<?php
// Staging-only seed for CustomerSiteVideoSyncUITests. NEVER run against production.
//
//   VIDEO_BASE=9600 DB_DATABASE=<staging> APP_ENV=<staging|testing> \
//     php artisan tinker --execute="require '<path>/CustomerSiteVideoSyncStagingSeed.php';"
//
// The reported case (2026-11-14): Employee A prepares the delivery checklist in the yard on
// their phone; Employee B, who never opened that checklist, films the walk-around from Main
// Order at the customer site, so the upload names no cycle. Three one-line orders, each
// prepared by A through the real API and then set On My Way → Arrived (the customer site):
//
//   +1  B films; B's local sync record is then deleted; B submits the checklist    V1
//   +2  B films; B relaunches the app; B submits                                    V2
//   +3  B films; a FRESH install signed in as C (another phone) submits             V3
//
// Accounts (password video-pass-123): yard-a@videosync.local (A), driver-b@videosync.local (B),
// driver-c@videosync.local (C). The legs start UNASSIGNED, so B's phone has no cached checklist
// for them (the offline mission cache prefetches a driver's assigned stops) and B's upload names
// no cycle. After V0 the runner assigns BASE+1/+2 to B and BASE+3 to C (another driver takes the
// stop over), which puts them on Dispatch, where Start Delivery opens Main Order at Arrived:
//   UPDATE order_products op JOIN orders o ON o.id = op.order_id SET op.delivery_by = <B|C> WHERE o.order_number = ?;
// Server checks between steps: see the footer.

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

$base = (int) (getenv('VIDEO_BASE') ?: 9600);
$numbers = range($base + 1, $base + 5);
if (Order::whereIn('order_number', array_map('strval', $numbers))->exists()) { echo "ALREADY SEEDED for base {$base}\n"; return; }

$person = function (string $email, string $first, string $last): User {
    return User::where('email', $email)->first() ?? User::create([
        'first_name' => $first, 'last_name' => $last, 'email' => $email, 'status' => 'Active',
        'password' => bcrypt('video-pass-123'),
    ]);
};
$a = $person('yard-a@videosync.local', 'Avery', 'Yard');
$b = $person('driver-b@videosync.local', 'Blake', 'Driver');
$c = $person('driver-c@videosync.local', 'Casey', 'Driver');
User::whereKey([$b->id, $c->id])->update(['is_driver' => true]);   // Dispatch lists drivers only

$ids = DB::transaction(function () use ($numbers, $base, $a, $b) {
    $store = Store::where('store_name', 'Video Sync Yard')->first() ?? Store::create(['store_name' => 'Video Sync Yard', 'status' => 'Active']);
    $customer = Customer::create(['first_name' => 'Video', 'last_name' => 'Customer', 'email' => "video-customer-{$base}@test.local"]);

    $category = CustomerAdminCategory::create(['category_name' => "Video Sync Condition {$base}"]);
    $q1 = CustomerAdminQuestion::create(['question_name' => "Video sync body damage {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Any body damage at delivery?', 'question_return_text' => 'Any body damage at return?', 'required_question' => true]);
    $q1ok = CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No damage', 'answer_return_text' => 'No damage', 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Damaged', 'answer_return_text' => 'Damaged', 'question_id' => $q1->id, 'index_number' => 2, 'is_damaged' => true, 'return_amt' => 150]);
    $q2 = CustomerAdminQuestion::create(['question_name' => "Video sync keys {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Keys handed over?', 'question_return_text' => 'Keys returned?', 'required_question' => false]);
    $q2yes = CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Yes', 'answer_return_text' => 'Yes', 'question_id' => $q2->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No', 'answer_return_text' => 'No', 'question_id' => $q2->id, 'index_number' => 2]);
    $template = CustomerAdminTemplate::create(['template_name' => "Video Sync Checklist {$base}", 'active_template' => true]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q2->id, 'index_number' => 2]);
    $master = ChecklistMaster::create(['checklist_system_name' => "Video Sync Master {$base}", 'customer_admin_template_id' => $template->id]);

    $lines = [];
    foreach ($numbers as $number) {
        $order = Order::create(['order_number' => (string) $number, 'order_date' => now()->format('Y-m-d'),
            'customer_name' => 'Video Customer', 'customer_id' => $customer->id, 'grand_total' => 200]);
        $product = Product::create(['product_name' => 'Video Sync Alpha', 'slug' => "video-sync-{$number}-" . uniqid(), 'product_type' => 'Rental']);
        $line = OrderProduct::create(['order_id' => $order->id, 'product_id' => $product->id, 'product_name' => 'Video Sync Alpha',
            'price' => 100, 'quantity' => 1, 'total' => 100, 'delivery_date' => now()->format('Y-m-d'),
            'delivery_status' => 'Pending', 'pickup_status' => 'Pending', 'delivery_transport_mode' => 'Truck', 'pickup_transport_mode' => 'Truck',
            'delivery_store_id' => $store->id, 'pickup_store_id' => $store->id, 'hour_tracking' => 'No',
            'delivery_by' => $number >= $base + 4 ? $b->id : null,
            'product_data' => ['product_type' => 'Rental', 'product_variant' => 'daily', 'product_rental_items_prices' => [], 'product_option_items' => []]]);
        $unit = Equipment::create(['equipment_name' => 'Alpha Unit', 'equipment_id' => "VS{$number}-A", 'brand' => 'Bobcat',
            'current_status' => 'available', 'checklist_master_id' => $master->id, 'power_source_type' => null,
            'hour_tracking' => 'No', 'store_id' => $store->id, 'assigned_product_id' => $product->id]);
        EquipmentSoftAssign::create(['equipment_id' => $unit->id, 'order_id' => $order->id, 'order_product_id' => $line->id, 'assigned_by' => $a->id]);
        $lines[$number] = ['line' => $line->unique_id, 'unit' => $unit->unique_id, 'order' => $order->unique_id];
    }

    return ['lines' => $lines, 'q1' => $q1->unique_id, 'q1ok' => $q1ok->unique_id, 'q2' => $q2->unique_id, 'q2yes' => $q2yes->unique_id];
});

