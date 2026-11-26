# Gameplay and product design

## Map and starting territories

Generate 24 seeded Voronoi territories by default in a 60 × 36 world. The human and CPU each own one starting territory by default, with their bases near opposite ends. Additional starting territories form contiguous groups around each faction’s base. The remaining regions start neutral. Units navigate the open map around active building footprints and cross regions freely.

Use **Match setup** to choose Rectangle, Square, Triangle, or Circle and enter the region count and seed. The playable area grows with the region count. Triangle has an equilateral outline with its apex pointing north. Hover over **Overview** to see the active seed.

Setup supports up to 128 regions and needs enough regions for all faction starts and at least one neutral region. **Restart** with the same settings restores the same geometry and initial owners. Changing the settings creates a fresh match. The same settings can also be configured on the Match root in `main.tscn` before launch.

Sources: S95c42ca9286d, Se50c19e91616, [generated territory map ticket](https://trello.com/c/gV8QZqOh/9-generate-a-2d-voronoi-style-territory-map), [configurable territory map ticket](https://trello.com/c/HfqeIWVg/20-scale-up-seeded-voronoi-maps-with-configurable-region-counts-and-starting-territory)

Pan with WASD, the arrow keys, or middle-mouse drag. Scroll to zoom and use Home or the Overview button to frame the whole map. Left-click a structure to select its region.

The prototype uses six fitted cells with straight seams and flat ownership fills. Blue marks the player, coral marks the CPU, slate marks neutral territory, and a pale rim marks the selection. Circular bases, long barracks roofs, and triangular unit markers give each piece a distinct silhouette at a distance.

This treatment favors a tactical board over a natural landscape. Terrain detail and architectural identity remain art-direction choices. Ownership at a glance still depends on color.

## Shared economy and production

Provisional defaults give each side 50 Energy at +3/s, 30 Materials at +2/s, and 20 Food at +1/s. Barracks cost 40 Energy and 20 Materials. Training Ranges cost 45 Energy and 25 Materials. Heavy Factories cost 55 Energy and 35 Materials. The Build menu lists building types and their prices. Choose a building and click inside owned territory to place it, keeping structures and military exits clear. The preview indicates whether the point is valid, and Cancel, Escape, or right-click exits placement. Each military producer has a one-time inspector upgrade for 60 Energy and 15 Food. A level-two Barracks shortens its cycle from 3.5 seconds to 2.5 seconds. The other military producers use the same proportional speed increase. Both sides use the same construction costs, placement checks, and production rules. Purchases require sufficient stock in every listed resource and deduct the full price together.

Each region holds five buildings by default. The starting base, claim outpost, Legendary landmark, producers, and gun defenses each occupy one slot in every region their footprint overlaps. Inactive buildings still occupy space until destroyed. Neutral regions reserve capacity for their claim outpost. Select a region to see its used and free slots, then hover over the slot readout for the building counts, inactive counts, and zero-slot wall segments. Build options that need slots are disabled when all owned regions are full.

Barracks deploy Infantry for 4 Food per cycle. Training Ranges deploy Ranged for 5 Food every 4.5 seconds. Heavy Factories deploy Heavy for 8 Food every 6 seconds. Each military producer holds one completed cycle until the faction can pay. Generators cost 26 Materials and add 2 Energy/s. Mines cost 24 Materials and 15 Energy and add 2 Materials/s. Farms cost 20 Materials and add 3 Food/s. Each faction can build multiple producers in starting or claimed territory. Destroying a producer ends its output. Producers in lost territory pause until their original owner reclaims the region. These prices and rates are provisional.

Build stays available during play so players can inspect prices. Unaffordable options stay visible and re-enable as resources recover. Machine gun nests fire rapid single-target shots with line of sight. Mortars fire more slowly, reach farther, and damage enemies within both weapon range and the splash radius around the impact. Gun previews and inspection show attack range and the mortar splash radius. A brief tracer or impact ring marks each shot.

Drag to draw a straight wall in owned territory. The preview rounds length down to whole units and shows the total price before release. A valid drag buys one independently destructible segment per unit of length. Each segment must fit entirely in owned territory and leave existing structures and production exits clear. Units can route around active walls or attack hostile segments when a wall cuts off their route. Fortifications stay in place and remain destructible if the faction loses a region they occupy. They resume firing or blocking passage when their faction reclaims the entire footprint.

Sources: S95c42ca9286d
[Three-resource economy ticket](https://trello.com/c/SesjHC9Y/15-expand-the-economy-to-three-resources)

## CPU opponent and automatic combat

Choose CPU difficulty before starting or restarting a match. The active level appears below Restart, and the picker keeps that level selected for the current session. Each level describes its behavior in the picker. Standard is the default.

| Level | CPU decision interval | Strategy |
| --- | ---: | --- |
| 1 · Relaxed | 5.5 s | Favors nearby claims and basic troops, keeps a smaller reserve, and reacts slowly. |
| 2 · Casual | 3.5 s | Builds a mixed force and basic economy with slower threat response. |
| 3 · Standard | 2 s | Balances growth, scout claims, counters, and defenses. |
| 4 · Challenging | 1.5 s | Invests earlier and weighs useful, safe claims and local counters more heavily. |
| 5 · Expert | 1 s | Considers the most routes and sites and reacts fastest to nearby threats. |

Challenging and Expert use visible enemy military buildings to anticipate unit types. They prioritize a second military producer when there is room to support it and keep some slots available for reinforcements and defenses when planning optional income buildings. Both sides begin with two scouts and use the same resource, construction, production, combat, and claim rules at every level. The CPU considers one action per decision. It weighs military producers using construction savings, Food demand, the current army and producers, and combat matchups. Enemies near a held base or outpost have more influence, and nearby defensive guns favor units that can fire from behind the line. The production target grows with territory and leaves room for a reinforcement under pressure, subject to a construction cap. The CPU adds Farms when current or projected production needs Food and buys Mines and Generators when their income can cover projected construction spending. The CPU protects a Food reserve for deployments when buying upgrades or mortars. Under pressure near its base or outposts, it positions machine gun nests to cover active approaches, places mortars farther back, and chooses anti-tank guns against groups of Heavy units. Short walls intercept an observed approach with room on both ends for units to pass. The CPU limits fortifications per defended region and retries blocked sites after a cooldown. Both sides use the same unit roster and combat rules. Combat units start with their producer's configured stance. Both factions can assign each unit a stance or order. Seeking units with no reachable local opponent attack reachable enemy outposts or advance toward the opposing base. Bases have 80 HP. Remove dead units and stop combat when a base falls.

Infantry is the general-purpose unit with 12 HP, 3 damage per hit and a 1-second cooldown. Ranged has less HP, fires faster from farther away and favors targets it can hit immediately. Heavy has more HP, moves slower, costs more Food and deals extra damage to structures. Catalog values are provisional.

Sources: S95c42ca9286d, S1389629da9a3

## Unit orders

Inspect a military producer to see its next unit type, level, production countdown, and default stance. Each producer starts in Seek Nearest. An owned producer can set a reachable rally point anywhere on the battlefield. Its future deployments move there and then resume the configured stance. Clear the rally to deploy at the exit. Producers retain their settings and cycle progress while paused.

Left-click a player or CPU unit to inspect its type, HP, attack damage, weapon range, cooldown, movement speed, orders, current target and state. A ring marks the unit, and a line traces its remaining route to the current movement destination. Click the map or press Escape to clear inspection. Building placement takes priority over unit selection.

With a player combat unit selected, choose Seek Nearest, Seek Strongest, or Idle to clear its current order and apply that stance. Seek Nearest pursues the closest reachable hostile within detection range. Seek Strongest looks in the same radius and ranks reachable hostiles by `2 × effective DPS + 0.25 × current HP`. The Match scene exposes both weights. Equal threat scores favor shorter distance, and equal distances favor lower unit IDs. Idle leaves the unit in reserve at its current position with no automatic attacks.

Right-drag on the battlefield to select friendly units. Shift adds units and Ctrl removes them. The inspector shows unit counts and combined HP for a group. Right-click ground, or click Move and choose ground, to issue a move order. Groups take nearby formation positions. **Resume stance after Move** starts checked and restores the unit’s stance on arrival. Uncheck it to Hold at the destination. A reachable hostile wall can be breached if removing it opens the route. Use **Hold here** to defend the current position or **Hold at…** to choose a post on the map. At the post, any stance can fire on detected enemies in weapon range with a clear shot. Hold units fire without leaving their post. The existing target priority setting controls which available shot a defender takes. CPU unit stances and orders are visible when inspected.

[Autonomous combat and right-click orders ticket](https://trello.com/c/mHKVpPnR/12-replace-fixed-lane-with-autonomous-combat-and-right-click-unit-orders)


## Support, counters, and strategic strikes

| Unit | HP | Speed | Food | Action |
| --- | ---: | ---: | ---: | --- |
| Medic | 9 | 2.0 | 6 | Heals one nearby ally by up to 2.5 HP every 1.2 seconds, within 2 world units. A recipient waits 0.85 seconds before further healing. |
| Raider | 9 | 3.0 | 5 | Attacks for 2.7 damage every 0.8 seconds at range 0.8. Deals ×1.7 damage to Infantry and ×0.75 to Heavy. Ranged and Heavy deal ×2 and ×1.25 to Raiders. |

The 30 HP Aid Station costs 52 Energy and 28 Materials and deploys a Medic every 6.5 seconds. The 29 HP Raider Camp costs 48 Energy and 25 Materials and deploys a Raider every 4.6 seconds. The CPU adds a limited Medic complement to established forces and chooses Raiders against Infantry-heavy threats.

The 32 HP Anti-Tank Gun uses one slot and costs 54 Energy and 34 Materials. It prioritizes armor and deals 14 damage to Heavy or 1.8 to Infantry at range 6.0, with 1.85 seconds between single-target shots.

The 65 HP Missile Silo uses four slots and costs 390 Energy, 270 Materials, and 45 Food. Its inspector targets a 7-unit blast radius. One click commits a public 12-second charge. Destroying the silo before launch cancels the strike. After launch, the silo is exhausted and the missile arrives 2.4 seconds later. Damage uses unit centers and structure footprints. A region becomes permanently ruined when its ownership hub or, for a region without a hub, its Voronoi site falls within the blast. Ruined regions are neutral and passable. They cannot support new outposts, buildings, or ownership income before restart.

## HUD and match reset

Show the player's resource stockpiles and net income rates, Build, faction base HP, and Restart. Group buildable structures under Economy, Military, Fortifications, and Strategic. Show upgrade controls in the selected producer’s inspector. Show region slots, claim progress and landmark effects when inspecting the region. Hover over or click a resource to see its passive rate, individual sources, and total. Open Stat sources in the inspector for base values, named modifiers, and effective totals. Producer and barracks output reflects whether the building is active. CPU activity is visible through buildings and units, with debug labels allowed. Show Victory when every opposing base falls or Defeat when the player’s base falls. Restart restores initial ownership and resources, resets CPU and production timers, and clears buildings, units, upgrades, and claims while restoring base HP.

Sources: S95c42ca9286d, S8f6e375bbe16, Se50c19e91616

## Scout expeditions

Both factions begin with two noncombat Scouts. Select a neutral region adjacent to friendly territory and use Claim. The available Scout with the shortest reachable travel time is dispatched, with Scout ID breaking ties. Claim is disabled when no Scout is available. Select a Scout on the map or in the roster to inspect it or recall an active expedition. A reachable dispatch reserves the region and costs 50 Energy by default. The Scout travels to an interior site and stays there for 20 seconds by default. The map and inspector show the Scout’s progress and estimated completion time. Only completion changes the region color, allows building, and establishes a destructible outpost with 24 HP by default.

A Scout can return from a recalled expedition, and a defeated or blocked expedition releases its reservation. Energy spent on dispatch stays spent. A lost Scout can be replaced near its base after 15 seconds for 35 Energy by default. Each faction has two Scout slots. The CPU uses the same expedition and replacement rules. It compares travel time and enemy exposure on reachable routes, connections to nearby regions, landmark bonuses, and room for construction after the outpost takes its slot. It prioritizes reclaiming dormant investments when safe and sets aside Energy for defense before dispatching.

Destroying an outpost returns its region to neutral, so it no longer supports building placement or further claims for the former owner. Existing producers stay visible. Barracks still appear in their faction's barracks count. Military production pauses until their original faction pays to reclaim the region, then resumes from the existing timer. Only the starting bases determine victory and defeat. Restart clears expansion outposts.

A faction's first successful claim in a region reveals one discovery. The player chooses between two or three disclosed outcomes while the match is paused. The CPU chooses from the same discoveries during play. Rewards include small supply grants, trades, and brief income or unit bonuses. Losing and reclaiming the region gives that faction no additional discovery. Restart clears claim discovery history and reproduces the same draw for the same region and faction with the same seed.

Legendary landmarks mark contested regions with a gold crystal. Select the landmark or its region to see the name, bonus, and current controller. A neutral landmark is inactive. Its bonus applies to the faction that owns the region and stacks with bonuses from other landmarks. Destroying the claim outpost returns the region to neutral and suspends the bonus. The landmark stays in place and activates for the next owner.

Sources: S95c42ca9286d, S1389629da9a3, Se50c19e91616
