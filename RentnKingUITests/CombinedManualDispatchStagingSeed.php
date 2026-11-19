<?php
// Staging-only seed for CombinedManualDispatchUITests (combined manual dispatches + per-item
// confirmation, 2026-11-18). NEVER run against production.
//
//   APP_TIMEZONE=America/Chicago APP_ENV=testing DB_DATABASE=<staging> \
//     php artisan tinker --execute="require '<path>/CombinedManualDispatchStagingSeed.php';"
//
// Account (password combined-pass-123): driver@combined.local — a driver.
// Two Equipment Drop-Off tasks for TODAY from "Combined North Yard" to the street address of
// "Combined South Yard", created and combined through Kabba's own services (the rule runs):
//   task 1  items: "Trench Roller", "Plate Compactor"
//   task 2  item:  "Light Tower"
// and ONE separate task to a different address ("Mill Rd Site") on the same driver — it must
// stay its own card.

use App\Models\Dispatch\ManualDispatchTask;
use App\Models\Dispatch\ManualDispatchType;
use App\Models\Iam\Personnel\User;
use App\Models\Stores\Store;
use App\Services\Dispatch\ManualDispatchLoadService;
use App\Services\Dispatch\ManualDispatchService;

if (app()->environment('production')) { echo "REFUSED: production\n"; return; }
if (User::where('email', 'driver@combined.local')->exists()) { echo "ALREADY SEEDED\n"; return; }

$driver = User::create(['first_name' => 'Cory', 'last_name' => 'Combined', 'email' => 'driver@combined.local', 'status' => 'Active',
    'password' => bcrypt('combined-pass-123')]);
User::whereKey($driver->id)->update(['is_driver' => true]);
$office = User::create(['first_name' => 'Olive', 'last_name' => 'Office', 'email' => 'office@combined.local', 'status' => 'Active',
    'password' => bcrypt('combined-pass-123')]);

$north = Store::create(['store_name' => 'Combined North Yard', 'status' => 'Active', 'address' => '10550 Highway 46', 'city' => 'Bon Aqua', 'zip_code' => '37025']);
$south = Store::create(['store_name' => 'Combined South Yard', 'status' => 'Active', 'address' => '200 Transfer Road', 'city' => 'Waverly', 'zip_code' => '37185']);
$type = ManualDispatchType::where('name', 'Equipment Drop-Off')->firstOrFail();

$service = app(ManualDispatchService::class);
$make = fn (array $extra) => $service->create(array_merge([
    'manual_dispatch_type_id' => $type->id, 'store_id' => $north->id, 'dispatch_date' => today()->toDateString(),
    'location_name' => 'Combined South Yard', 'address' => $south->address, 'city' => $south->city, 'zip_code' => $south->zip_code,
], $extra), $office);

$one = $make(['custom_description' => 'Compaction gear for the south yard', 'items' => [
    ['label' => 'Trench Roller', 'instructions' => 'Chain it at the front of the trailer'],
    ['label' => 'Plate Compactor'],
]]);
$two = $make(['custom_description' => 'Lighting for the south yard', 'items' => [['label' => 'Light Tower', 'instructions' => 'Mast down and pinned']]]);
$solo = $make(['custom_description' => 'Pump for the Mill Rd job', 'location_name' => 'Mill Rd Site', 'address' => '415 Mill Road', 'city' => 'Dickson', 'zip_code' => '37055',
    'items' => [['label' => 'Trash Pump']]]);

$load = app(ManualDispatchLoadService::class)->combine([$one->unique_id, $two->unique_id], null, $driver->id, today()->toDateString(), false, $office);
$service->assign($solo->fresh(), $driver->id, today()->toDateString(), $office);

foreach ([$one, $two, $solo] as $t) {
    $t = $t->fresh();
    echo "task {$t->unique_id} load=" . ($t->dispatch_load_id ?? 'none') . " driver={$t->driver_id} items=" . $t->items()->count() . "\n";
}
echo "load {$load->unique_id}\ndriver=driver@combined.local password=combined-pass-123\n";
