# Engineering and architecture

## Runtime and presentation

The proposed runtime uses Godot 4.6.3 and GDScript with Compatibility rendering, a fixed orthographic Camera3D, Windows export, and single-threaded Web export. Use built-in primitives for structures and generate polygon geometry for territories. The prototype excludes C#, networking, navigation agents, terrain tooling, and complex third-party frameworks.

Sources: S8f6e375bbe16, Se50c19e91616

## State and simulation

Generate the region graph by clipping the map bounds around seeded Voronoi sites. Each cell has a stable ID, a polygon, and neighbors that share a border of positive length. The scene tracks ownership and resolves world positions to the nearest site inside the map bounds, breaking ties by site order. Track each side's energy, owned regions, base HP, barracks count, upgrade, and timers. Track unit side, position along the corridor, HP, attack cooldown, and target. Track simulation time and match outcome. Keep rules testable independently of rendering where practical, step shared combat deterministically with delta, and centralize balance values and CPU cadence.

Sources: S8f6e375bbe16, S95c42ca9286d

Corridor combat consumes elapsed time in fixed 60 Hz steps. Units target from the same snapshot before resolving attacks, and casualties are removed after all attacks for that step. The match scene derives the combat endpoints from bases placed in the generated starting regions and renders the battle state.

## Rules interfaces and validation

The proposed responsibility split gives match logic authority over purchases, claims, CPU actions, and end states. Shared battle logic handles spawning, movement, targeting, damage, and cleanup. Map visuals and HUD reflect state through the shared rules interface. Use a single side-and-region claim API that validates ownership, adjacency, and cost. Keep any browser instrumentation minimal and read-only. Cover initial ownership and adjacency, valid and invalid claims and purchases, barracks capacity, CPU actions, symmetric spawning, combat, outcomes, and reset in headless logic tests. A headless scene-load test checks initialization.

Sources: S8f6e375bbe16, S95c42ca9286d
