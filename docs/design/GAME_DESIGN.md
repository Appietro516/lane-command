# Gameplay and product design

## Map and starting territories

Generate 5–7 irregular territories across the playable map and frame all regions and both bases together. The human and CPU each own one starting region at opposite ends of the map. The remaining regions start neutral. The map seed and region count are configurable on the Match scene. The existing combat simulation moves units between the bases. Units cross regions without capturing them, and ownership has no effect on movement or combat.

Sources: S95c42ca9286d, Se50c19e91616, [generated territory map ticket](https://trello.com/c/gV8QZqOh/9-generate-a-2d-voronoi-style-territory-map)

## Shared economy and production

Proposed defaults give each side 50 starting energy and 3 energy per second. A barracks costs 40 energy and fills the next free slot in the side's starting region, with two slots per side. A one-time production upgrade costs 60 energy and shortens the automatic spawn interval from about 3.5 seconds to 2.5 seconds. Apply the same costs, capacity checks, and production rules to both sides. Reject unaffordable actions and prevent negative energy.

Sources: S95c42ca9286d

## CPU opponent and automatic combat

The CPU must visibly spend resources and build a barracks without player input in the first playable build. Its proposed deterministic priority is first barracks, second barracks, then the production upgrade, with a periodic check such as every 2 seconds. Both sides use the same single unit type and combat rules. Units stop to attack opposing units in range, then attack the opposing base at close range when no opposing unit is in range. Proposed stats are 12 unit HP, 3 attack damage, a 1-second attack cooldown, and 80 HP per base. Remove dead units and stop combat when a base falls.

Sources: S95c42ca9286d, S1389629da9a3

## HUD and match reset

Show player energy, income, barracks count, Build and Upgrade controls, both bases' HP, and Restart. CPU activity is visible through buildings and units, with debug labels allowed. Show Victory when the CPU base falls or Defeat when the player's base falls. Restart restores initial ownership and resources, resets CPU and production timers, and clears buildings, units, upgrades, and claims while restoring base HP.

Sources: S95c42ca9286d, S8f6e375bbe16, Se50c19e91616

## Optional region claiming

The player can select a region on the map and use Claim to acquire a neutral region adjacent to any player-owned region. The initial prototype charges 50 energy per claim, a provisional balance value. A successful claim updates ownership and map color and deducts the cost once. Reject enemy-owned, nonadjacent, already claimed, and unaffordable targets. Claims have no income, production, building-slot, routing, or combat effects in this slice. CPU expansion is deferred.

Sources: S95c42ca9286d, S1389629da9a3, Se50c19e91616
