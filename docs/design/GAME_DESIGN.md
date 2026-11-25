# Gameplay and product design

## Map and starting territories

Generate 24 seeded Voronoi territories by default in a 60 × 36 world. The human and CPU each own one starting territory by default, with their bases near opposite ends. Additional starting territories form contiguous groups around each faction’s base. The remaining regions start neutral. Units navigate the open map around active building footprints and cross regions freely.

Open `main.tscn` and select the Match root to configure **Map** in the Inspector. Set the width, height, region count, seed, and starting region count for each faction before launching the match. Hover over **Overview** in game to see the active seed. **Restart** restores the same map and its initial owners.

Each map dimension accepts 18–192 world units. A nonpositive or nonfinite dimension uses its default, and other out-of-range values clamp to the supported bounds. The generator fits 2–128 regions subject to the map’s capacity at a minimum five-unit site grid pitch. Each side starts with at least one region. If the requested starting territories exceed the effective region count, each side receives one.

Sources: S95c42ca9286d, Se50c19e91616, [generated territory map ticket](https://trello.com/c/gV8QZqOh/9-generate-a-2d-voronoi-style-territory-map), [configurable territory map ticket](https://trello.com/c/HfqeIWVg/20-scale-up-seeded-voronoi-maps-with-configurable-region-counts-and-starting-territory)

Pan with WASD, the arrow keys, or middle-mouse drag. Scroll to zoom and use Home or the Overview button to frame the whole map. Left-click a structure to select its region.

The prototype uses six fitted cells with straight seams and flat ownership fills. Blue marks the player, coral marks the CPU, slate marks neutral territory, and a pale rim marks the selection. Circular bases, long barracks roofs, and triangular unit markers give each piece a distinct silhouette at a distance.

This treatment favors a tactical board over a natural landscape. Terrain detail and architectural identity remain art-direction choices. Ownership at a glance still depends on color.

## Shared economy and production

Provisional defaults give each side 50 Energy at +3/s, 30 Materials at +2/s, and 20 Food at +1/s. Barracks cost 40 Energy and 20 Materials. Training Ranges cost 45 Energy and 25 Materials. Heavy Factories cost 55 Energy and 35 Materials. The Build menu lists building types and their prices. Choose a building and click inside owned territory to place it, keeping structures and military exits clear. The preview indicates whether the point is valid, and Cancel, Escape, or right-click exits placement. A one-time Barracks upgrade costs 60 Energy and 15 Food and shortens the automatic spawn interval from 3.5 seconds to 2.5 seconds. Both sides use the same construction costs, placement checks, and production rules. Purchases require sufficient stock in every listed resource and deduct the full price together.

Barracks deploy Infantry for 4 Food per cycle. Training Ranges deploy Ranged for 5 Food every 4.5 seconds. Heavy Factories deploy Heavy for 8 Food every 6 seconds. Each military producer holds one completed cycle until the faction can pay. Generators cost 26 Materials and add 2 Energy/s. Mines cost 24 Materials and 15 Energy and add 2 Materials/s. Farms cost 20 Materials and add 3 Food/s. Each faction can build multiple producers in starting or claimed territory. Destroying a producer ends its output. Producers in lost territory pause until their original owner reclaims the region. These prices and rates are provisional.

Build stays available during play so players can inspect prices. Unaffordable options stay visible and re-enable as resources recover. Machine gun nests fire rapid single-target shots with line of sight. Mortars fire more slowly, reach farther, and damage enemies within both weapon range and the splash radius around the impact. Gun previews and inspection show attack range and the mortar splash radius. A brief tracer or impact ring marks each shot.

Drag to draw a straight wall in owned territory. The preview rounds length down to whole units and shows the total price before release. A valid drag buys one independently destructible segment per unit of length. Each segment must fit entirely in owned territory and leave existing structures and production exits clear. Units can route around active walls or attack hostile segments when a wall cuts off their route. Fortifications stay in place and remain destructible if the faction loses a region they occupy. They resume firing or blocking passage when their faction reclaims the entire footprint.

Sources: S95c42ca9286d
[Three-resource economy ticket](https://trello.com/c/SesjHC9Y/15-expand-the-economy-to-three-resources)

## CPU opponent and automatic combat

Every two seconds by default, the CPU considers one purchase. It weighs Barracks, Training Ranges, and Heavy Factories using construction savings, Food demand, the current army and producers, and combat matchups. Enemies near a held base or outpost have more influence, and nearby defensive guns favor units that can fire from behind the line. The production target grows with territory and leaves room for a reinforcement under pressure, subject to a construction cap. The CPU adds Farms when current or projected production needs Food and buys Mines and Generators when their income can cover projected construction spending. The CPU protects a Food reserve for deployments when buying upgrades or mortars. Under pressure near its base or outposts, it positions machine gun nests to cover active approaches and places mortars to defend from farther back. Short walls intercept an observed approach with room on both ends for units to pass. The CPU limits fortifications per defended region and retries blocked sites after a cooldown. Both sides use the same unit roster and combat rules. Units pursue the nearest reachable opponent within their detection radius by default. When no local enemy unit is available, autonomous units attack reachable enemy outposts or advance toward the opposing base. Bases have 80 HP. Remove dead units and stop combat when a base falls.

Infantry is the general-purpose unit with 12 HP, 3 damage per hit and a 1-second cooldown. Ranged has less HP, fires faster from farther away and favors targets it can hit immediately. Heavy has more HP, moves slower, costs more Food and deals extra damage to structures. Catalog values are provisional.

Sources: S95c42ca9286d, S1389629da9a3

## Unit orders

Left-click a player or CPU unit to inspect its type, HP, attack damage, weapon range, cooldown, movement speed, orders, current target and state. A ring marks the unit, and a line traces its remaining route to the current movement destination. Click the map or press Escape to clear inspection. Building placement takes priority over unit selection.

With a player unit selected, right-click reachable ground to issue or replace a move order. The unit can engage nearby opponents during transit and resumes its destination when the threat passes. On arrival it holds the area, engages local threats within its detection radius around the destination, and returns to that location after combat. Detection range and local target priority are tunable on the Match scene.

[Autonomous combat and right-click orders ticket](https://trello.com/c/mHKVpPnR/12-replace-fixed-lane-with-autonomous-combat-and-right-click-unit-orders)

## HUD and match reset

Show the player's resource stockpiles and net income rates, barracks count, Build and Upgrade controls, both bases' HP, and Restart. Hover over or click a resource to see its passive rate, individual sources, and total. Open Stat sources in the inspector for base values, named modifiers, and effective totals. Producer and barracks output reflects whether the building is active. CPU activity is visible through buildings and units, with debug labels allowed. Show Victory when the CPU base falls or Defeat when the player's base falls. Restart restores initial ownership and resources, resets CPU and production timers, and clears buildings, units, upgrades, and claims while restoring base HP.

Sources: S95c42ca9286d, S8f6e375bbe16, Se50c19e91616

## Scout expeditions

Both factions begin with two noncombat Scouts. Select a Scout on the map or in the Scout roster, select a neutral region adjacent to friendly territory, and use Claim. A reachable dispatch reserves the region and costs 50 Energy by default. The Scout travels to an interior site and stays there for 20 seconds by default. The map and inspector show the Scout’s progress and estimated completion time. Only completion changes the region color, allows building, and establishes a destructible outpost with 24 HP by default.

A Scout can return from a recalled expedition, and a defeated or blocked expedition releases its reservation. Energy spent on dispatch stays spent. A lost Scout can be replaced near its base after 15 seconds for 35 Energy by default. Each faction has two Scout slots. The CPU uses the same expedition and replacement rules and considers landmarks, dormant buildings, and threats when expanding.

Destroying an outpost returns its region to neutral, so it no longer supports building placement or further claims for the former owner. Existing producers stay visible. Barracks still appear in their faction's barracks count. Military production pauses until their original faction pays to reclaim the region, then resumes from the existing timer. Only the starting bases determine victory and defeat. Restart clears expansion outposts.

Legendary landmarks mark contested regions with a gold crystal. Select the landmark or its region to see the name, bonus, and current controller. A neutral landmark is inactive. Its bonus applies to the faction that owns the region and stacks with bonuses from other landmarks. Destroying the claim outpost returns the region to neutral and suspends the bonus. The landmark stays in place and activates for the next owner.

Sources: S95c42ca9286d, S1389629da9a3, Se50c19e91616
