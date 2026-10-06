<?php
// Staging-only seed (rc_kabba_staging) for the checklist batch-isolation UI smoke.
// Five synthetic orders, three equipment lines each (A/B/C), on Bon Aqua for the
// staging driver. Nothing here touches an existing order.
//
//   9401  delivery, Combine ON   (untouched / shared-only / only C / A then B)
//   9402  delivery, Combine OFF  (A+B, per-row employee + signature)
//   9403  delivery, C has NO unit (partial no-unit + partial B focus)
//   9404  return,   Combine ON   (delivery completed through the API first — below)
//   9405  return,   Combine OFF
//
// Hour-tracked units, prefilled readings (start_hours 100, later end_hours 130),
// no power source (no fuel row). Template: Q1 body damage (required; "Damaged"
// costs 150 on return), Q2 keys (optional).

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
use Illuminate\Support\Facades\DB;

$driver = User::where('email', 'driver@staging.local')->firstOrFail();
$storeId = 36;          // Bon Aqua
$customerId = 303;      // P6 Test Customer 1
$customerName = 'P6 Test Customer 1';

if (Order::whereBetween('order_number', ['9401', '9405'])->exists()) {
    echo "ALREADY SEEDED\n";
    return;
}

DB::transaction(function () use ($driver, $storeId, $customerId, $customerName) {
    $category = CustomerAdminCategory::create(['category_name' => 'Batch Isolation Condition']);
    $q1 = CustomerAdminQuestion::create([
        'question_name' => 'Batch body damage', 'category_id' => $category->id,
        'question_delivery_text' => 'Any body damage at delivery?', 'question_return_text' => 'Any body damage at return?',
        'required_question' => true,
    ]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No damage', 'answer_return_text' => 'No damage', 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Damaged', 'answer_return_text' => 'Damaged', 'question_id' => $q1->id, 'index_number' => 2, 'is_damaged' => true, 'return_amt' => 150]);
    $q2 = CustomerAdminQuestion::create([
        'question_name' => 'Batch keys', 'category_id' => $category->id,
        'question_delivery_text' => 'Keys handed over?', 'question_return_text' => 'Keys returned?',
        'required_question' => false,
    ]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Yes', 'answer_return_text' => 'Yes', 'question_id' => $q2->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No', 'answer_return_text' => 'No', 'question_id' => $q2->id, 'index_number' => 2]);
    $template = CustomerAdminTemplate::create(['template_name' => 'Batch Isolation Checklist', 'active_template' => true]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q2->id, 'index_number' => 2]);
    $master = ChecklistMaster::create(['checklist_system_name' => 'Batch Isolation Master', 'customer_admin_template_id' => $template->id]);

    $letters = ['A' => 'Alpha', 'B' => 'Bravo', 'C' => 'Charlie'];
    foreach ([9401, 9402, 9403, 9404, 9405] as $number) {
        $order = Order::create([
            'order_number' => (string) $number, 'order_date' => now()->format('Y-m-d'),
            'customer_name' => $customerName, 'customer_id' => $customerId, 'grand_total' => 300,
        ]);
        foreach ($letters as $letter => $word) {
            $product = Product::create(['product_name' => "Batch {$word}", 'slug' => "batch-{$number}-" . strtolower($letter) . '-' . uniqid(), 'product_type' => 'Rental']);
            $line = OrderProduct::create([
                'order_id' => $order->id, 'product_id' => $product->id, 'product_name' => "Batch {$word}",
                'price' => 100, 'quantity' => 1, 'total' => 100,
                'delivery_date' => now()->format('Y-m-d'), 'delivery_status' => 'Pending', 'pickup_status' => 'Pending',
                'delivery_transport_mode' => 'Truck', 'pickup_transport_mode' => 'Truck',
                'delivery_store_id' => $storeId, 'pickup_store_id' => $storeId,
                'hour_tracking' => 'Yes', 'start_hours' => 100,
                'product_data' => ['product_type' => 'Rental', 'product_variant' => 'daily', 'product_rental_items_prices' => [], 'product_option_items' => []],
            ]);
            if ($number === 9403 && $letter === 'C') {
                continue;   // the line WITHOUT a unit
            }
            $unit = Equipment::create([
                'equipment_name' => "{$word} Unit", 'equipment_id' => "CB{$number}-{$letter}", 'brand' => 'Bobcat',
                'current_status' => 'available', 'checklist_master_id' => $master->id,
                'power_source_type' => null, 'hour_tracking' => 'Yes', 'store_id' => $storeId,
            ]);
            EquipmentSoftAssign::create(['equipment_id' => $unit->id, 'order_id' => $order->id, 'order_product_id' => $line->id, 'assigned_by' => $driver->id]);
        }
    }
});

$rows = OrderProduct::whereHas('order', fn ($q) => $q->whereBetween('order_number', ['9401', '9405']))
    ->with(['order', 'softAssignment.equipment'])->orderBy('id')->get();
foreach ($rows as $r) {
    echo $r->order->order_number, ' ', $r->product_name, ' line=', $r->unique_id, ' unit=', $r->softAssignment?->equipment?->equipment_id ?? '-', ' unit_uid=', $r->softAssignment?->equipment?->unique_id ?? '-', "\n";
}

/*
 * Run (staging Laravel checkout, staging DB only):
 *   DB_DATABASE=<staging> APP_ENV=staging php artisan tinker --execute="require '<path>/ChecklistBatchIsolationStagingSeed.php';"
 *
 * 9404/9405 need a completed DELIVERY before their return can be tested — done the way
 * the phone does it (staging driver token from POST login; question/answer ids from
 * customer_admin_questions / customer_admin_question_answers where question_name LIKE 'Batch %'):
 *   GET  orders/checklists/context/{line}/delivery          → data.identity.checklist_execution_id
 *   POST orders/checklists/{execution}/complete  (multipart) order_product_unique_id, equipment_unique_id,
 *        user_id, answers[i][question_id], answers[i][answer_id], start_hours=100, signature_media=@sig.png
 * then:  UPDATE order_products ... SET end_hours = 130 WHERE order IN (9404, 9405)   (prefilled return reading)
 *
 * Verify a line's independence after each UI test:
 *   SELECT op.product_name, e.leg, e.status, e.signature_media_id FROM order_product_checklist_executions e
 *     JOIN order_products op ON op.id = e.order_product_id JOIN orders o ON o.id = op.order_id WHERE o.order_number = ?;
 *   SELECT m.operation_type, op.product_name FROM mobile_operations m
 *     JOIN order_product_checklist_executions e ON e.id = m.resource_id AND m.resource_type = 'checklist_execution'
 *     JOIN order_products op ON op.id = e.order_product_id ...   -- no row for an untouched line
 *   billing_charges / customer_damage_stagings by order_product_id   -- a damage charge only on the damaged line
 */
