<?php
// Staging-only seed for the fuel/DEF scenarios in ChecklistBatchIsolationUITests (F1–F3).
// NEVER run against production.
//
//   FUEL_BASE=9500 DB_DATABASE=<staging> APP_ENV=staging \
//     php artisan tinker --execute="require '<path>/FuelDEFStagingSeed.php';"
//
// Prices are set to production's System Configuration (diesel 6.50, gas 4.25, DEF 3.98 per
// gallon) so the totals below are the production arithmetic. Units are not hour-tracked.
//
//   +1  delivery   A "Fuel DEF Machine" FD<n>-A (diesel 32 gal + DEF 5 gal), B "Fuel Trailer" (no
//                  power source)                                                           F1
//   +2  return     A DEF machine delivered here with diesel Full + DEF Full; B trailer;
//                  C DEF machine delivered here with diesel Full and NO DEF level (a delivery
//                  made before DEF readings existed). Expected return (diesel 1/2, DEF 1/2):
//                  A $104.00 + $9.95 = $113.95 · B $0.00 · C $104.00 (DEF never assumed)  F2
//   +3  delivery   A DEF machine against a server WITHOUT DEF readings → one fuel row      F3
//
// "Delivered here" goes through the real mobile API (in-process HTTP kernel, staging driver).

use App\Models\ChecklistManagement\ChecklistMaster\ChecklistMaster;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminCategory;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminQuestion;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminQuestionAnswer;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminTemplate;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminTemplateQuestion;
use App\Models\Configurations\Setting;
use App\Models\Iam\Personnel\User;
use App\Models\MaintenanceManagement\Equipment;
use App\Models\MaintenanceManagement\EquipmentSoftAssign;
use App\Models\Orders\Order;
use App\Models\Orders\OrderProduct;
use App\Models\ProductManagement\Product;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\TransientToken;

if (app()->environment('production')) { echo "REFUSED: production\n"; return; }

$base = (int) (getenv('FUEL_BASE') ?: 9500);
$numbers = range($base + 1, $base + 3);
$driver = User::where('email', 'driver@staging.local')->firstOrFail();
$storeId = 36;                                     // Bon Aqua (staging)
$customerId = 303; $customerName = 'P6 Test Customer 1';

if (Order::whereIn('order_number', array_map('strval', $numbers))->exists()) { echo "ALREADY SEEDED for base {$base}\n"; return; }

foreach (['diesel_price_per_gallon' => '6.50', 'gas_price_per_gallon' => '4.25', 'def_price_per_gallon' => '3.98'] as $name => $value) {
    Setting::updateOrCreate(['setting_name' => $name], ['setting_type' => 'Price Settings', 'value_type' => 'text', 'setting_title' => $name, 'setting_value' => $value]);
}

