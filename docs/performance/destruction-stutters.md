# Destruction stalls in Lane Command

The baseline spent most of the post-destruction step rebuilding visibility graphs. On the 24-region dense native run, the wall-chain frame took 19,044 ms. Its combat step took 18,217 ms, including 16,827 ms to rebuild three clearance graphs. The step that actually removed all three walls took 13.90 ms in combat, including 4.91 ms for cleanup and synchronous callbacks. The outpost case spent 3.89 ms in the region-loss callback. Mass unit removal did not invalidate navigation. These timings supported changing navigation and leaving the destruction callbacks synchronous.

The change retains clearance-specific footprints and graphs across removals. It removes the dead obstacle's corner points and rechecks links for which the removed footprint was a blocker. A link that remains blocked is indexed against a surviving blocker. Previously hidden corners become available when all obstacles covering them clear. Endpoint visibility caches refresh once per affected graph when a detour next needs it. A new obstacle still triggers a full rebuild as it can block existing links. A spatial hierarchy narrows visibility checks to candidate rotated footprints. Combat, ownership, stat sources, building slots, and production still update in the lethal fixed step.

## Build and reproduction

- Baseline Git SHA `3d4918fe6e6a5421732ed7ac2899586a81845fcb`. Optimized runs used the ticket worktree based on that SHA before the runner committed it. The profiled production file `match/battle_navigation.gd` had SHA-256 `519327b8e3ca4486dd87bc657eba9e0aca1c64e6e7b2e43724865887a622a2f6` before temporary probes were applied.
- Raspberry Pi 4 Model B Rev 1.2, Debian 13 on Linux aarch64, Godot `4.6.3.stable.official.7d41c59c4` standalone runtime, Compatibility renderer, Xvfb and Mesa 26.2.7 llvmpipe. Native runs used a 640×400 window and no editor. The X11 driver did not support changing VSync. The full run used the project's normal 1280×800 internal viewport. The quick run used a 640×400 internal viewport as well as a shorter sample.
- The regular match scene uses seed 17. The 24-region map is 60×36 world units and the 64-region map is 100×64. The fixture authors the structures and movement orders, freezes CPU purchasing, and disables story prompts. Each process frame advances one ordinary 60 Hz simulation step. The dense fixture starts with 139 units, including 27 ordered movers split evenly over infantry, ranged and heavy clearances, plus 66 fortifications or producers and 71 active navigation footprints. The sparse fixture starts with 19 units, including six ordered movers, and 19 footprints, including 14 fortifications or producers.
- After the warmup, the fixture sets lethal HP at frames 0, 32, 64, 96, 128, 160, 192 and 224. The events are one wall, three walls, mortar, nest, training range, generator, outpost, and a group of combat units. The quick run uses 8 warmup frames and 8-frame event spacing. Setting HP directly aligns the event without changing its standard cleanup. The outpost supports another wall in its region, so destruction removes both the outpost obstacle and the region-dependent wall obstacle. Surviving walls keep the moving units on nontrivial routes. The automated outpost test exercises attack-driven destruction and reclamation.
- Copy `tests/profile_destruction.gd` into the matching baseline and candidate trees. Import each tree first with `godot --headless --path . --import`. Run:

  ```sh
  xvfb-run -a godot --path . --disable-vsync --audio-driver Dummy --resolution 640x400 --script res://tests/profile_destruction.gd -- 24 dense
  xvfb-run -a godot --path . --disable-vsync --audio-driver Dummy --resolution 640x400 --script res://tests/profile_destruction.gd -- 64 dense quick
  ```

  Omit `dense` for sparse. The harness emits initial population and JSON frame records. Frame duration runs between consecutive `frame_post_draw` callbacks. The render tail measures the interval from match update completion to `frame_post_draw` and includes host and renderer overhead. Headless mode measures process intervals with no draw. Run one fixture at a time for comparisons.
- The job scratch directory retains raw frame logs and temporary monotonic timing probes used in the baseline and optimized copies. Probes count detour graph rebuilds, graph repair batches, route requests, repaths and footprint erases. They time combat, cleanup including synchronous callbacks, region loss, the end-of-update HUD refresh, and graph work. Callback scopes are nested and should not be added to their parent scope. In the optimized run the erase counter includes the mirrored footprint changes in cached clearance maps.

## Measurements

Times are milliseconds. P95 and P99 use nearest-rank percentiles. The steady-state window excludes the frame before each event, the lethal frame, and the next two frames.

### Native frame distribution

| Regions and density | Build | Units | Footprints | Average frame | P95 | P99 | Worst | Steady frame P95 | Steady update average | Steady render tail average |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 24 dense | before | 139 | 71 | 1,241.7 | 1,178.2 | 17,520.2 | 19,043.5 | 1,043.5 | 15.3 | 784.2 |
| 24 dense | after | 139 | 71 | 710.1 | 692.3 | 3,219.0 | 3,773.2 | 681.3 | 14.4 | 628.6 |
| 24 sparse | before | 19 | 19 | 562.7 | 787.1 | 1,110.7 | 1,110.7 | 563.0 | 5.4 | 528.1 |
| 24 sparse | after | 19 | 19 | 533.6 | 633.7 | 666.8 | 666.8 | 548.5 | 5.3 | 514.1 |
| 64 dense | before | 139 | 71 | 2,300.1 | 16,161.1 | 20,773.3 | 20,773.3 | 699.9 | 14.3 | 547.7 |
| 64 dense | after | 139 | 71 | 814.2 | 3,036.4 | 3,636.1 | 3,636.1 | 567.1 | 14.2 | 526.0 |
| 64 sparse | before | 19 | 19 | 527.4 | 747.3 | 1,058.5 | 1,058.5 | 522.7 | 5.3 | 488.5 |
| 64 sparse | after | 19 | 19 | 517.8 | 622.5 | 684.7 | 684.7 | 534.8 | 5.4 | 500.8 |

