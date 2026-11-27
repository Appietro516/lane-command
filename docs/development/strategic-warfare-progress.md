# Strategic Warfare Overhaul progress

Baseline `73fdb26` on the isolated strategic-warfare feature branch. The production scene remains `main.tscn` and uses Godot 4.6.3 Compatibility.

## Visibility and last-known intelligence

- Faction-separated, sparse byte masks share navigation's map bounds and grid partition. Source coverage buckets update independently of native navigation. The 5 Hz mask update samples centers on a 16-by-16 grid per chunk. Live targeting and inspection use current radius queries.
- The map uses one R8 texture overlay. Starting markers and remembered structure labels have separate state. Combat presentation, selection and CPU observations share the authoritative visibility check.
- The implementation commit is recorded as "Add faction visibility and fog presentation" in Git history.

Next action is reconnaissance buildings and periodic contacts, followed by regional and neutral objectives.

Visibility milestone commit `074caa9`. Godot import, production scene smoke, and the visibility test passed.

## Reconnaissance

- Watchtower, radar and counterintelligence use normal placement and slots. One shared scan feeds all faction pulses due in a step. Contacts carry copied positions and composition, age after each pulse, and expire. Decoys have no simulation entity and direct observation debunks them.
- CPU planners use live sightings for tactical decisions and radar compositions for production planning.
- Both the visibility and recon tests passed. Next action is specialized regions, landmarks, and claim pricing.

Reconnaissance milestone commit `c8c3531`.

## Regional strategy

- Seven regions is the default. Larger configurable maps remain supported. Deterministic specialties occupy 80% of neutral regions, and the default landmark limit rose from two to four. Starting regions have ordinary terrain and no default landmark.
- Fertile, mineral-rich and energy-rich regions multiply their matching producer by 1.35. Defensible regions multiply outpost and defensive structure base HP by 1.20 before faction bonuses. Active producers have full yield for the first two per type, then efficiency is `max(0.55, 1 / (1 + 0.10 × (index - 2)))`.
- Claim prices use `round(base × min(3, 1.20^extra))` with each faction's current non-ruined holdings and original territory count. Payment remains at dispatch. CPUs scout frontier sites before evaluating their current state.
- Import, focused regional and visibility tests passed. Next action is combat pacing and neutral objectives.

Regional strategy milestone commit `6075ebf`.

## Combat and siege

- Military movement is 12% slower. Production defaults to Idle with local self-defense, while explicit producer assignments and rallies continue to work. Right-clicking a visible enemy issues a focus order. A target lost in fog leaves its last observed point.
- Starting bases have 240 HP and outposts have 40 HP before modifiers, and both fire through the fortification rules. Ordinary attacks take a 0.55 multiplier against armored hubs and defenses. Heavies have a 1.85 structure multiplier and increased Food cost. Class counters are catalog values.
- Strategic combat tests passed. Next action is jungle objectives and CPU contesting.

Combat milestone commit `a369d10`.

## Neutral objectives

- Seeded neutral sites host up to four minor camps and a central stronghold. Guardians are real combat units with local engagement range and no pathing footprint. Defeat leaves a contested pickup for 30 seconds. Minor and major guardians respawn after 82 and 175 seconds.
- Pickups use nearest living unit and stable ID ties. Rewards are three-resource grants, 48-second ranged or defense boons, or a 75-second stronghold boon that increases fortified-target damage by 65%. Same-kind rewards refresh duration.
- CPUs use their sighting records and current force to consider a fight or collect a drop. The jungle test and production smoke passed. Next action is scores, bounties, missile warnings and control groups.

Neutral objectives milestone commit `8b1f23d`.

## Strength and comeback

- Faction scores refresh every three seconds and rank all factions. The 0–1000 score weights normalized military, economy, territory and defense values at 35/30/20/15 percent. The panel shows faction totals and the player's current boons.
- Comeback rewards require a sustained 36-second deficit of at least 90 points and a score no greater than 72% of the leading active rival. An exponential average and decaying peak govern eligibility. Each faction can claim up to six grants with 90 seconds between grants and one grant per objective. Ordinary grants add 22/15/12 Energy/Materials/Food. A landmark claim adds 30/22/18.
- Import and focused score, UI, restart and bounty tests passed. Next action is missile presentation and control groups.

Strength and comeback milestone commit `c5020a1`.

