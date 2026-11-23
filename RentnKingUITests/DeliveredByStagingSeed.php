<?php
// Staging-only seed for DeliveredByUITests (Rent 'n King order #5657, 2026-11-23). NEVER run against production.
//
//   DELIVERED_BY_BASE=9750 APP_TIMEZONE=America/Chicago APP_ENV=testing DB_DATABASE=<staging> \
//     php artisan tinker --execute="require '<path>/DeliveredByStagingSeed.php';"
//
// #5657: a cab skid steer assigned to a driver and a grapple with NO driver (delivered from the
// store), both prepared in the yard by a non-driver employee. On the phone the combined
// checklist's Delivered By was blank (it copied the grapple's) and, opened from Dispatch, the
// picker did nothing. Orders (today, Chicago time):
//
//   +1  skid steer (driver Dana) + grapple (no driver)    combined; pick "Olive Oldest"      D1
//   +2  the same two lines                                 separate; pick "Yara Yard" on line 1 D2
//   +3  skid steer only (driver Dana)                      single; keep the driver           D3
//
// Both lines of every order are PREPARED by Yara (yard, not a driver) through the real API, and
// Dana's lines are set On My Way → Arrived, so Dispatch's Start Delivery opens Main Order at the
// customer site, as in production.
//
// Accounts (password deliveredby-pass-123): driver@deliveredby.local (Dana Driver, signed in on
// the phone), yard@deliveredby.local (Yara Yard). "Olive Oldest" is created BEFORE
// DELIVERED_BY_FILLERS (default 110) newer active employees, so she is NOT on the first page of
// POST users (100 per page, newest first): she can only be picked when the phone reads every page.
// Nobody here is a real person.

use App\Models\ChecklistManagement\ChecklistMaster\ChecklistMaster;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminCategory;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminQuestion;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminQuestionAnswer;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminTemplate;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminTemplateQuestion;
use App\Models\Customers\Customer;
use App\Models\Iam\Personnel\User;
use App\Models\MaintenanceManagement\Equipment;
use App\Models\MaintenanceManagement\EquipmentSoftAssign;
use App\Models\Orders\Order;
use App\Models\Orders\OrderProduct;
use App\Models\ProductManagement\Product;
use App\Models\Stores\Store;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\TransientToken;

if (app()->environment('production')) { echo "REFUSED: production\n"; return; }

$base = (int) (getenv('DELIVERED_BY_BASE') ?: 9750);
$fillers = (int) (getenv('DELIVERED_BY_FILLERS') ?: 110);
$numbers = [$base + 1, $base + 2, $base + 3];
if (Order::whereIn('order_number', array_map('strval', $numbers))->exists()) { echo "ALREADY SEEDED for base {$base}\n"; return; }

$person = function (string $email, string $first, string $last): User {
    return User::where('email', $email)->first() ?? User::create([
        'first_name' => $first, 'last_name' => $last, 'email' => $email, 'status' => 'Active',
        'password' => bcrypt('deliveredby-pass-123'),
    ]);
};
$olive = $person('oldest@deliveredby.local', 'Olive', 'Oldest');                 // first: the lowest id
for ($i = 1; $i <= $fillers; $i++) {
    $person(sprintf('filler-%03d@deliveredby.local', $i), 'Filler', sprintf('Employee %03d', $i));
}
$dana = $person('driver@deliveredby.local', 'Dana', 'Driver');
$yara = $person('yard@deliveredby.local', 'Yara', 'Yard');
User::whereKey($dana->id)->update(['is_driver' => true]);                        // Dispatch lists drivers only
$newer = User::active()->where('id', '>', $olive->id)->count();
echo "Olive Oldest id={$olive->id}: {$newer} newer active employees (" . ($newer >= 100 ? 'beyond page 1' : 'STILL ON PAGE 1 — add fillers') . ")\n";

