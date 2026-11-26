# Navigation and pathfinding baseline

## Reproduce

Game source at `3d4918fe6e6a5421732ed7ac2899586a81845fcb` (ticket's master checkout). Run from the project root with Python 3 and the pinned Godot 4.6.3. Set `GODOT` if the executable is outside PATH. Give each run a fresh scratch directory. [Benchmark harness](../../tests/performance)

```sh
python3 tests/performance/run_navigation_benchmark.py --output /tmp/lane-nav-matrix --suite matrix
python3 tests/performance/run_navigation_benchmark.py --output /tmp/lane-nav-match --suite match
xvfb-run -a -s '-screen 0 1280x800x24' python3 tests/performance/run_navigation_benchmark.py --output /tmp/lane-nav-desktop --suite match --display native --mode baseline
```

The runner copies the working source and harness to scratch. Default mode `both` runs one pristine copy and a second copy with scoped probes injected at method boundaries. Use the documented SHA's game files for comparison. The runner retains import and engine logs, exports JSON Lines and compares phase populations, revision counts and unit-state hashes across copies. Matrix assertions check accepted orders, segment safety, and destruction cleanup. The match workload asserts claim ownership, legal wall purchase, and cleanup after losing the outpost. Select `--suite normal` or `--suite ownership` to repeat just one match scenario. The native command can run directly on a desktop display without the Xvfb prefix.

## Environment

Raspberry Pi 4 Model B Rev 1.2, ARM64, four Cortex-A72 cores up to 1.5 GHz, 3.7 GiB available to Linux, Debian 13 and kernel `6.12.47+rpt-rpi-v8`. CPU governor was `ondemand`. Godot reports official debug-capable build `4.6.3.stable.official.7d41c59c4`. The headless matrix uses the dummy display. Native desktop uses X11 through Xvfb, a 1280 × 800 viewport, Compatibility OpenGL and Mesa 26.2.7-1~bpo13+0~rpt1 llvmpipe (LLVM 19.1.7, 128 bits), with dummy audio. The X11 driver reported that it could not change VSync mode. The software-rendered data characterize this host. Hardware rendering and release build behavior need separate runs.

Windows runtime was unavailable on this ARM Linux host. Chromium was installed but the pinned Web export template and a runnable Web benchmark were unavailable. Routine Windows and Web export checks remain with the project CI workflow.

## Method

- **Matrix** uses seed 17 and a fixed 60 × 36 battle plane. It pairs 20, 40 and 60 initial footprints with 12 and 48 units evenly split by side and catalog clearance (0.00, 0.10, 0.34). The layout uses two bases, three central wall segments, one barracks and a seeded subset of jitter-rotated wall segments. Higher counts extend the same obstacle layout. At 60 footprints the uninstrumented construction frames already exceeded eight seconds. The bounded matrix uses 40 and 60 in place of 100 and 500 to keep repeated runs practical on this host.
- **Orders and events** use two simultaneous opposing move bursts on identical endpoints, followed by 60 fixed steps with retained routes. The next three 30-step windows add one wall across an ordered lane, remove the original center wall, and remove two additional walls plus the barracks in the same combat step. For destruction, the fixture sets HP to zero on the event tick so the regular cleanup and navigation revision paths run at a repeatable point. At 20 initial footprints, one final 30-step window places both armies across the newly built wall and lets the live engagement planner run.
- **Match** loads the actual 24-region default match scene, including HUD, rendering, scouts, income and the CPU decision scheduler. It advances six simulated seconds with ordinary CPU decisions. A fresh match handles a scripted claim-completion callback, a legal three-segment purchase, then destruction of the outpost and loss of the region. The timed claim bypasses player input and scout travel and disables the discovery dialogue in that fixture to keep combat running. The ownership handler deactivates the region's walls, leaving the placed structures intact.
- **Timing** uses Godot's monotonic microsecond clock. Every measured engine iteration advances one 60 Hz step except the two standalone command bursts. Baseline `frame_us` samples one actual engine iteration from immediately before the scripted update to the next `process_frame`. With fixed FPS, the clock stays real while simulation delta stays fixed. `work_us` is synchronous scripted work in the same iteration and includes callbacks. For multi-frame phases, percentiles use nearest rank. For one-frame bursts the only frame is also the worst frame. Preparation, assertions and phase transitions sit outside the sample windows. A baseline run provides one seeded sample per case.
- **Profiler counters** show calls, inclusive microseconds, exclusive microseconds and worst single call, in that order. Exclusive time subtracts immediate measured children. `line_clear` is split by its measured caller so graph visibility checks can be distinguished from endpoint visibility, direct routes, and combat checks. `astar/*` timings measure native API boundaries including GDScript bindings and timer overhead. `get_point_path` measures the search call separately from point/edge setup and removal. `line_clear` includes native Geometry2D intersection calls and the GDScript per-obstacle loop. These are instrumented wall times. OS sampling and engine-internal C++ attribution are outside the collection. Use the pristine copy for frame budgets. Small native calls approach the clock's granularity, and high-frequency hooks inflate the enclosing time.
- **Cache and invalidation** use endpoint hits divided by hits plus misses, and clearance hits divided by hits plus misses for nonzero requests. Zero clearance bypasses the clearance cache. Root obstacle revision deltas come from battle state. Footprint addition calls also count copies built for clearance or breach checks. `revision_repath` counts revision-triggered executions of `_route_to` on a previously initialized unit route. Local engagement and strategic planning can issue additional path queries, visible in profiler totals.

The baseline contains the existing cached obstacle corners, endpoint links, and combat cells from `eca5e84`. Later destruction-specific changes can use these same seeded events and compare the event tick, following tick, revisions and rebuild counts against the pinned baseline.

## Results

### Headless frame times

Each cell is P50 / P95 / P99 / worst in milliseconds. The footprint and unit counts are at case start.

| Footprints / units | Cold orders | Warm orders | Retained orders | Build a wall | Destroy one wall | Destroy three structures |
|---|---:|---:|---:|---:|---:|---:|
| 20 / 12 | 295.65 / 295.65 / 295.65 / 295.65 | 2.04 / 2.04 / 2.04 / 2.04 | 0.55 / 0.58 / 0.89 / 0.89 | 1.40 / 1.53 / 582.59 / 582.59 | 1.37 / 3.02 / 766.52 / 766.52 | 1.39 / 2.56 / 569.21 / 569.21 |
| 20 / 48 | 870.74 / 870.74 / 870.74 / 870.74 | 16.56 / 16.56 / 16.56 / 16.56 | 3.96 / 4.31 / 4.63 / 4.63 | 3.98 / 4.25 / 1,165.49 / 1,165.49 | 1.58 / 5.36 / 589.91 / 589.91 | 1.53 / 2.45 / 254.08 / 254.08 |
| 40 / 12 | 3,303.08 / 3,303.08 / 3,303.08 / 3,303.08 | 2.97 / 2.97 / 2.97 / 2.97 | 0.62 / 0.66 / 0.94 / 0.94 | 0.63 / 0.85 / 3,672.70 / 3,672.70 | 1.57 / 1.91 / 2,972.05 / 2,972.05 | 0.57 / 3.70 / 3,578.11 / 3,578.11 |
| 40 / 48 | 3,839.90 / 3,839.90 / 3,839.90 / 3,839.90 | 23.76 / 23.76 / 23.76 / 23.76 | 4.11 / 4.21 / 4.78 / 4.78 | 4.14 / 4.42 / 5,098.35 / 5,098.35 | 4.11 / 6.37 / 4,177.05 / 4,177.05 | 1.58 / 6.44 / 2,715.88 / 2,715.88 |
| 60 / 12 | 7,891.74 / 7,891.74 / 7,891.74 / 7,891.74 | 3.52 / 3.52 / 3.52 / 3.52 | 0.68 / 0.84 / 1.02 / 1.02 | 1.72 / 1.87 / 9,729.95 / 9,729.95 | 1.73 / 4.88 / 7,717.64 / 7,717.64 | 1.63 / 4.73 / 5,850.75 / 5,850.75 |
| 60 / 48 | 7,498.50 / 7,498.50 / 7,498.50 / 7,498.50 | 28.52 / 28.52 / 28.52 / 28.52 | 4.28 / 4.39 / 5.16 / 5.16 | 4.32 / 4.49 / 8,776.15 / 8,776.15 | 1.71 / 7.46 / 7,039.82 / 7,039.82 | 1.66 / 3.60 / 7,895.00 / 7,895.00 |

In the local engagement phase, 17 active footprints remained. The 12-unit fight measured 55.46 / 140.52 / 141.18 / 141.18 ms. The 48-unit fight measured 627.73 / 2,124.33 / 2,280.45 / 2,280.45 ms across 30 frames each.

The following event work times show where the stall lands. The first number is the mutation tick and the second is the following tick, in milliseconds.

| Footprints / units | Build a wall | Destroy one wall | Destroy three structures |
|---|---:|---:|---:|
| 20 / 48 | 1,165.27 / 3.95 | 5.06 / 589.77 | 2.32 / 253.94 |
| 60 / 48 | 8,775.75 / 4.31 | 7.23 / 7,039.68 | 3.42 / 7,894.71 |

[Raw headless frame and work samples](data/matrix-baseline.jsonl)

### Profiler attribution

The ranking below reflects impact on the slowest headless frames and sustained combat. All per-function times come from the scoped probe run.

1. **Graph construction and rebuild visibility.** In the 60-footprint, 48-unit cold burst, three rebuilds consumed 10.51 s inclusive. Their 83,667 visibility calls consumed 6.99 s. Native AStar2D graph API calls accounted for 0.56 s of the rebuilds, leaving about 9.95 s in the surrounding GDScript, geometry, and probe overhead. The same burst at 20 footprints checked 9,246 corner pairs. The 12-unit and 48-unit bursts at 60 footprints both checked 83,667 pairs. The obstacle layout and clearance groups determine this work once their graphs are touched.
2. **Endpoint visibility during repeated route queries.** In the 48-unit engagement, 13,157 path requests ran without a rebuild. Endpoint visibility consumed 39.44 s across the 30 frames, including 22.09 s in its line checks and 2.42 s in native corner-ID and position reads. A 73% endpoint hit rate still left 6,453 misses. The 12-unit engagement made 1,020 path requests and spent 9.24 s in endpoint visibility. These cases use the same 17 active footprints. Warm orders hit 100% of endpoint links in all six cases and still pay to construct temporary endpoints and run the path search.
3. **Native API work to attach and detach route endpoints.** The 48-unit engagement spent 3.91 s on native API calls under `path()` to manage the temporary endpoints and edges. The 11,974 native searches consumed 0.39 s. Preparing adjacency for the native solver is a better candidate for this workload than replacing its search. Non-navigation enemy candidate gathering took 0.10 s in the same window, and local engagement's exclusive time was 0.70 s.

Global invalidation is the trigger that makes the rebuild cost recur. The 48-unit cases repathed all 48 retained orders after each mutation, even after removals that left routes available. The 60-footprint events reopened three clearance graphs per mutation window. Three batched removals advanced the revision three times within one tick and still produced only three downstream rebuilds. In these fixtures the footprint bookkeeping fits in the mutation tick for removals, while the following navigation tick contains the stall. Construction triggers the stall on its own tick because the added footprint is already visible to movement planning. The number of removed footprints alone does not predict stall size.

Selected 48-unit phases are below. All elapsed values are inclusive milliseconds over the phase. Native rebuild time is part of rebuild time. Native route setup counts endpoint attachment and removal plus the small native lookup for temporary point IDs. Native corner reads are part of endpoint visibility. Cache columns show hits / lookups.

| Footprints | Phase | Rebuild ms (calls) | Graph visibility ms (calls) | Endpoint visibility ms (calls) | Native rebuild / route setup / search ms | Paths | Endpoint hits | Clearance hits (ms in with_clearance) | Revision repaths |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 20 | Cold orders | 1,295.19 (3) | 637.34 (9,246) | 525.09 (40) | 117.59 / 21.20 / 2.57 | 48 | 0/40 | 32/32 (1.49) | 0 |
| 20 | Warm orders | 0.00 (0) | 0.00 (0) | 1.06 (40) | 0.00 / 21.58 / 2.72 | 48 | 40/40 | 32/32 (1.53) | 0 |
| 20 | Engagement | 0.00 (0) | 0.00 (0) | 39,440.73 (23,948) | 0.00 / 3,912.57 / 386.06 | 13,157 | 17,495/23,948 | 6,341/6,341 (128.58) | 0 |
| 40 | Cold orders | 2,910.52 (3) | 1,797.44 (37,686) | 537.01 (40) | 180.81 / 10.80 / 1.52 | 48 | 0/40 | 32/32 (0.56) | 0 |
| 60 | Cold orders | 10,510.00 (3) | 6,985.39 (83,667) | 911.92 (40) | 555.40 / 12.02 / 1.71 | 48 | 0/40 | 32/32 (0.59) | 0 |
| 60 | Warm orders | 0.00 (0) | 0.00 (0) | 0.39 (40) | 0.00 / 11.64 / 1.49 | 48 | 40/40 | 32/32 (0.53) | 0 |
| 60 | Build a wall | 16,090.28 (3) | 10,771.79 (86,525) | 2,322.00 (88) | 831.29 / 40.63 / 4.06 | 48 | 36/88 | 30/32 (9.12) | 48 |
| 60 | Destroy one wall | 14,215.75 (3) | 9,497.59 (83,901) | 1,267.29 (62) | 741.31 / 34.27 / 2.63 | 48 | 36/62 | 30/32 (9.18) | 48 |
| 60 | Destroy three structures | 10,385.20 (3) | 6,988.35 (77,407) | 757.55 (62) | 534.70 / 16.81 / 1.26 | 48 | 36/62 | 30/32 (11.37) | 48 |

Across all 38 phases, the probes recorded 140.94 s in rebuilds and 63.30 s in endpoint visibility. Native API boundaries accounted for 8.08 s during construction, 8.49 s in endpoint lookup and setup outside construction, and 0.48 s inside the search call. These totals reflect the phase lengths and probe overhead.

[Raw profiler counters and per-frame samples](data/matrix-probes.jsonl)

### Normal match and regional ownership

The opening match produced one combat unit after starting with four scouts. The headless probe recorded two CPU decisions with 11.75 ms total and a 9.61 ms worst call. Two direct paths took 0.34 ms total, and no visibility graph was built. Normal headless frame P50/P95/P99/worst was 3.80 / 4.59 / 5.60 / 13.18 ms. The rendered normal run had the same ending unit state, 120 draw calls in its final frame and 4.01 ms P95 synchronous match work. The much longer rendered frame times include software rendering, presentation and other engine work outside the timed update. Rendering and presentation were measured together.

The outpost case started with the same four scouts and four footprints. Claim completion added one footprint, the purchase added three wall segments, and outpost destruction removed four footprints in the same tick by destroying the outpost and deactivating the walls. This quiet case made no route requests. The movement matrix isolates the cost of mutations when active orders must repath.

| Match phase | Footprints | Units | Headless P50 / P95 / P99 / worst (ms) | Desktop P50 / P95 / P99 / worst (ms) |
|---|---:|---:|---:|---:|
| Normal match | 4 → 5 | 4 → 5 | 3.80 / 4.59 / 5.60 / 13.18 | 556.36 / 605.27 / 699.32 / 1,274.57 |
| Claim | 4 → 5 | 4 → 4 | 3.71 / 4.61 / 9.31 / 9.31 | 550.98 / 599.36 / 1,171.12 / 1,171.12 |
| Wall purchase | 5 → 8 | 4 → 4 | 1.66 / 2.82 / 5.71 / 5.71 | 559.75 / 611.84 / 751.30 / 751.30 |
| Outpost destruction | 8 → 4 | 4 → 4 | 1.66 / 1.91 / 3.61 / 3.61 | 554.99 / 599.63 / 607.48 / 607.48 |

[Raw headless match frame and work samples](data/match-baseline.jsonl) · [Raw headless match profiler counters](data/match-probes.jsonl) · [Raw normal desktop sample](data/desktop-normal.jsonl) · [Raw ownership desktop samples](data/desktop-ownership.jsonl)

The raw desktop normal row comes from the completed opening window before the first ownership fixture paused for claim discovery. Ownership timings come from the focused rerun with discovery disconnected. The matrix baseline emitted all 38 phase rows and its completion marker before a debug resource-leak diagnostic at shutdown. The harness now releases its probe instance at shutdown. A short teardown rerun and exact phase-state comparison retained the original timing samples without resampling the measured matrix.

## Correctness invariants

- **Obstacle addition and removal are asymmetric.** Addition can invalidate a previously safe segment and can overlap a unit that needs to walk out. Removal can reveal a shorter path or make a blocked order reachable. Safety checks for additions and route-quality/reachability checks for removals both matter. A shared revision currently dirties both equally, and the first affected query pays lazy rebuilding.
- **Preserve clearance and safe paths.** Maintain distinct expansion of footprints and shrinking of bounds for each radius, including the scout's 0.22 clearance in the match. Verify rotated wall corners, endpoints, and segment validity. Preserve the existing exit-from-footprint behavior.
- **Preserve deterministic fixed-step combat.** Route changes must use the same order of fixed-step snapshots, movement, attack resolution and cleanup. A delayed result would have to preserve when an order can move, attack or breach. Use stable tie-breaking for equivalent targets and routes where needed.
- **Preserve faction parity.** Both factions use the same navigation, commands, and movement rules. Keep ownership-driven deactivation, destructibility and unit clearance symmetric. CPU strategy chooses actions through existing economic and placement rules.

## Follow-up hypotheses and thresholds

1. **Use a spatial broad phase for visibility checks.** Keep native `AStar2D` for the solver while testing a deterministic lookup of intersecting footprint bounds. Broad-phase candidate order must remain stable where it can affect route selection. On this host, target at least a 75% reduction in measured graph visibility time in the 60-footprint, 48-unit cold burst. For that case, cap uninstrumented cold-order work at 1.88 s as a first milestone, down from 7.50 s.
2. **Scope invalidation by change type and measure both ticks.** Test whether a newly added footprint intersects retained routes and keep removal from forcing needless immediate replans on still-passable routes. Include explicit retests of shorter routes and newly opened blocked orders. Batch revision handling for simultaneous or ownership-driven footprint changes only if the fixed-step semantics permit it. Target a 75% reduction in the larger of the event tick and following tick in each 60-footprint, 48-unit mutation scenario. This gives provisional caps of 2.20 s for construction, 1.76 s for single destruction and 1.98 s for batch destruction. Then work toward a worst-frame budget of 16.67 ms on the target hardware.
3. **Reuse safe engagement work and benchmark endpoint setup.** Test bounded reuse of line-of-sight and local routes across stable targets and nearby endpoints. Quantized or reused routes must pass a clearance check before use. Aim for at most 6,579 path calls across the 48-unit engagement window and a headless frame P95 at or below 1,062 ms on this host, half the measured 2,124 ms. Keep the 60-footprint, 48-unit retained-order P95 at or below 5 ms and bring its warm 48-order burst below 16.67 ms.

Keep native `AStar2D` for the first follow-up because visibility and route preparation have the largest measured costs. A spatial grid used as a lookup for footprint bounds is a smaller experiment than replacing navigation with a traversable grid. Compare a traversable grid or polygon/navmesh only if this graph still misses the budget after those experiments. The comparison should cover rotated walls, obstacle additions and removals, multiple clearances, route quality and deterministic ties. Shared flow fields are a candidate for armies with a common goal and stable geometry. This benchmark includes changing engagement destinations and clearance groups that would require multiple fields. Treat all three alternatives as hypotheses until profiled on the same scenarios.