## Missiles and control groups

- Missile preparation lasts 60 seconds. The public warning and flashing silo marker show the source, faction and deadline. Off-screen arrows point to the source. Enemy projectile trajectories stay hidden. Original starting regions are protected, and hit hubs in other regions permanently neutralize territory. CPU retaliation priority lasts 105 seconds from the announcement.
- Control groups 1–9 support assignment, addition, recall and camera centering. A unit belongs to one group at a time. Death and restart clean up membership.
- Focused missile and group tests passed. Next action is integrated regression testing, fog benchmarks and reproducible balance simulations.

Missiles and groups milestone commit `78c6432`.

## Integration and measurement

- Fog now stores separate explored and visible row bitsets, with 12 cells per navigation-aligned chunk edge. Circle spans and sampled source buckets reduce overlapping work. Exact live radius checks use conservative inner and outer bounds with per-source checks at the boundary. Dirty work has a chunk and time budget, independent of the rendering and navigation lifecycle.
- Radar draws one instanced field of precise stale contacts. Clicking a contact shows its last recorded composition and age. Structure and region sightings are observed by the match simulation independently of texture uploads.
- CPU assaults now gather a force before advance, use siege options, and prioritize units under public retaliation. Neutral guards no longer count as invading rival armies. Camp sites give scouts room to approach regional claim points.
- Baseline validation used a separate checkout of `73fdb26`. The pre-existing multi-CPU test missed its 16.67 ms p95 threshold in both measured combat cases. Several legacy assertions expect behavior superseded by the overhaul. The existing tests are still enabled.
- Next action is to finish the benchmark matrix and balance simulations, check release artifacts on native and browser renderers, and resolve any remaining integration failures before publishing.

Bounded visibility and CPU integration milestone commit `c4ec7ea`.

## Pacing adjustment

Two completed automated pilot games reached defeat at 166.02 seconds on seed 17 and 344.85 seconds on seed 31. The 15-minute target remains a balance goal. In response, passive Energy and Materials were reduced to 2.25/s and 1.45/s. Food remains 1/s. Starting-base HP rose to 420, its defensive attack to 6 damage per 0.9 seconds, and ordinary damage against the base receives a 0.40 armor multiplier. Outpost/other defended structures retain their 0.55 multiplier. Heavy siege and individual upgrades are unchanged. Follow-up simulations and release checks use the tuned values.

The setup, camera and attack-event tests now exercise the requested default map, production cadence and targeting rules. A new five-faction integration test checks distinct intelligence, normal producer upgrades, rallies, victory and restart. Next action is to record the verification result and reconcile any remaining blockers before GitHub delivery.


Pacing and presentation milestone commit `158451651be0b2e98faa850778eebbeaa16596bd`.

## Automated balance results

The simulation script drives both the player side and the opponents through the normal CPU planner at Standard difficulty. It resolves player narrative choices with the first affordable option. This was automated simulation and there was no human playtest. Reproduce the tuned pair with `godot --headless --path . --script tests/performance/strategic_simulation.gd -- 17 1 Rectangle 1200` and `-- 31 2 Circle 1200`. The 1200-second ceiling belongs to the test harness.

| Build | Seed | Map | CPUs | First engagement | Duration | Outcome | Claims | Camp hits/kills | Stronghold pickups | Casualties | Bounties |
| --- | ---: | --- | ---: | ---: | ---: | --- | ---: | --- | ---: | ---: | ---: |
| Pilot | 17 | Rectangle | 1 | 80.47s | 166.02s | Defeat | 5 | 302/4 | 1 | 155 | 0 |
| Pilot | 31 | Circle | 2 | 22.27s | 344.85s | Defeat | 3 | 654/9 | 1 | 495 | 1 |
| Tuned | 17 | Rectangle | 1 | 94.78s | 176.08s | Victory | 4 | 437/7 | 1 | 142 | 0 |
| Tuned | 31 | Circle | 2 | 22.27s | 234.70s | Defeat | 3 | 358/5 | 1 | 230 | 0 |

### Tuned trajectories

Rows are sampled at approximately one-minute intervals and at match end. Factions appear in player, CPU 1, CPU 2 order where applicable.

