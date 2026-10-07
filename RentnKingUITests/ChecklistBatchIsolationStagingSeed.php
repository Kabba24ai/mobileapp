<?php
// Staging-only seed for ChecklistBatchIsolationUITests. NEVER run against production.
//
//   BATCH_BASE=9410 DB_DATABASE=<staging> APP_ENV=staging \
//     php artisan tinker --execute="require '<path>/ChecklistBatchIsolationStagingSeed.php';"
//
// Synthetic orders BASE+1 … BASE+8 for the staging driver (driver@staging.local) at Bon Aqua,
// three equipment lines each — "Batch Alpha/Bravo/Charlie", units CB<order>-A/B/C — on one
// template (Q1 body damage, required; "Damaged" costs 150 on return. Q2 keys, optional).
// Units are hour-tracked (is_tracked = Yes): the checklist shows a prefilled hours row
// (start 100, end 130) — an operational default that alone never makes a line "entered".
//
//   +1  delivery, Combine ON     D1 → D2 → D2b (one install: the draft carries over)
//   +2  delivery, Combine OFF    D3
//   +3  delivery, C has NO unit  D4
//   +4  return,   Combine ON     R1   (all three delivered here, through the API)
//   +5  return,   Combine OFF    R2   (all three delivered here)
//   +6  delivery, A+B delivered here; a FRESH install (another phone) finishes C        N1
//   +7  return,   all delivered, B returned here; another phone returns A/C (Orders list) N2
//   +8  delivery, photo for B lands on B; A delivered, then its leg REOPENED (new cycle)  N3
//
// "Delivered/returned here" goes through the real mobile API (in-process HTTP kernel, as the
// staging driver): GET orders/checklists/context/{line}/{leg} → POST …/{execution}/complete.

use App\Models\ChecklistManagement\ChecklistMaster\ChecklistMaster;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminCategory;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminQuestion;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminQuestionAnswer;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminTemplate;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminTemplateQuestion;
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

$base = (int) (getenv('BATCH_BASE') ?: 9410);
$numbers = range($base + 1, $base + 8);
$driver = User::where('email', 'driver@staging.local')->firstOrFail();
$storeId = 36;                                     // Bon Aqua (staging)
$customerId = 303; $customerName = 'P6 Test Customer 1';

if (Order::whereIn('order_number', array_map('strval', $numbers))->exists()) { echo "ALREADY SEEDED for base {$base}\n"; return; }

$ids = DB::transaction(function () use ($numbers, $base, $driver, $storeId, $customerId, $customerName) {
    $category = CustomerAdminCategory::create(['category_name' => "Batch Isolation Condition {$base}"]);
    $q1 = CustomerAdminQuestion::create(['question_name' => "Batch body damage {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Any body damage at delivery?', 'question_return_text' => 'Any body damage at return?', 'required_question' => true]);
    $q1ok = CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No damage', 'answer_return_text' => 'No damage', 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Damaged', 'answer_return_text' => 'Damaged', 'question_id' => $q1->id, 'index_number' => 2, 'is_damaged' => true, 'return_amt' => 150]);
    $q2 = CustomerAdminQuestion::create(['question_name' => "Batch keys {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Keys handed over?', 'question_return_text' => 'Keys returned?', 'required_question' => false]);
    $q2yes = CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Yes', 'answer_return_text' => 'Yes', 'question_id' => $q2->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No', 'answer_return_text' => 'No', 'question_id' => $q2->id, 'index_number' => 2]);
    $template = CustomerAdminTemplate::create(['template_name' => "Batch Isolation Checklist {$base}", 'active_template' => true]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q2->id, 'index_number' => 2]);
    $master = ChecklistMaster::create(['checklist_system_name' => "Batch Isolation Master {$base}", 'customer_admin_template_id' => $template->id]);

    $lines = [];
    foreach ($numbers as $number) {
        $order = Order::create(['order_number' => (string) $number, 'order_date' => now()->format('Y-m-d'),
            'customer_name' => $customerName, 'customer_id' => $customerId, 'grand_total' => 300]);
        foreach (['A' => 'Alpha', 'B' => 'Bravo', 'C' => 'Charlie'] as $letter => $word) {
            $product = Product::create(['product_name' => "Batch {$word}", 'slug' => "batch-{$number}-" . strtolower($letter) . '-' . uniqid(), 'product_type' => 'Rental']);
            $line = OrderProduct::create(['order_id' => $order->id, 'product_id' => $product->id, 'product_name' => "Batch {$word}",
                'price' => 100, 'quantity' => 1, 'total' => 100, 'delivery_date' => now()->format('Y-m-d'),
                'delivery_status' => 'Pending', 'pickup_status' => 'Pending', 'delivery_transport_mode' => 'Truck', 'pickup_transport_mode' => 'Truck',
                'delivery_store_id' => $storeId, 'pickup_store_id' => $storeId, 'hour_tracking' => 'Yes', 'start_hours' => 100,
                'product_data' => ['product_type' => 'Rental', 'product_variant' => 'daily', 'product_rental_items_prices' => [], 'product_option_items' => []]]);
            $unit = null;
            if (! ($number === $base + 3 && $letter === 'C')) {             // BASE+3's Charlie has no unit
                $unit = Equipment::create(['equipment_name' => "{$word} Unit", 'equipment_id' => "CB{$number}-{$letter}", 'brand' => 'Bobcat',
                    'current_status' => 'available', 'checklist_master_id' => $master->id, 'power_source_type' => null,
                    'hour_tracking' => 'Yes', 'is_tracked' => 'Yes', 'overage_rate' => '10', 'store_id' => $storeId]);
                EquipmentSoftAssign::create(['equipment_id' => $unit->id, 'order_id' => $order->id, 'order_product_id' => $line->id, 'assigned_by' => $driver->id]);
            }
            $lines[$number][$letter] = ['line' => $line->unique_id, 'unit' => $unit?->unique_id];
        }
    }
    return ['lines' => $lines, 'q1' => $q1->unique_id, 'q1ok' => $q1ok->unique_id, 'q2' => $q2->unique_id, 'q2yes' => $q2yes->unique_id];
});

