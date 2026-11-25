# First match playtest

The first playable match was winnable with the rules in commit `a2a4dcc`. The shortest sampled win took 45.18 seconds and the longest took 51.27 seconds. All nine active matches ended before the proposed two-minute lower bound.

## Timing and winner tendencies

The playtest loaded the normal match scene on Godot 4.6.3, restarted for each run, clicked the actual HUD buttons through viewport input, and advanced the unmodified match in 1/60-second increments. Each active run bought the second barracks and production upgrade at their first enabled frame, at 10.02 and 30.02 seconds respectively. Match times come from the battle clock at base destruction.

| First build (s) | Outcome | Match time (s) | Final HP (player / CPU) |
| ---: | --- | ---: | ---: |
| 0.00 | Victory | 49.02 | 80 / 0 |
| 0.50 | Victory | 45.18 | 80 / 0 |
| 1.00 | Defeat | 46.47 | 0 / 80 |
| 1.50 | Victory | 48.55 | 80 / 0 |
| 2.00 | Victory | 51.27 | 80 / 0 |
| 2.50 | Victory | 46.55 | 80 / 0 |
| 3.00 | Victory | 46.52 | 80 / 0 |
| 5.00 | Victory | 46.60 | 80 / 0 |
| 10.00 | Victory | 45.50 | 77 / 0 |
| Idle | Defeat | 23.55 | 0 / 80 |

Eight of the nine sampled active openings won. The 1.00-second opening lost despite the same follow-up purchase timings as the 0.50- and 1.50-second wins. In nine of ten runs, the winning base finished at full health. This timing sweep measures selected openings against a deterministic CPU. A follow-up sweep can vary the second build and upgrade timings independently and record the first base hit alongside the winner and match duration. That would show whether longer matches are also less sensitive to small purchase delays. Balance values and CPU purchase priorities remain open for the project owner.

## Export verification

### Windows x86-64

The release export produced `builds/first-match/windows-x86_64.zip` containing `game.exe` and `game.pck`. The archive passed integrity verification, the executable was identified as x86-64 PE32+, and the exported pack started in headless Godot on Linux.

Windows runtime acceptance is pending because the build host runs ARM64 Linux. On Windows, extract both files together, launch `game.exe`, and check the six-region map and both bases. Click Build after Restart, build again when the button enables, and buy Upgrade when it enables. Watch the CPU place barracks and both sides send units into combat. After the outcome, click Restart and confirm that both bases return to 80 HP, player barracks reset to 0/2, and both sides can produce units in the replay.

### Single-threaded Web

The release export is in `builds/first-match/web/`. Chromium 156 loaded it from a loopback HTTP server with cross-origin isolation disabled. The rendered six-region map, base HP, economy labels, and controls were readable at 1280×800, 1366×768, and 1920×1080. On the software-rendered ARM64 host, the browser simulation advanced more slowly than real time. The timing table uses simulation time.

The browser playthrough bought both player barracks and the production upgrade through the HUD. The CPU built two barracks and both sides fought in the corridor. The CPU base reached 0 HP, disappeared, and the HUD showed Victory. Restart restored both bases to 80 HP and cleared the units and barracks. A new player purchase and renewed CPU production confirmed the replay was running.
