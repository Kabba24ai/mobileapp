<?php
// Staging-only seed for OrderNotificationEntryUITests (mobile issue #9). NEVER run against production.
//
//   NOTIFY_BASE=9680 DB_DATABASE=<staging> APP_ENV=<staging|testing> \
//     php artisan tinker --execute="require '<path>/OrderNotificationEntryStagingSeed.php';"
//
// Synthetic data only (@notify.local / @test.local):
//   BASE+1  "hidden": created FIRST, then 50 newer filler orders, so it is not on the Orders list's
//           first page (50 per page, newest first) — a notification must still open it.
//   BASE+2  the new order a push announces (newest, top of the list).
//   BASE+3  a second new order (another tap replaces the first; the busy-workflow case).
// Each real order has one rental line, Delivery pending, a soft-assigned unit with a checklist, so
// Checklist Deliv / Photo-Video / Terms open exactly as for any order.
// Unread new-order notifications for the office user: one each for BASE+1…+3 and one for a filler
// order — opening an order must mark only ITS notifications read.
// Prints one JSON line per order: the push data Kabba sends (SendAdminNotificationListener).

use App\Models\ChecklistManagement\ChecklistMaster\ChecklistMaster;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminCategory;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminQuestion;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminQuestionAnswer;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminTemplate;
use App\Models\ChecklistManagement\CustomerAdmin\CustomerAdminTemplateQuestion;
use App\Models\Customers\Customer;
use App\Models\Iam\Personnel\User;
use App\Models\Iam\Personnel\UserNotification;
use App\Models\MaintenanceManagement\Equipment;
use App\Models\MaintenanceManagement\EquipmentSoftAssign;
use App\Models\Orders\Order;
use App\Models\Orders\OrderProduct;
use App\Models\ProductManagement\Product;
use App\Models\Stores\Store;
use Illuminate\Support\Facades\DB;

if (app()->environment('production')) { echo "REFUSED: production\n"; return; }

$base = (int) (getenv('NOTIFY_BASE') ?: 9680);
$numbers = [$base + 1, $base + 2, $base + 3];
if (Order::whereIn('order_number', array_map('strval', $numbers))->exists()) { echo "ALREADY SEEDED for base {$base}\n"; return; }

$office = User::where('email', 'office@notify.local')->first() ?? User::create([
    'first_name' => 'Morgan', 'last_name' => 'Office', 'email' => 'office@notify.local', 'status' => 'Active',
    'password' => bcrypt('notify-pass-123'),
]);

$out = DB::transaction(function () use ($base, $office) {
    $store = Store::where('store_name', 'Notify Yard')->first() ?? Store::create(['store_name' => 'Notify Yard', 'status' => 'Active']);
    $customer = Customer::create(['first_name' => 'Notify', 'last_name' => 'Customer', 'email' => "notify-customer-{$base}@test.local"]);

    $category = CustomerAdminCategory::create(['category_name' => "Notify Condition {$base}"]);
    $q1 = CustomerAdminQuestion::create(['question_name' => "Notify body damage {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Any body damage at delivery?', 'question_return_text' => 'Any body damage at return?', 'required_question' => true]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No damage', 'answer_return_text' => 'No damage', 'question_id' => $q1->id, 'index_number' => 1]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'Damaged', 'answer_return_text' => 'Damaged', 'question_id' => $q1->id, 'index_number' => 2, 'is_damaged' => true, 'return_amt' => 150]);
    $template = CustomerAdminTemplate::create(['template_name' => "Notify Checklist {$base}", 'active_template' => true]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q1->id, 'index_number' => 1]);
    $master = ChecklistMaster::create(['checklist_system_name' => "Notify Master {$base}", 'customer_admin_template_id' => $template->id]);

    $makeOrder = function (int $number, string $name) use ($customer, $store, $master, $office) {
        $order = Order::create(['order_number' => (string) $number, 'order_date' => now()->format('Y-m-d'),
            'customer_name' => $name, 'customer_id' => $customer->id, 'grand_total' => 200]);
        $product = Product::create(['product_name' => 'Notify Excavator', 'slug' => "notify-{$number}-" . uniqid(), 'product_type' => 'Rental']);
        $line = OrderProduct::create(['order_id' => $order->id, 'product_id' => $product->id, 'product_name' => 'Notify Excavator',
            'price' => 100, 'quantity' => 1, 'total' => 100, 'delivery_date' => now()->addDay()->format('Y-m-d'),
            'delivery_status' => 'Pending', 'pickup_status' => 'Pending', 'delivery_transport_mode' => 'Truck', 'pickup_transport_mode' => 'Truck',
            'delivery_store_id' => $store->id, 'pickup_store_id' => $store->id, 'hour_tracking' => 'No',
            'product_data' => ['product_type' => 'Rental', 'product_variant' => 'daily', 'product_rental_items_prices' => [], 'product_option_items' => []]]);
        $unit = Equipment::create(['equipment_name' => 'Notify Unit', 'equipment_id' => "NT{$number}", 'brand' => 'Kubota',
            'current_status' => 'available', 'checklist_master_id' => $master->id, 'power_source_type' => null,
            'hour_tracking' => 'No', 'store_id' => $store->id, 'assigned_product_id' => $product->id]);
        EquipmentSoftAssign::create(['equipment_id' => $unit->id, 'order_id' => $order->id, 'order_product_id' => $line->id, 'assigned_by' => $office->id]);
        return $order;
    };

    $hidden = $makeOrder($base + 1, 'Notify Hidden Customer');
    $fillers = [];
    for ($i = 1; $i <= 50; $i++) {
        $fillers[] = Order::create(['order_number' => "NF{$base}-{$i}", 'order_date' => now()->format('Y-m-d'),
            'customer_name' => 'Notify Filler', 'customer_id' => $customer->id, 'grand_total' => 0]);
    }
    $new = $makeOrder($base + 2, 'Notify New Customer');
    $other = $makeOrder($base + 3, 'Notify Other Customer');

    foreach ([$hidden, $new, $other, $fillers[0]] as $order) {
        UserNotification::create(['user_id' => $office->id, 'order_id' => $order->id, 'status' => 'unread', 'type' => 'new_order',
            'title' => 'New Order Placed ' . $order->order_number, 'body' => $order->customer_name,
            'params' => json_encode(['order_id' => (string) $order->id, 'order_unique_id' => (string) $order->unique_id, 'order_number' => (string) $order->order_number])]);
    }
    return ['hidden' => $hidden, 'new' => $new, 'other' => $other, 'filler' => $fillers[0]];
});

foreach ($out as $role => $order) {
    $order->refresh();
    echo strtoupper($role) . '=' . json_encode(['order_id' => (string) $order->id, 'order_unique_id' => (string) $order->unique_id,
        'order_number' => (string) $order->order_number], JSON_UNESCAPED_SLASHES) . "\n";
}

/*
 * After the run (staging DB): only the opened orders' notifications are read; the filler's stays unread.
 *   SELECT o.order_number, n.status FROM user_notifications n JOIN orders o ON o.id = n.order_id
 *    JOIN users u ON u.id = n.user_id WHERE u.email = 'office@notify.local' ORDER BY o.id;
 */
