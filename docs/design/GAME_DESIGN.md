# Gameplay and product design

## Map and starting territories

Generate 5–7 irregular territories across the playable map and frame all regions and both bases together. The human and CPU each own one starting region at opposite ends of the map. The remaining regions start neutral. The map seed and region count are configurable on the Match scene. Units navigate the open map around building footprints. Units cross regions without capturing them, and ownership has no effect on movement or combat.

Sources: S95c42ca9286d, Se50c19e91616, [generated territory map ticket](https://trello.com/c/gV8QZqOh/9-generate-a-2d-voronoi-style-territory-map)

Pan with WASD, the arrow keys, or middle-mouse drag. Scroll to zoom and use Home or the Overview button to frame the whole map. Left-click a structure to select its region.

The prototype uses six fitted cells with straight seams and flat ownership fills. Blue marks the player, coral marks the CPU, slate marks neutral territory, and a pale rim marks the selection. Circular bases, long barracks roofs, and triangular unit markers give each piece a distinct silhouette at a distance.

This treatment favors a tactical board over a natural landscape. Terrain detail and architectural identity remain art-direction choices. Ownership at a glance still depends on color.

## Shared economy and production

Proposed defaults give each side 50 starting energy and 3 energy per second. A barracks costs 40 energy, with a capacity of two barracks per side. The Build menu lists building types and their energy costs. Choose a building and click any point inside owned territory to place it. The preview indicates whether the point is valid, and Cancel, Escape, or right-click exits placement. A one-time production upgrade costs 60 energy and shortens the automatic spawn interval from about 3.5 seconds to 2.5 seconds. Apply the same costs, capacity checks, and production rules to both sides. Reject unaffordable actions and prevent negative energy.

Sources: S95c42ca9286d

## CPU opponent and automatic combat

The CPU must visibly spend resources and build a barracks without player input in the first playable build. Its proposed deterministic priority is first barracks, second barracks, then the production upgrade, with a periodic check such as every 2 seconds. Both sides use the same single unit type and combat rules. Units deploy from their producing barracks and pursue the nearest reachable opponent within their detection radius by default. When no local enemy unit is available, autonomous units advance toward the opposing base and attack at close range. Proposed stats are 12 unit HP, 3 attack damage, a 1-second attack cooldown, and 80 HP per base. Remove dead units and stop combat when a base falls.

Sources: S95c42ca9286d, S1389629da9a3

## Unit orders

Left-click a player or CPU unit to inspect its HP, attack damage, movement speed, current target, and state. A ring marks the unit, and a line traces its remaining route to the current movement destination. Click the map or press Escape to clear inspection. Building placement takes priority over unit selection.

With a player unit selected, right-click reachable ground to issue or replace a move order. The unit can engage nearby opponents during transit and resumes its destination when the threat passes. On arrival it holds the area, engages local threats within its detection radius around the destination, and returns to that location after combat. Detection range and local target priority are tunable on the Match scene.

[Autonomous combat and right-click orders ticket](https://trello.com/c/mHKVpPnR/12-replace-fixed-lane-with-autonomous-combat-and-right-click-unit-orders)

## HUD and match reset

Show player energy, income, barracks count, Build and Upgrade controls, both bases' HP, and Restart. CPU activity is visible through buildings and units, with debug labels allowed. Show Victory when the CPU base falls or Defeat when the player's base falls. Restart restores initial ownership and resources, resets CPU and production timers, and clears buildings, units, upgrades, and claims while restoring base HP.

Sources: S95c42ca9286d, S8f6e375bbe16, Se50c19e91616

## Optional region claiming

The player can select a region on the map and use Claim to acquire a neutral region adjacent to any player-owned region. The initial prototype charges 50 energy per claim, a provisional balance value. A successful claim updates ownership and map color and deducts the cost once. Reject enemy-owned, nonadjacent, already claimed, and unaffordable targets. Claimed regions immediately become available for building placement. Claims have no direct effect on income, production, routing, or combat. CPU expansion is deferred.

Sources: S95c42ca9286d, S1389629da9a3, Se50c19e91616
