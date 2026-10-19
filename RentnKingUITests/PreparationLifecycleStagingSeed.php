<?php
// Staging-only seed for PreparationLifecycleUITests (test02, A, B, C, E, D, H1, H2, H3). NEVER run
// against production.
//
//   PL_BASE=9430 DB_DATABASE=<staging> APP_ENV=staging \
//     php artisan tinker --execute="require '<path>/PreparationLifecycleStagingSeed.php';"
//
// One Product Category holding ONLY this fixture's units, so the substitution picker (category-
// scoped to the assigned unit) lists exactly them — hour-tracked diesel units, so the checklist
// shows the fuel and hours rows the scenarios fill:
//   EXC-A / EXC-B / EXC-C   "Mini Excavator EXC-A" …   (A → B → C → A substitutions, restarts)
//   EXC-H1 / EXC-X          the multi-line order's units (H2 substitutes EXC-H1 → EXC-C)
// Orders on driver@staging.local's Queue Line board (Rental, Pending, delivery today, Truck, Bon Aqua):
//   PL_BASE+1  "Cody Cash"    one line on EXC-A                 test02 → A → B → C → E → D
//   PL_BASE+2  "Hana Hughes"  two lines on EXC-H1 and EXC-X     H1 → H2 → H3
// Template: "Any body damage at delivery?" (No damage / Damaged, required) + "Keys handed over?".
// Each line's delivery driver (delivery_by) is the staging driver, as Dispatch assigns it — the
// checklist prefills "Delivered By" from it (the footer picker is not reachable by XCUITest).
// Run the scenarios in that order against one fresh seed; the runner checks executions, cycles,
// soft assignments and the staged latch between them.

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
use App\Models\ProductManagement\ProductCategory;
use Illuminate\Support\Facades\DB;

if (app()->environment('production')) { echo "REFUSED: production\n"; return; }

$base = (int) (getenv('PL_BASE') ?: 9430);
$driver = User::where('email', 'driver@staging.local')->firstOrFail();
$storeId = 36;                                     // Bon Aqua (staging)

if (Equipment::whereIn('equipment_id', ['EXC-A', 'EXC-B', 'EXC-C', 'EXC-H1', 'EXC-X'])->exists()
    || Order::whereIn('order_number', [(string) ($base + 1), (string) ($base + 2)])->exists()) {
    echo "ALREADY SEEDED (EXC units or orders {$base}+1/+2 exist)\n"; return;
}

$out = DB::transaction(function () use ($base, $driver, $storeId) {
    $category = CustomerAdminCategory::create(['category_name' => "Prep Lifecycle Condition {$base}"]);
    $q1 = CustomerAdminQuestion::create(['question_name' => "Prep body damage {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Any body damage at delivery?', 'question_return_text' => 'Any body damage at return?', 'required_question' => true]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No damage', 'answer_return_text' => 'No damage', 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Damaged', 'answer_return_text' => 'Damaged', 'question_id' => $q1->id, 'index_number' => 2, 'is_damaged' => true, 'return_amt' => 150]);
    $q2 = CustomerAdminQuestion::create(['question_name' => "Prep keys {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Keys handed over?', 'question_return_text' => 'Keys returned?', 'required_question' => false]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Yes', 'answer_return_text' => 'Yes', 'question_id' => $q2->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No', 'answer_return_text' => 'No', 'question_id' => $q2->id, 'index_number' => 2]);
    $template = CustomerAdminTemplate::create(['template_name' => "Prep Lifecycle Checklist {$base}", 'active_template' => true]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q2->id, 'index_number' => 2]);
    $master = ChecklistMaster::create(['checklist_system_name' => "Prep Lifecycle Master {$base}", 'customer_admin_template_id' => $template->id]);

    $equipmentCategory = ProductCategory::create(['title' => "Prep Lifecycle Excavators {$base}",
        'slug' => "prep-lifecycle-excavators-{$base}-" . uniqid(), 'status' => 'Draft', 'is_featured' => 'No']);
    $product = Product::create(['product_name' => 'Mini Excavator', 'slug' => "prep-lifecycle-mini-excavator-{$base}-" . uniqid(), 'product_type' => 'Rental']);

    $units = [];
    foreach (['EXC-A', 'EXC-B', 'EXC-C', 'EXC-H1', 'EXC-X'] as $code) {
        $units[$code] = Equipment::create(['equipment_name' => "Mini Excavator {$code}", 'equipment_id' => $code, 'brand' => 'Kubota',
            'current_status' => 'available', 'checklist_master_id' => $master->id, 'power_source_type' => 'diesel',
            'hour_tracking' => 'Yes', 'is_tracked' => 'Yes', 'overage_rate' => '10', 'store_id' => $storeId,
            'product_category_id' => $equipmentCategory->id]);
    }

    $customer = function (string $first, string $last) {
        return Customer::create(['first_name' => $first, 'last_name' => $last,
            'email' => strtolower("{$first}.{$last}") . '+' . uniqid() . '@staging.local']);
    };
    $orders = [
        $base + 1 => [$customer('Cody', 'Cash'), ['EXC-A']],
        $base + 2 => [$customer('Hana', 'Hughes'), ['EXC-H1', 'EXC-X']],
    ];
    $lines = [];
    foreach ($orders as $number => [$who, $codes]) {
        $order = Order::create(['order_number' => (string) $number, 'order_date' => now()->format('Y-m-d'),
            'customer_name' => "{$who->first_name} {$who->last_name}", 'customer_id' => $who->id, 'grand_total' => 400]);
        foreach ($codes as $code) {
            $line = OrderProduct::create(['order_id' => $order->id, 'product_id' => $product->id, 'product_name' => 'Mini Excavator',
                'price' => 200, 'quantity' => 1, 'total' => 200, 'delivery_date' => now()->format('Y-m-d'),
                'delivery_status' => 'Pending', 'pickup_status' => 'Pending', 'delivery_transport_mode' => 'Truck', 'pickup_transport_mode' => 'Truck',
                'delivery_store_id' => $storeId, 'pickup_store_id' => $storeId, 'hour_tracking' => 'Yes',
                'delivery_by' => $driver->id,          // the dispatch-assigned driver prefills "Delivered By"
                'product_data' => ['product_type' => 'Rental', 'product_variant' => 'daily', 'product_rental_items_prices' => [], 'product_option_items' => []]]);
            EquipmentSoftAssign::create(['equipment_id' => $units[$code]->id, 'order_id' => $order->id, 'order_product_id' => $line->id, 'assigned_by' => $driver->id]);
            $lines[] = "{$number} {$code} line={$line->unique_id} unit={$units[$code]->unique_id}";
        }
    }
    return $lines;
});

foreach ($out as $row) echo $row . "\n";

/*
 * Verify after each scenario (staging DB):
 *   SELECT o.order_number, op.unique_id, e.leg, e.cycle, e.status, eq.equipment_id, e.prepared_at IS NOT NULL prepared
 *     FROM order_product_checklist_executions e JOIN order_products op ON op.id = e.order_product_id
 *     JOIN orders o ON o.id = op.order_id LEFT JOIN equipment eq ON eq.id = e.equipment_id
 *    WHERE o.order_number IN (?, ?) ORDER BY op.id, e.cycle;
 *   equipment_soft_assigns by order_product_id (the unit kept / switched);  queue_line_items.staged_at (the latch).
 */
