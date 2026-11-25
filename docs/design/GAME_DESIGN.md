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

Provisional defaults give each side 50 Energy at +3/s, 30 Materials at +2/s, and 20 Food at +1/s. A barracks costs 40 Energy and 20 Materials. The Build menu lists building types and their prices. Choose a building and click inside owned territory to place it, keeping outpost footprints clear. The preview indicates whether the point is valid, and Cancel, Escape, or right-click exits placement. A one-time production upgrade costs 60 Energy and 15 Food and shortens the automatic spawn interval from 3.5 seconds to 2.5 seconds. Both sides use the same construction costs, placement checks, and production rules. Purchases require sufficient stock in every listed resource and deduct the full price together.

Each unit costs 4 Food. A barracks with a completed cycle waits until the faction can pay, then deploys one unit. Generators cost 26 Materials and add 2 Energy/s. Mines cost 24 Materials and 15 Energy and add 2 Materials/s. Farms cost 20 Materials and add 3 Food/s. Producers stack and can be placed in starting or claimed territory. Destroyed producers lose their income. Producers in lost territory pause until their original owner reclaims the region. These prices and rates are provisional.

Build stays available during play so players can inspect prices. Unaffordable options stay visible and re-enable as resources recover. Machine gun nests fire rapid single-target shots with line of sight. Mortars fire more slowly, reach farther, and damage enemies within both weapon range and the splash radius around the impact. Gun previews and inspection show attack range and the mortar splash radius. A brief tracer or impact ring marks each shot.

Drag to draw a straight wall in owned territory. The preview rounds length down to whole units and shows the total price before release. A valid drag buys one independently destructible segment per unit of length. Each segment must fit entirely in owned territory and leave existing structures and production exits clear. Units can route around active walls or attack hostile segments when a wall cuts off their route. Fortifications stay in place and remain destructible if the faction loses a region they occupy. They resume firing or blocking passage when their faction reclaims the entire footprint.

Sources: S95c42ca9286d
[Three-resource economy ticket](https://trello.com/c/SesjHC9Y/15-expand-the-economy-to-three-resources)

## CPU opponent and automatic combat

Every two seconds the CPU checks for a purchase. It uses opening food reserves to establish production, adds enough income to fund upgraded production, buys the upgrade, and develops its economy. It adds more barracks as food income and construction resources allow. Both sides use the same single unit type and combat rules. Units deploy from their producing barracks and pursue the nearest reachable opponent within their detection radius by default. When no local enemy unit is available, autonomous units attack reachable enemy outposts or advance toward the opposing base. Proposed stats are 12 unit HP, 3 attack damage, a 1-second attack cooldown, and 80 HP per base. Remove dead units and stop combat when a base falls.

Sources: S95c42ca9286d, S1389629da9a3

## Unit orders

Left-click a player or CPU unit to inspect its HP, attack damage, movement speed, current target, and state. A ring marks the unit, and a line traces its remaining route to the current movement destination. Click the map or press Escape to clear inspection. Building placement takes priority over unit selection.

With a player unit selected, right-click reachable ground to issue or replace a move order. The unit can engage nearby opponents during transit and resumes its destination when the threat passes. On arrival it holds the area, engages local threats within its detection radius around the destination, and returns to that location after combat. Detection range and local target priority are tunable on the Match scene.

[Autonomous combat and right-click orders ticket](https://trello.com/c/mHKVpPnR/12-replace-fixed-lane-with-autonomous-combat-and-right-click-unit-orders)

## HUD and match reset

Show the player's resource stockpiles and net income rates, barracks count, Build and Upgrade controls, both bases' HP, and Restart. Hover over a resource to see its baseline rate, any additional sources, and the total. CPU activity is visible through buildings and units, with debug labels allowed. Show Victory when the CPU base falls or Defeat when the player's base falls. Restart restores initial ownership and resources, resets CPU and production timers, and clears buildings, units, upgrades, and claims while restoring base HP.

Sources: S95c42ca9286d, S8f6e375bbe16, Se50c19e91616

## Optional region claiming

The player can select a neutral region adjacent to existing territory and use Claim to spend 50 Energy and acquire it. A successful claim changes the map color, opens building placement, and adds one outpost with 24 HP by default. Select its region to inspect its health. Both factions use the same claim rules. Automated CPU expansion is deferred.

Destroying an outpost returns its region to neutral, so it no longer supports building placement or further claims for the former owner. Existing barracks stay visible and still appear in their faction's barracks count. Production pauses until their original faction pays to reclaim the region, then resumes from the existing timer. Only the starting bases determine victory and defeat. Restart clears expansion outposts.

Legendary landmarks mark contested regions with a gold crystal. Select the landmark or its region to see the name, bonus, and current controller. A neutral landmark is inactive. Its bonus applies to the faction that owns the region and stacks with bonuses from other landmarks. Destroying the claim outpost returns the region to neutral and suspends the bonus. The landmark stays in place and activates for the next owner.

Sources: S95c42ca9286d, S1389629da9a3, Se50c19e91616
