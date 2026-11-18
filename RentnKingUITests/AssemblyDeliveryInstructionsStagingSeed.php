<?php
// Staging-only seed for AssemblyDeliveryInstructionsUITests (Order / Delivery Instructions on the
// Assembly Review, 2026-11-18). NEVER run against production.
//
//   INSTR_BASE=9740 APP_TIMEZONE=America/Chicago APP_ENV=testing DB_DATABASE=<staging> \
//     php artisan tinker --execute="require '<path>/AssemblyDeliveryInstructionsStagingSeed.php';"
//
// APP_TIMEZONE must be the shop's: the deliveries are for TODAY as the phone counts days.
//
// Account (password instructions-pass-123): driver@instructions.local — a driver, so Dispatch
// lists the stops. Three one-line deliveries for today, assigned to the driver and not started,
// so Start Delivery opens the Assembly Review (driver origin):
//   BASE+1  "Ivy Instructions"  two notes: several paragraphs written by the office (Amber Office),
//                                and a short one the customer left at checkout
//   BASE+2  "Nate Nonotes"      no notes at all
//   BASE+3  "Wanda Wrongyard"   one short note; NO unit assigned, so the assembly is at STOP
// The notes are plain order_notes rows — what Order Details' "Order / Delivery Instructions"
// Add Note writes. Each order also carries a payment-style dashboard note that must NOT appear.
// Nothing here is a real customer.

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

$base = (int) (getenv('INSTR_BASE') ?: 9740);

$long = "Deliver to the back lot, not the front office. Use the gravel entrance on Mill Rd; the paved drive cannot take the trailer.\n\n"
    . "Gate code 4471. Call Dale at the site 20 minutes before arriving.\n\n"
    . "- Set the machine beside the blue container\n- Leave the keys in the lockbox (code 0912)\n- Do not block the loading dock\n\n"
    . "Customer needs a walk-around on the controls before you leave.";

$orders = [
    $base + 1 => ['first' => 'Ivy', 'last' => 'Instructions', 'unit' => true, 'office' => $long, 'customer' => 'Dog in the yard. Please close the gate behind you.'],
    $base + 2 => ['first' => 'Nate', 'last' => 'Nonotes', 'unit' => true, 'office' => null, 'customer' => null],
    $base + 3 => ['first' => 'Wanda', 'last' => 'Wrongyard', 'unit' => false, 'office' => 'Customer will meet you at the north gate at 8:00.', 'customer' => null],
];
if (Order::whereIn('order_number', array_map('strval', array_keys($orders)))->exists()) { echo "ALREADY SEEDED for base {$base}\n"; return; }

$driver = User::where('email', 'driver@instructions.local')->first() ?? User::create([
    'first_name' => 'Dana', 'last_name' => 'Driver', 'email' => 'driver@instructions.local', 'status' => 'Active',
    'password' => bcrypt('instructions-pass-123'),
]);
User::whereKey($driver->id)->update(['is_driver' => true]);   // Dispatch lists drivers only
$office = User::where('email', 'office@instructions.local')->first() ?? User::create([
    'first_name' => 'Amber', 'last_name' => 'Office', 'email' => 'office@instructions.local', 'status' => 'Active',
    'password' => bcrypt('instructions-pass-123'),
]);