$ids = DB::transaction(function () use ($numbers, $base, $dana, $yara) {
    $store = Store::where('store_name', 'Delivered By Yard')->first() ?? Store::create(['store_name' => 'Delivered By Yard', 'status' => 'Active']);
    $customer = Customer::create(['first_name' => 'Delivered', 'last_name' => 'Customer', 'email' => "delivered-by-{$base}@test.local"]);

    $category = CustomerAdminCategory::create(['category_name' => "Delivered By Condition {$base}"]);
    $q1 = CustomerAdminQuestion::create(['question_name' => "Delivered by body damage {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Any body damage at delivery?', 'question_return_text' => 'Any body damage at return?', 'required_question' => true]);
    $q1ok = CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No damage', 'answer_return_text' => 'No damage', 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Damaged', 'answer_return_text' => 'Damaged', 'question_id' => $q1->id, 'index_number' => 2, 'is_damaged' => true, 'return_amt' => 150]);
    $q2 = CustomerAdminQuestion::create(['question_name' => "Delivered by keys {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Keys handed over?', 'question_return_text' => 'Keys returned?', 'required_question' => false]);
    $q2yes = CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Yes', 'answer_return_text' => 'Yes', 'question_id' => $q2->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No', 'answer_return_text' => 'No', 'question_id' => $q2->id, 'index_number' => 2]);
    $template = CustomerAdminTemplate::create(['template_name' => "Delivered By Checklist {$base}", 'active_template' => true]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q2->id, 'index_number' => 2]);
    $master = ChecklistMaster::create(['checklist_system_name' => "Delivered By Master {$base}", 'customer_admin_template_id' => $template->id]);

    $shapes = [
        $base + 1 => [['Skid Steer w/Cab', $dana->id, 'Truck', 'SS'], ['Skid Steer - Grapple', null, 'Store', 'GR']],
        $base + 2 => [['Skid Steer w/Cab', $dana->id, 'Truck', 'SS'], ['Skid Steer - Grapple', null, 'Store', 'GR']],
        $base + 3 => [['Skid Steer w/Cab', $dana->id, 'Truck', 'SS']],
    ];
    $lines = [];
    foreach ($shapes as $number => $shape) {
        $order = Order::create(['order_number' => (string) $number, 'order_date' => now()->format('Y-m-d'),
            'customer_name' => 'Delivered Customer', 'customer_id' => $customer->id, 'grand_total' => 400]);
        foreach ($shape as [$name, $driver, $transport, $code]) {
            $product = Product::create(['product_name' => $name, 'slug' => "delivered-by-{$number}-{$code}-" . uniqid(), 'product_type' => 'Rental']);
            $line = OrderProduct::create(['order_id' => $order->id, 'product_id' => $product->id, 'product_name' => $name,
                'price' => 100, 'quantity' => 1, 'total' => 100, 'delivery_date' => now()->format('Y-m-d'),
                'delivery_status' => 'Pending', 'pickup_status' => 'Pending', 'delivery_transport_mode' => $transport, 'pickup_transport_mode' => 'Truck',
                'delivery_store_id' => $store->id, 'pickup_store_id' => $store->id, 'hour_tracking' => 'No', 'delivery_by' => $driver,
                'product_data' => ['product_type' => 'Rental', 'product_variant' => 'daily', 'product_rental_items_prices' => [], 'product_option_items' => []]]);
            $unit = Equipment::create(['equipment_name' => $name, 'equipment_id' => "DB{$number}-{$code}", 'brand' => 'Takeuchi',
                'current_status' => 'available', 'checklist_master_id' => $master->id, 'power_source_type' => null,
                'hour_tracking' => 'No', 'store_id' => $store->id, 'assigned_product_id' => $product->id]);
            EquipmentSoftAssign::create(['equipment_id' => $unit->id, 'order_id' => $order->id, 'order_product_id' => $line->id, 'assigned_by' => $yara->id]);
            $lines[] = ['number' => $number, 'order_id' => $order->id, 'line' => $line->unique_id, 'name' => $name, 'driver' => $driver];
        }
    }

    return ['lines' => $lines, 'q1' => $q1->unique_id, 'q1ok' => $q1ok->unique_id, 'q2' => $q2->unique_id, 'q2yes' => $q2yes->unique_id];
});

// ── The yard (Yara prepares every line) and the trip (Dana drives her lines), through the real mobile API ──
$http = app(Illuminate\Contracts\Http\Kernel::class);
$api = 'https://' . config('app.domains.api') . '/api/admin/v1/';
$call = function (User $as, string $method, string $path, array $fields = []) use ($http, $api) {
    app('auth')->forgetGuards();
    app('auth')->guard('api_user')->setUser($as->withAccessToken(new TransientToken()));
    $request = Request::create($api . $path, $method, $fields, [], [], ['HTTP_ACCEPT' => 'application/json', 'HTTP_X_OPERATION_ID' => 'seed-' . bin2hex(random_bytes(10))]);
    $response = $http->handle($request);
    return [$response->getStatusCode(), json_decode((string) $response->getContent(), true)];
};

foreach ($ids['lines'] as $l) {
    [$s, $context] = $call($yara, 'GET', "orders/checklists/context/{$l['line']}/delivery");
    $execution = $context['data']['identity']['checklist_execution_id'] ?? null;
    [$s2] = $call($yara, 'POST', "orders/checklists/{$execution}/prepare", [
        'order_product_unique_id' => $l['line'], 'user_id' => $yara->id, 'mark_staged' => false,
        'answers' => [['question_id' => $ids['q1'], 'answer_id' => $ids['q1ok']], ['question_id' => $ids['q2'], 'answer_id' => $ids['q2yes']]],
    ]);
    $trip = '';
    if ($l['driver']) {
        [$s3] = $call($dana, 'POST', 'orders/schedules/driver-checklist', ['order_product_unique_id' => $l['line'], 'checklist_type' => 'delivery', 'equipment_driver_status' => 'On My Way']);
        [$s4] = $call($dana, 'POST', 'orders/schedules/driver-checklist', ['order_product_unique_id' => $l['line'], 'checklist_type' => 'delivery', 'equipment_driver_status' => 'Arrived']);
        $trip = " on_my_way={$s3} arrived={$s4}";
    }
    echo "{$l['number']} (order id {$l['order_id']}) {$l['name']} line={$l['line']} driver=" . ($l['driver'] ?? 'none') . " execution={$execution} context={$s} prepare={$s2}{$trip}\n";
}
echo "accounts: driver@deliveredby.local / yard@deliveredby.local (deliveredby-pass-123); Dana id={$dana->id}, Yara id={$yara->id}, Olive id={$olive->id}\n";