$ids = DB::transaction(function () use ($numbers, $base, $driver, $storeId, $customerId, $customerName) {
    $category = CustomerAdminCategory::create(['category_name' => "Fuel DEF Condition {$base}"]);
    $q1 = CustomerAdminQuestion::create(['question_name' => "Fuel body damage {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Any body damage at delivery?', 'question_return_text' => 'Any body damage at return?', 'required_question' => true]);
    $q1ok = CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No damage', 'answer_return_text' => 'No damage', 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Damaged', 'answer_return_text' => 'Damaged', 'question_id' => $q1->id, 'index_number' => 2, 'is_damaged' => true, 'return_amt' => 150]);
    $template = CustomerAdminTemplate::create(['template_name' => "Fuel DEF Checklist {$base}", 'active_template' => true]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q1->id, 'index_number' => 1]);
    $master = ChecklistMaster::create(['checklist_system_name' => "Fuel DEF Master {$base}", 'customer_admin_template_id' => $template->id]);

    $lines = [];
    foreach ($numbers as $number) {
        $order = Order::create(['order_number' => (string) $number, 'order_date' => now()->format('Y-m-d'),
            'customer_name' => $customerName, 'customer_id' => $customerId, 'grand_total' => 300]);
        $layout = $number === $base + 2
            ? ['A' => 'Fuel DEF Machine', 'B' => 'Fuel Trailer', 'C' => 'Fuel DEF Second']
            : ($number === $base + 1 ? ['A' => 'Fuel DEF Machine', 'B' => 'Fuel Trailer'] : ['A' => 'Fuel DEF Machine']);
        foreach ($layout as $letter => $name) {
            $product = Product::create(['product_name' => $name, 'slug' => "fuel-{$number}-" . strtolower($letter) . '-' . uniqid(), 'product_type' => 'Rental']);
            $line = OrderProduct::create(['order_id' => $order->id, 'product_id' => $product->id, 'product_name' => $name,
                'price' => 100, 'quantity' => 1, 'total' => 100, 'delivery_date' => now()->format('Y-m-d'),
                'delivery_status' => 'Pending', 'pickup_status' => 'Pending', 'delivery_transport_mode' => 'Truck', 'pickup_transport_mode' => 'Truck',
                'delivery_store_id' => $storeId, 'pickup_store_id' => $storeId, 'hour_tracking' => 'No',
                'product_data' => ['product_type' => 'Rental', 'product_variant' => 'daily', 'product_rental_items_prices' => [], 'product_option_items' => []]]);
            $machine = $letter !== 'B';
            $unit = Equipment::create(['equipment_name' => $name . ' Unit', 'equipment_id' => "FD{$number}-{$letter}", 'brand' => 'Takeuchi',
                'current_status' => 'available', 'checklist_master_id' => $master->id,
                'power_source_type' => $machine ? 'diesel' : null, 'has_def' => $machine ? 'Yes' : 'No',
                'diesel_tank_capacity' => $machine ? 32 : null, 'def_tank_capacity' => $machine ? 5 : null,
                'hour_tracking' => 'No', 'is_tracked' => 'No', 'store_id' => $storeId]);
            EquipmentSoftAssign::create(['equipment_id' => $unit->id, 'order_id' => $order->id, 'order_product_id' => $line->id, 'assigned_by' => $driver->id]);
            $lines[$number][$letter] = ['line' => $line->unique_id, 'unit' => $unit->unique_id];
        }
    }
    return ['lines' => $lines, 'q1' => $q1->unique_id, 'q1ok' => $q1ok->unique_id];
});

$http = app(Illuminate\Contracts\Http\Kernel::class);
$api = 'https://' . config('app.domains.api') . '/api/admin/v1/';
$sig = tempnam(sys_get_temp_dir(), 'sig') . '.png';
$canvas = imagecreatetruecolor(300, 120);
imagefill($canvas, 0, 0, imagecolorallocate($canvas, 255, 255, 255));
imageline($canvas, 20, 90, 280, 30, imagecolorallocate($canvas, 0, 0, 0));
imagepng($canvas, $sig);
$call = function (string $method, string $path, array $fields = [], array $files = []) use ($http, $api, $driver) {
    app('auth')->forgetGuards();
    app('auth')->guard('api_user')->setUser($driver->withAccessToken(new TransientToken()));
    $request = Request::create($api . $path, $method, $fields, [], $files, ['HTTP_ACCEPT' => 'application/json', 'HTTP_X_OPERATION_ID' => 'seed-' . uniqid()]);
    $response = $http->handle($request);
    return [$response->getStatusCode(), json_decode((string) $response->getContent(), true)];
};
$deliver = function (array $l, array $extra) use ($call, $ids, $sig, $driver) {
    [$s, $context] = $call('GET', "orders/checklists/context/{$l['line']}/delivery");
    $execution = $context['data']['identity']['checklist_execution_id'] ?? null;
    if ($s !== 200 || ! $execution) { echo "context delivery {$l['line']} → {$s}\n"; return; }
    $fields = ['order_product_unique_id' => $l['line'], 'user_id' => $driver->id, 'equipment_unique_id' => $l['unit'],
        'answers' => [['question_id' => $ids['q1'], 'answer_id' => $ids['q1ok']]]] + $extra;
    [$s, $body] = $call('POST', "orders/checklists/{$execution}/complete", $fields,
        ['signature_media' => new UploadedFile($sig, 'signature.png', 'image/png', null, true)]);
    echo "  delivery {$l['line']} → {$s}\n";
};
$L = $ids['lines'];
$deliver($L[$base + 2]['A'], ['fuel_initial_reading' => '9', 'def_initial_reading' => '9']);
$deliver($L[$base + 2]['B'], []);
$deliver($L[$base + 2]['C'], ['fuel_initial_reading' => '9']);

foreach ($L as $number => $byLetter) {
    foreach ($byLetter as $letter => $l) echo "{$number} {$letter} line={$l['line']} unit={$l['unit']}\n";
}
