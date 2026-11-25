# Engineering and architecture

## Runtime and presentation

The runtime uses Godot 4.6.3 and GDScript with Compatibility rendering, an orthographic Camera3D, Windows export, and single-threaded Web export. Use built-in primitives for structures and generate polygon geometry for territories. The prototype excludes C#, networking, navigation agents, terrain tooling, and complex third-party frameworks.

Sources: S8f6e375bbe16, Se50c19e91616

## State and simulation

Generate the region graph by clipping the map bounds around seeded Voronoi sites. Each cell has a stable ID, a polygon, and neighbors that share a border of positive length. The scene tracks ownership and resolves world positions to the nearest site inside the map bounds, breaking ties by site order. Track each side's resource stockpiles, income sources, owned regions, base HP, barracks count, upgrade, and timers. Track unit side, map-plane position, HP, attack cooldown, target, order, ordered destination, current movement destination, and remaining waypoints. Track simulation time and match outcome. Keep rules testable independently of rendering where practical, step shared combat deterministically with delta, and centralize balance values and CPU cadence.

Sources: S8f6e375bbe16, S95c42ca9286d

`MatchEconomy` defines resources by stable ID, label, starting stockpile, and baseline rate. Each side holds its own stockpiles. A purchase validates every entry in its resource-to-amount cost before debiting stockpiles.

The match shares one `FactionStats` between economy and battle. Register a flat modifier with `set_modifier()` using a stable source ID and a stat key. Reusing that pair replaces its contribution. One source can contribute to several stats, and `remove_source()`, `set_source_owner()`, and `set_source_active()` update the whole source. Use `set_region_modifier()` for contributions that follow region ownership. Battle exposes source IDs for bases, outposts, and barracks so contributions can follow destruction or activation. Restart creates a fresh registry.

Income, unit DPS, damage per attack, and maximum building HP expose computed totals with named source breakdowns. The registry adds the baseline first and then modifiers in lexical source ID order. Disabled entries retain their configured magnitude and contribute zero. Damage per attack scales each DPS contribution by the unit's attack interval. Bases and outposts start at their effective maximum HP. Later cap increases preserve current HP, and decreases clamp it to the new cap.

Combat consumes elapsed time in fixed 60 Hz steps. Units plan from the same snapshot before movement and damage, and casualties are removed after all attacks for that step. The match scene projects pointer input to the same map plane and renders the battle state. Routes use direct segments or an AStar2D graph of building footprint corners. Adding a building invalidates cached routes. Unit state is available by ID through `MatchBattle.get_unit()` and by current selection through `selected_unit()` on the match scene.

The camera keeps its viewing angle fixed and moves its focus within the map bounds. Its zoom range runs from a close tactical view to an overview fitted to the projected map and HUD. Placement stores the map point at click time so camera movement before the next physics tick cannot move the purchase.

## Rules interfaces and validation

The proposed responsibility split gives match logic authority over purchases, claims, CPU actions, and end states. Shared battle logic handles spawning, movement, targeting, damage, and cleanup. Map visuals and HUD reflect state through the shared rules interface. Register each building type in the match catalog with its label, cost, visual scene, and purchase rules. The menu and placement logic read this catalog and use the same Voronoi lookup as region selection to resolve ownership at the cursor. Use a single side-and-region claim API that validates ownership, adjacency, and cost. Keep any browser instrumentation minimal and read-only. Cover initial ownership and adjacency, valid and invalid claims and purchases, barracks capacity, CPU actions, symmetric spawning, combat, outcomes, and reset in headless logic tests. A headless scene-load test checks initialization.

Sources: S8f6e375bbe16, S95c42ca9286d