// ── Canonical completions as the phone sends them (in-process, staging driver) ─────────────
$http = app(Illuminate\Contracts\Http\Kernel::class);
$api = 'https://' . config('app.domains.api') . '/api/admin/v1/';
$sig = tempnam(sys_get_temp_dir(), 'sig') . '.png';
$canvas = imagecreatetruecolor(300, 120);                      // a signature-sized stroke
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
$complete = function (array $l, string $leg) use ($call, $ids, $sig, $driver, $storeId) {
    [$s, $context] = $call('GET', "orders/checklists/context/{$l['line']}/{$leg}");
    $execution = $context['data']['identity']['checklist_execution_id'] ?? null;
    if ($s !== 200 || ! $execution) { echo "context {$leg} {$l['line']} → {$s}\n"; return; }
    $fields = ['order_product_unique_id' => $l['line'], 'user_id' => $driver->id,
        'answers' => [['question_id' => $ids['q1'], 'answer_id' => $ids['q1ok']], ['question_id' => $ids['q2'], 'answer_id' => $ids['q2yes']]]];
    $fields += $leg === 'delivery' ? ['equipment_unique_id' => $l['unit'], 'start_hours' => '100'] : ['store_id' => $storeId, 'end_hours' => '130'];
    [$s, $body] = $call('POST', "orders/checklists/{$execution}/complete", $fields,
        ['signature_media' => new UploadedFile($sig, 'signature.png', 'image/png', null, true)]);
    echo "  {$leg} {$l['line']} → {$s}\n";
};
$L = $ids['lines'];
foreach ([$base + 4, $base + 5, $base + 7] as $n) foreach (['A', 'B', 'C'] as $x) $complete($L[$n][$x], 'delivery');
foreach (['A', 'B'] as $x) $complete($L[$base + 6][$x], 'delivery');
$complete($L[$base + 7]['B'], 'return');
// Return legs get their prefilled reading (the hours default the return checklist shows).
OrderProduct::whereHas('order', fn ($q) => $q->whereIn('order_number', [(string) ($base + 4), (string) ($base + 5), (string) ($base + 7)]))->update(['end_hours' => 130]);

foreach ($L as $number => $byLetter) {
    foreach ($byLetter as $letter => $l) echo "{$number} {$letter} line={$l['line']} unit=" . ($l['unit'] ?? '-') . "\n";
}

/*
 * Verify a line's independence after each UI test (staging DB):
 *   SELECT op.product_name, e.leg, e.cycle, e.status, e.signature_media_id FROM order_product_checklist_executions e
 *     JOIN order_products op ON op.id = e.order_product_id JOIN orders o ON o.id = op.order_id WHERE o.order_number = ?;
 *   mobile_operations JOIN order_product_checklist_executions ON e.id = resource_id (resource_type = checklist_execution)
 *     -- no operation for an untouched line;  billing_charges / customer_damage_stagings by order_product_id
 *     -- a damage charge only on the damaged line;  order media by order_product_id -- a photo only on its line.
 */