| Seed | Simulated seconds | Base HP | Faction scores | Claims | Camp kills | Stronghold pickups | Casualties |
| ---: | ---: | --- | --- | ---: | ---: | ---: | ---: |
| 17 | 1.0 | 420.0/420.0 | 153/153 | 0 | 0 | 0 | 0 |
| 17 | 61.0 | 420.0/420.0 | 243/429 | 1 | 1 | 0 | 9 |
| 17 | 120.1 | 420.0/420.0 | 575/344 | 3 | 3 | 1 | 79 |
| 17 | 176.1 | 420.0/0.0 | 931/0 | 4 | 7 | 1 | 142 |
| 31 | 1.0 | 420.0/420.0/420.0 | 153/153/153 | 0 | 0 | 0 | 0 |
| 31 | 61.0 | 420.0/420.0/420.0 | 249/231/248 | 0 | 0 | 0 | 27 |
| 31 | 121.0 | 420.0/420.0/420.0 | 248/495/242 | 2 | 2 | 0 | 81 |
| 31 | 180.0 | 420.0/420.0/406.6 | 240/542/214 | 2 | 3 | 0 | 161 |
| 31 | 234.7 | 0.0/420.0/0.0 | 0/790/0 | 3 | 5 | 1 | 230 |


The winning formation on tuned seed 17 finished with 12 Heavy, 5 Infantry and 22 Ranged units plus 2 Scouts. On tuned seed 31, CPU 1 finished with 8 Heavy, 4 Infantry, 4 Raiders and 11 Ranged units plus 1 Scout. The tuner changed which faction won seed 17 and shortened seed 31. The two tuned matches averaged 205.39 seconds, so they did not validate the 15-minute balance target. The four-opponent pilot hit its wall-clock timeout. Its last sample at 541 simulated seconds showed all five bases standing, two claims, one guardian defeat and 1,048 military casualties. It showed low territorial development and high attrition. The tuned circular simulation also logged native navigation edge-merge warnings while finishing its match.

The full headless benchmark matrix is recorded in [Strategic visibility benchmarks](../performance/strategic-visibility.md). Native Compatibility screenshots confirmed that the fog overlay and the hidden CPU-start marker are both visible at overview zoom. The screenshot is available at `/tmp/lane-strategic-markers-native/capture.png` for this worktree.

## Validation and delivery status

The clean baseline `73fdb261cf4c2349bb27a52aa838e419fc5a6d46` passed 26 of 27 original scripts. `match_multiple_cpu_test.gd` already failed the fixed-step p95 budget on both representative combats, at 19.54 ms for 1v1 and 39.09 ms for 1v4 in that run.

The full overhaul run executed 36 scripts with Godot 4.6.3. It returned 16 passes, 19 failures and one timeout. All nine new feature scripts passed. Existing attack-effect, camera, native chunk navigation, destruction navigation, group orders, map shape and setup scripts also passed. The failing existing suites were buffs, building slots, claim discovery, claims, combat, CPU difficulty, CPU expansion, CPU tactics, economy, expansion, fortifications, landmarks, military production, multiple CPU opponents, narrative, outposts, provenance, startup and the unit roster. CPU strategy hit its time budget in the full run and failed assertions on an isolated retry. A number of assertions still prescribe older opening health, production timings, omniscient landmark inspection, or Seek Nearest production. These failures still block release verification.

Godot headless import, direct `main.tscn` smoke, six CI build preflight checks, and native Compatibility capture passed. Native stress comparisons timed out at 160 seconds per mode, so the benchmark table reports headless CPU-side presentation and upload times only. The Windows and Web production exports are in `/tmp/lane-strategic-final-export` with tested ZIPs and SHA-256 checksums. The host has no Windows execution environment. Chromium initialized the single-threaded Godot WebAssembly engine and WebGL 2, displayed Game Setup, and entered a playable match. The local-file smoke logged a service-worker security error specific to the file origin. The HTTP try reached the loopback server with curl, while Chromium stayed on an empty document, so HTTP-served browser startup remains unverified on this host. The match screen is at `/tmp/lane-production-check/final-web-match.png`. Publication remains gated on the regression suites, performance and match pacing.

Remote master was read directly as `73fdb261cf4c2349bb27a52aa838e419fc5a6d46` and its [Godot builds workflow](https://github.com/Appietro516/lane-command/actions/runs/45788539353) completed successfully. The implementation is on the isolated feature branch. The next checkpoint is to resolve the listed regression suites, repeat paired profiling on an idle host and tune with further reproducible matches before publication.
