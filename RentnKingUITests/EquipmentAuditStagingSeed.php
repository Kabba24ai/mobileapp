// Staging world for RentnKingUITests/EquipmentAuditUITests (the mobile
// Equipment Audit). NOT part of the app: a Laravel tinker script, run against
// an EMPTY staging database cloned from the test schema:
//
//   cd <Kabba Laravel checkout>
//   mysql -e "CREATE DATABASE kabba_audit_mobile"
//   mysqldump --no-data rentnking_kabba_testing | mysql kabba_audit_mobile
//   mysqldump rentnking_kabba_testing settings migrations | mysql kabba_audit_mobile
//   DB_DATABASE=kabba_audit_mobile php artisan tinker --execute="$(cat <this file>)"
//
// Then serve that checkout on :8124 with API_DOMAIN=localhost and
// API_DOMAIN_URL=http://localhost:8124 (see RentnKingTests/README.md). Each
// UI scenario consumes its units: reseed before re-running.
//
(new \Database\Seeders\Iam\EquipmentAuditPermissionSeeder)->run();
use App\Models\Stores\Store;
use App\Models\ProductManagement\ProductCategory;
use App\Models\Iam\Personnel\User;
use App\Models\MaintenanceManagement\Equipment;
use App\Models\MaintenanceManagement\Supplier;
use App\Models\Orders\Order;
use App\Models\Orders\OrderProduct;
use App\Services\EquipmentAudit\EquipmentAuditPermissions as P;

$bon = Store::create(['store_name' => 'Bon Aqua', 'status' => 'Active', 'is_primary' => 'Yes', 'latitude' => '36', 'longitude' => '-87']);
$wav = Store::create(['store_name' => 'Waverly', 'status' => 'Active', 'is_primary' => 'No', 'latitude' => '36', 'longitude' => '-87']);
$skid = ProductCategory::create(['title' => 'Skid Steer', 'status' => 'Published', 'sort_order' => 1]);
\App\Models\Locations\State::firstOrCreate(['name' => 'Tennessee'], ['slug' => 'tennessee', 'abbreviation' => 'TN']);
Supplier::create(['name' => 'Parman Tractor', 'status' => 'Active', 'is_driveable' => true, 'address' => '11262 Moss Branch Road', 'city' => 'Bon Aqua', 'zip_code' => '37025', 'primary_contact_name' => 'Joe Parman', 'primary_contact_phone' => '(615) 555-2000']);

$user = function ($first, $last, $email, array $perms) {
    $u = User::create(['first_name' => $first, 'last_name' => $last, 'email' => $email, 'password' => bcrypt('audit-pass-123'), 'status' => 'Active']);
    if ($perms) { $u->givePermissionTo($perms); }
    return $u;
};
$all = array_keys(P::all());
$gary = $user('Gary', 'Lead', 'gary@audit.local', $all);
$john = $user('John', 'Yard', 'john@audit.local', $all);
$ashley = $user('Ashley', 'Lot', 'ashley@audit.local', $all);
$user('Billy', 'Bob', 'billy@audit.local', []);
$user('Vera', 'Verifier', 'vera@audit.local', [P::VIEW, P::VERIFY]);

$unit = fn ($name, $code, $store, $status = 'available') => Equipment::create([
    'equipment_name' => $name, 'equipment_id' => $code, 'brand' => 'Takeuchi',
    'product_category_id' => $skid->id, 'store_id' => $store->id, 'current_status' => $status,
]);
foreach (['TAK-SS-16', 'TAK-SS-2', 'TAK-SS-14', 'TAK-SS-7'] as $code) { $unit('Cab - Tak TL8', $code, $bon); }
$unit('Cab -Tak TL8', 'TAK-SS-11', $bon);
$unit('Bobcat S70', 'SS-101', $bon);
$unit('Kubota SVL75', 'SS-112', $bon, 'maintenance');
$unit('Cat 259D3', 'SS-9', $wav);
$unit('Bobcat T66', 'SS-104', $wav);
$wanderer = $unit('Bobcat E35', 'SS-88', $wav);   // physically at Bon Aqua — the store-mismatch unit

$rented = $unit('Cat 299D3', 'SS-110', $bon);
$order = Order::create(['order_number' => '4521', 'order_date' => now()->toDateString(), 'customer_name' => 'Jane Renter', 'grand_total' => 250]);
$line = OrderProduct::create(['order_id' => $order->id, 'product_name' => 'Skid Steer Rental', 'product_data' => ['product_type' => 'Rental'],
    'price' => 250, 'quantity' => 1, 'total' => 250, 'equipment_id' => $rented->id, 'delivery_date' => now()->subDay()->toDateString(),
    'delivery_status' => 'Completed', 'pickup_status' => 'Pending', 'pickup_date' => now()->addDays(3)->toDateString(), 'pickup_store_id' => $bon->id]);
\App\Services\Equipment\EquipmentStatusService::markRented($rented->fresh(), $order->id, $line->id, $gary->id);

$away = $unit('Bobcat T76', 'SS-4', $bon);
app(\App\Services\Equipment\EquipmentOffSiteService::class)->moveOffSite($away->fresh(), ['location_source' => 'manual', 'location_name' => 'Humphreys County Fair', 'address_line_1' => '1 Fair Way', 'city' => 'Waverly'], $gary->id);

$audit = app(\App\Services\EquipmentAudit\EquipmentAuditService::class)->start($skid->id, $gary, $gary);
$ledger = app(\App\Services\EquipmentAudit\EquipmentAuditLedger::class);
$ledger->assignSectionAuditor($audit, 'store:'.$bon->id, $john, $gary);
$ledger->assignSectionAuditor($audit, 'store:'.$wav->id, $ashley, $gary);
echo "audit {$audit->unique_id} {$audit->reference} bon={$bon->id} wav={$wav->id} john={$john->id}\n";