// ── The yard and the trip, through the real mobile API (in-process) ─────────────────────────
$http = app(Illuminate\Contracts\Http\Kernel::class);
$api = 'https://' . config('app.domains.api') . '/api/admin/v1/';
$call = function (User $as, string $method, string $path, array $fields = []) use ($http, $api) {
    app('auth')->forgetGuards();
    app('auth')->guard('api_user')->setUser($as->withAccessToken(new TransientToken()));
    $request = Request::create($api . $path, $method, $fields, [], [], ['HTTP_ACCEPT' => 'application/json', 'HTTP_X_OPERATION_ID' => 'seed-' . bin2hex(random_bytes(10))]);
    $response = $http->handle($request);
    return [$response->getStatusCode(), json_decode((string) $response->getContent(), true)];
};

foreach ($ids['lines'] as $number => $l) {
    // A opens the delivery checklist in the yard and saves every answer (Prepared, not staged).
    [$s, $context] = $call($a, 'GET', "orders/checklists/context/{$l['line']}/delivery");
    $execution = $context['data']['identity']['checklist_execution_id'] ?? null;
    [$s2] = $call($a, 'POST', "orders/checklists/{$execution}/prepare", [
        'order_product_unique_id' => $l['line'], 'user_id' => $a->id, 'mark_staged' => false,
        'answers' => [['question_id' => $ids['q1'], 'answer_id' => $ids['q1ok']], ['question_id' => $ids['q2'], 'answer_id' => $ids['q2yes']]],
    ]);
    // The truck leaves and reaches the customer (B is driving).
    [$s3] = $call($b, 'POST', 'orders/schedules/driver-checklist', ['order_product_unique_id' => $l['line'], 'checklist_type' => 'delivery', 'equipment_driver_status' => 'On My Way']);
    [$s4] = $call($b, 'POST', 'orders/schedules/driver-checklist', ['order_product_unique_id' => $l['line'], 'checklist_type' => 'delivery', 'equipment_driver_status' => 'Arrived']);
    echo "{$number} line={$l['line']} unit={$l['unit']} execution={$execution} context={$s} prepare={$s2} on_my_way={$s3} arrived={$s4}\n";
}

/*
 * Server checks between steps (staging DB), per order number:
 *   SELECT e.unique_id, e.cycle, e.status, m.client_media_id, m.checklist_execution_id = e.id AS anchored, md.file_type
 *     FROM orders o JOIN order_products op ON op.order_id = o.id
 *     JOIN order_product_checklist_executions e ON e.order_product_id = op.id AND e.leg = 'delivery'
 *     LEFT JOIN order_media m ON m.order_product_id = op.id AND m.type = 'delivery'
 *     LEFT JOIN media md ON md.id = m.media_id
 *    WHERE o.order_number = ?;
 *   -- one cycle (A's), the video anchored to it; after V1–V3 the cycle is completed.
 * And the context as Employee C: GET orders/checklists/context/{line}/delivery →
 *   data.server_state.delivery_video_present = true.
 */