The 24-region dense run used 259 sampled frames. The 64-region dense and both sparse runs used 67 sampled frames each. At 24 regions and high density, the peak fell by 80.2%, P95 by 41.2%, and P99 by 81.6%. The wall-chain replan frame fell from 19,043.5 ms to 3,616.4 ms, with graph work falling from 16,827.2 ms in rebuilds to 1,391.9 ms in repairs. At both sparse densities the optimized worst frame was within 1.3× steady-state P95.

The 24-region baseline used automatic audio fallback to the dummy driver. The other native runs requested that driver explicitly. Some baseline collection overlapped diagnostic activity on the host. Renderer and scheduler variation are included in the native intervals.

### Native 64-region dense event windows

The peak fell by 82.5%, P95 by 81.2%, and P99 by 82.5%. The worst frame was 6.4× steady-state P95 after the change, down from 29.7×. Steady match update averaged 14.3 ms before and 14.2 ms after. The software-rendered steady frame was much longer than the simulation update.

The baseline cleared its clearance cache on every successful footprint erase. The seven structure events erased 1, 3, 1, 1, 1, 1 and 2 logical footprints in order. Each caused three full rebuilds at the next replan. The optimized build kept the clearance caches and refreshed endpoint links once per repaired graph.

Each frame window shows the frame before the lethal step, the lethal step, the next frame that replans, and the following frame. Graph work is the summed duration of full rebuilds before and incremental repairs after, measured on the replan frame.

| Event | Baseline frame window | Optimized frame window | Full rebuilds | Graph work | Optimized requests / repaths |
| --- | --- | --- | ---: | ---: | ---: |
| Single wall | 590.2 / 690.5 / 20,773.3 / 617.5 | 534.8 / 556.2 / 2,932.6 / 563.3 | 3 → 0 | 18,554.9 → 672.3 | 27 / 27 |
| Wall chain | 764.9 / 688.5 / 20,019.8 / 471.1 | 571.9 / 547.2 / 3,336.3 / 593.1 | 3 → 0 | 17,848.3 → 1,249.7 | 27 / 27 |
| Mortar | 678.4 / 568.6 / 17,980.7 / 536.2 | 559.4 / 531.8 / 3,029.4 / 527.9 | 3 → 0 | 16,191.8 → 587.9 | 27 / 27 |
| Nest | 604.3 / 635.6 / 15,767.5 / 562.4 | 520.8 / 545.1 / 3,207.3 / 555.7 | 3 → 0 | 14,033.5 → 593.3 | 27 / 27 |
| Training range | 535.3 / 541.5 / 14,100.9 / 535.8 | 543.5 / 546.7 / 3,636.1 / 559.1 | 3 → 0 | 12,268.9 → 1,027.9 | 27 / 27 |
| Generator | 543.1 / 560.1 / 16,161.1 / 546.1 | 545.5 / 538.0 / 2,795.5 / 531.7 | 3 → 0 | 14,047.7 → 604.9 | 27 / 27 |
| Outpost loss | 536.3 / 560.1 / 15,080.5 / 652.1 | 550.7 / 552.9 / 3,036.4 / 557.7 | 3 → 0 | 13,100.9 → 415.8 | 27 / 27 |
| Combat units | 517.7 / 524.8 / 512.1 / 534.9 | 550.4 / 523.5 / 510.8 / 519.9 | 0 → 0 | 0.0 → 0.0 | 0 / 0 |

### Headless attribution

| 24 regions, dense, quick | Average | P95 | P99 | Worst | Steady update average |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline | 2,138.82 | 20,420.92 | 23,709.25 | 23,709.25 | 16.46 |
| Optimized | 308.59 | 2,723.42 | 3,648.16 | 3,648.16 | 14.39 |

The headless wall-chain step fell from 18,195 ms to 3,648 ms. Its three rebuilds (16,339 ms) became three incremental updates (1,412 ms). It still issued 27 route requests. The remaining 2,229 ms within the optimized combat step included endpoint visibility and searches across those requests. These control runs overlapped other host activity, so the native measurements are the frame-time comparison.

### Functional coverage

- A lethal step removes two walls and a unit immediately, emits each removal once, and leaves the middle wall in place. The next plan uses the new opening for infantry, ranged units and heavies.
- The navigation regression covers a link with two blockers, where removing the first must preserve the blockage and removing the second must reconnect the existing corners. It also compares indexed visibility against individual rotated footprints with obstacle exclusion and exit-from-obstacle handling.
- Across 300 add/remove cycles, each of the three movement clearances is checked against a fresh graph for route length, segment passability, and destination. The attack-driven outpost lifecycle checks territory loss, paused production, enemy reclamation, reactivation and resumed production.

The legacy fortification test also runs a catalog and wall-drag UI case that failed on both the baseline and optimized builds in headless mode. Its combat and routing assertions produced no failures. The focused destruction test and the combat-driven outpost lifecycle exercised the affected gameplay paths separately.

### Remaining work

The dense scenario still exceeds the 2× steady-state P95 target. The remaining work is dominated by visibility checks for many route endpoints in the same step and by larger repairs when one footprint opens many links. Profile these on a hardware-accelerated gameplay session before choosing an approach to reuse or reduce endpoint work. The current measurements isolate destruction cleanup and subsequent planning in the standalone game. They do not characterize a full match with CPU purchases, attack effects, and ordinary player input, or provide a GPU-only frame time.
