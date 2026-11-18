<?php
// Staging-only seed for CustomerCallPhoneUITests and HomeTilesUITests (mobile issue #10). NEVER run against production.
//
//   CALL_BASE=9720 APP_TIMEZONE=America/Chicago APP_ENV=testing DB_DATABASE=<staging> \
//     php artisan tinker --execute="require '<path>/CustomerCallPhoneStagingSeed.php';"
//
// APP_TIMEZONE must be the shop's: the deliveries are for TODAY as the phone counts days (a UTC
// seed after 6 pm Central lands on tomorrow and Dispatch shows nothing).
//
// Account (password callphone-pass-123): driver@callphone.local — a driver, so Dispatch lists
// the stops. Two one-line deliveries for today, assigned to the driver and not started, so Start
// Delivery opens the Assembly Review (driver origin) → Continue to Driver Checklist:
//   BASE+1  "Pat Phone"     phone 865-555-0142 (Kabba shows it "(865) 555-0142") — in the 555-0100…0199
//                            range reserved for fiction; the UI tests stop at iOS's own "Call?" prompt and cancel
//   BASE+2  "Nora Nophone"  no phone
// The phone is on the order (what Dispatch's rows carry) and on its shipping address.
// Nothing here is a real customer, and nothing is dialled or texted.

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
use App\Models\Orders\OrderAddress;
use App\Models\Orders\OrderProduct;
use App\Models\ProductManagement\Product;
use App\Models\Stores\Store;
use Illuminate\Support\Facades\DB;

if (app()->environment('production')) { echo "REFUSED: production\n"; return; }

$base = (int) (getenv('CALL_BASE') ?: 9720);
$orders = [
    $base + 1 => ['first' => 'Pat', 'last' => 'Phone', 'phone' => '865-555-0142'],
    $base + 2 => ['first' => 'Nora', 'last' => 'Nophone', 'phone' => null],
];
if (Order::whereIn('order_number', array_map('strval', array_keys($orders)))->exists()) { echo "ALREADY SEEDED for base {$base}\n"; return; }

$driver = User::where('email', 'driver@callphone.local')->first() ?? User::create([
    'first_name' => 'Casey', 'last_name' => 'Caller', 'email' => 'driver@callphone.local', 'status' => 'Active',
    'password' => bcrypt('callphone-pass-123'),
]);
User::whereKey($driver->id)->update(['is_driver' => true]);   // Dispatch lists drivers only

$made = DB::transaction(function () use ($orders, $base, $driver) {
    $store = Store::where('store_name', 'Call Phone Yard')->first() ?? Store::create(['store_name' => 'Call Phone Yard', 'status' => 'Active']);

    $category = CustomerAdminCategory::create(['category_name' => "Call Phone Condition {$base}"]);
    $q = CustomerAdminQuestion::create(['question_name' => "Call phone body damage {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Any body damage at delivery?', 'question_return_text' => 'Any body damage at return?', 'required_question' => true]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No damage', 'answer_return_text' => 'No damage', 'question_id' => $q->id, 'index_number' => 1]);
    $template = CustomerAdminTemplate::create(['template_name' => "Call Phone Checklist {$base}", 'active_template' => true]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q->id, 'index_number' => 1]);
    $master = ChecklistMaster::create(['checklist_system_name' => "Call Phone Master {$base}", 'customer_admin_template_id' => $template->id]);

    $made = [];
    foreach ($orders as $number => $who) {
        $name = "{$who['first']} {$who['last']}";
        $customer = Customer::create(['first_name' => $who['first'], 'last_name' => $who['last'], 'email' => "call-phone-{$number}@test.local",
            'phone' => $who['phone']]);
        $order = Order::create(['order_number' => (string) $number, 'order_date' => now()->format('Y-m-d'),
            'customer_name' => $name, 'customer_phone' => $who['phone'], 'customer_id' => $customer->id, 'grand_total' => 200]);
        OrderAddress::create(['order_id' => $order->id, 'type' => 'Shipping', 'first_name' => $who['first'], 'last_name' => $who['last'],
            'phone' => $who['phone'], 'address' => '1200 Test Ridge Rd', 'city' => 'Knoxville', 'state' => 'TN', 'zip_code' => '37919']);
        $product = Product::create(['product_name' => 'Call Phone Excavator', 'slug' => "call-phone-{$number}-" . uniqid(), 'product_type' => 'Rental']);
        $line = OrderProduct::create(['order_id' => $order->id, 'product_id' => $product->id, 'product_name' => 'Call Phone Excavator',
            'price' => 100, 'quantity' => 1, 'total' => 100, 'delivery_date' => now()->format('Y-m-d'),
            'delivery_status' => 'Pending', 'pickup_status' => 'Pending', 'delivery_transport_mode' => 'Truck', 'pickup_transport_mode' => 'Truck',
            'delivery_store_id' => $store->id, 'pickup_store_id' => $store->id, 'hour_tracking' => 'No',
            'delivery_by' => $driver->id,
            'product_data' => ['product_type' => 'Rental', 'product_variant' => 'daily', 'product_rental_items_prices' => [], 'product_option_items' => []]]);
        $unit = Equipment::create(['equipment_name' => 'Call Phone Unit', 'equipment_id' => "CP{$number}", 'brand' => 'Bobcat',
            'current_status' => 'available', 'checklist_master_id' => $master->id, 'power_source_type' => null,
            'hour_tracking' => 'No', 'store_id' => $store->id, 'assigned_product_id' => $product->id]);
        EquipmentSoftAssign::create(['equipment_id' => $unit->id, 'order_id' => $order->id, 'order_product_id' => $line->id, 'assigned_by' => $driver->id]);
        $made[] = "{$number} id={$order->id} customer=\"{$name}\" phone=" . ($who['phone'] ?? 'none') . " line={$line->unique_id} delivery_date={$line->delivery_date}";
    }
    return $made;
});

echo implode("\n", $made) . "\n";
echo "driver=driver@callphone.local password=callphone-pass-123\n";
