// Staging world for RentnKingUITests/SupplierDirectoryUITests (the Supplier
// Directory). NOT part of the app: a Laravel tinker script, run against an
// EMPTY staging database cloned from the test schema:
//
//   cd <Kabba Laravel checkout with the suppliers API>
//   mysql -e "CREATE DATABASE kabba_supplier_mobile"
//   mysqldump --no-data rentnking_kabba_testing | mysql kabba_supplier_mobile
//   mysqldump rentnking_kabba_testing settings migrations | mysql kabba_supplier_mobile
//   APP_ENV=testing DB_DATABASE=kabba_supplier_mobile php artisan tinker --execute="$(cat <this file>)"
//
// Then serve that checkout on :8124 (see RentnKingTests/README.md):
//   cd public && APP_ENV=testing DB_DATABASE=kabba_supplier_mobile API_DOMAIN=localhost \
//     API_DOMAIN_URL=http://localhost:8124 php -S 127.0.0.1:8124 \
//     ../vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php
//
// Accounts (password supplier-pass-123): erin@suppliers.local — an active
// employee; casey@suppliers.local — an external contract driver (refused).

use App\Models\Iam\Personnel\User;
use App\Models\Locations\State;
use App\Models\MaintenanceManagement\Part;
use App\Models\MaintenanceManagement\PartCategory;
use App\Models\MaintenanceManagement\Supplier;
use App\Models\MaintenanceManagement\SupplierTag;

$tn = State::firstOrCreate(['name' => 'Tennessee'], ['slug' => 'tennessee', 'abbreviation' => 'TN']);
State::firstOrCreate(['name' => 'Kentucky'], ['slug' => 'kentucky', 'abbreviation' => 'KY']);
$hydraulics = PartCategory::firstOrCreate(['name' => 'Hydraulics']);
PartCategory::firstOrCreate(['name' => 'Engines']);
$sameDay = SupplierTag::firstOrCreate(['name' => 'Same-day delivery']);
SupplierTag::firstOrCreate(['name' => 'Net 30 account']);

$smoky = Supplier::create([
    'name' => 'Smoky Mountain Hydraulics', 'status' => 'Active', 'is_preferred_supplier' => true,
    'phone' => '(865) 555-0100', 'email' => 'sales@smokymountainhydraulics.example', 'website' => 'apple.com',
    'address' => '1 Apple Park Way', 'city' => 'Cupertino', 'state_id' => $tn->id, 'zip_code' => '95014',
    'payment_terms' => 'Net 30', 'tax_id' => '12-3456789',
    'supplier_category_id' => $hydraulics->id, 'tags' => (string) $sameDay->id,
    'primary_contact_name' => 'Dana Brooks', 'primary_contact_phone' => '(865) 555-0101', 'primary_contact_email' => 'dana@smokymountainhydraulics.example',
    'inside_sales_name' => 'Marcus Lee', 'inside_sales_phone' => '(865) 555-0102',
    'technical_support_phone' => '(865) 555-0199 x12',
]);
Part::create(['part_name' => 'Hydraulic Hose Kit', 'is_active' => true, 'primary_supplier_id' => $smoky->id, 'primary_part_number' => 'HK-1']);
Supplier::create(['name' => 'Midway Parts (retired)', 'status' => 'Inactive', 'city' => 'Maryville']);
foreach (range(1, 40) as $i) {
    Supplier::create(['name' => sprintf('Directory Filler %02d', $i), 'status' => 'Active', 'city' => 'Knoxville', 'state_id' => $tn->id]);
}

foreach ([['Erin', 'erin@suppliers.local', false], ['Casey', 'casey@suppliers.local', true]] as [$first, $email, $contractor]) {
    User::updateOrCreate(['email' => $email], [
        'first_name' => $first, 'last_name' => 'Staging', 'password' => bcrypt('supplier-pass-123'),
        'status' => 'Active', 'is_contract_driver' => $contractor,
    ]);
}
echo "Supplier Directory staging world ready: ".Supplier::count()." suppliers\n";