$made = DB::transaction(function () use ($orders, $base, $driver, $office) {
    $store = Store::where('store_name', 'Instructions Yard')->first() ?? Store::create(['store_name' => 'Instructions Yard', 'status' => 'Active']);

    $category = CustomerAdminCategory::create(['category_name' => "Instructions Condition {$base}"]);
    $q = CustomerAdminQuestion::create(['question_name' => "Instructions body damage {$base}", 'category_id' => $category->id,
        'question_delivery_text' => 'Any body damage at delivery?', 'question_return_text' => 'Any body damage at return?', 'required_question' => true]);
    CustomerAdminQuestionAnswer::create(['answer_delivery_text' => 'No damage', 'answer_return_text' => 'No damage', 'question_id' => $q->id, 'index_number' => 1]);
    $template = CustomerAdminTemplate::create(['template_name' => "Instructions Checklist {$base}", 'active_template' => true]);
    CustomerAdminTemplateQuestion::create(['template_id' => $template->id, 'question_id' => $q->id, 'index_number' => 1]);
    $master = ChecklistMaster::create(['checklist_system_name' => "Instructions Master {$base}", 'customer_admin_template_id' => $template->id]);

    $made = [];
    foreach ($orders as $number => $who) {
        $name = "{$who['first']} {$who['last']}";
        $customer = Customer::create(['first_name' => $who['first'], 'last_name' => $who['last'], 'email' => "instructions-{$number}@test.local"]);
        $order = Order::create(['order_number' => (string) $number, 'order_date' => now()->format('Y-m-d'),
            'customer_name' => $name, 'customer_id' => $customer->id, 'grand_total' => 200]);
        OrderAddress::create(['order_id' => $order->id, 'type' => 'Shipping', 'first_name' => $who['first'], 'last_name' => $who['last'],
            'address' => '1200 Test Ridge Rd', 'city' => 'Knoxville', 'state' => 'TN', 'zip_code' => '37919']);
        $product = Product::create(['product_name' => 'Instructions Excavator', 'slug' => "instructions-{$number}-" . uniqid(), 'product_type' => 'Rental']);
        $line = OrderProduct::create(['order_id' => $order->id, 'product_id' => $product->id, 'product_name' => 'Instructions Excavator',
            'price' => 100, 'quantity' => 1, 'total' => 100, 'delivery_date' => now()->format('Y-m-d'),
            'delivery_status' => 'Pending', 'pickup_status' => 'Pending', 'delivery_transport_mode' => 'Truck', 'pickup_transport_mode' => 'Truck',
            'delivery_store_id' => $store->id, 'pickup_store_id' => $store->id, 'hour_tracking' => 'No',
            'delivery_by' => $driver->id,
            'product_data' => ['product_type' => 'Rental', 'product_variant' => 'daily', 'product_rental_items_prices' => [], 'product_option_items' => []]]);
        if ($who['unit']) {
            $unit = Equipment::create(['equipment_name' => 'Instructions Unit', 'equipment_id' => "IN{$number}", 'brand' => 'Bobcat',
                'current_status' => 'available', 'checklist_master_id' => $master->id, 'power_source_type' => null,
                'hour_tracking' => 'No', 'store_id' => $store->id, 'assigned_product_id' => $product->id]);
            EquipmentSoftAssign::create(['equipment_id' => $unit->id, 'order_id' => $order->id, 'order_product_id' => $line->id, 'assigned_by' => $driver->id]);
        }

        // The customer's checkout note first (older), then the office's (newer) — the phone lists newest first.
        if ($who['customer']) {
            $note = $order->notes()->create(['note' => $who['customer'], 'created_by_type' => Customer::class, 'created_by_id' => $customer->id]);
            DB::table('order_notes')->where('id', $note->id)->update(['created_at' => now()->subDay(), 'updated_at' => now()->subDay()]);
        }
        if ($who['office']) {
            $order->notes()->create(['note' => $who['office'], 'user_id' => $office->id, 'created_by_type' => User::class, 'created_by_id' => $office->id]);
        }
        // Not an instruction: a Billing dashboard note. It must never reach the driver.
        $order->notes()->create(['note' => 'BILLING ONLY: promised to pay Friday.', 'note_type' => 'dashboard', 'user_id' => $office->id,
            'created_by_type' => User::class, 'created_by_id' => $office->id]);

        $made[] = "{$number} id={$order->id} uid={$order->unique_id} customer=\"{$name}\" line={$line->unique_id} unit=" . ($who['unit'] ? 'yes' : 'none');
    }
    return $made;
});

echo implode("\n", $made) . "\n";
echo "driver=driver@instructions.local password=instructions-pass-123\n";
