# Strategic visibility benchmarks

Godot 4.6.3 Compatibility was used for 36 paired headless cases. Each case advances 120 fixed steps in the production match scene on a seeded 36-region world. The rectangular world is 108 × 72 and the circular world has diameter 100. The harness injects ordinary military actors above the live production cap when needed. Both sides of each pair exercise the same movement orders, watchtower changes, simultaneous per-faction radar pulses, public missile warnings, and a scripted removal of half the injected military actors.

Frame results are elapsed CPU-side harness timings that include battle stepping, scene transform and visibility updates, and scheduled queries. GPU execution is outside the headless timings. Presentation columns use the measured CPU portion of the same frame and upload time is cumulative across 120 frames. The host was running automated match and validation jobs, so wall-clock tails include scheduling noise. Memory is Godot's static allocator delta, with resources warmed by earlier cases. The first pair per map includes a cold-to-warm asset transition.

Reproduce the pairs with these commands.

```sh
godot --headless --path . --script tests/performance/fog_benchmark.gd -- matrix Rectangle
godot --headless --path . --script tests/performance/fog_benchmark.gd -- matrix Circle
```

| Map | CPU | Units | Off P50/P95/P99 ms | On P50/P95/P99 ms | Off/on presentation P95 ms | Mean/max fog ms | Chunks | Source samples | Upload ms total | On minus off MiB | Off/on AI query ms | Nav revision |
| --- | ---: | ---: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | --- | ---: |
| Rectangle | 1 | 100 | 22.04/44.85/65.14 | 47.87/89.46/140.57 | 18.33/40.96 | 6.92/28.95 | 315 | 7597 | 76.16 | -6.95 | 3.22/5.71 | 15 |
| Rectangle | 1 | 250 | 71.38/129.66/167.76 | 94.43/166.15/213.47 | 46.36/59.07 | 7.36/22.94 | 261 | 10648 | 59.78 | +0.72 | 9.00/11.10 | 15 |
| Rectangle | 1 | 500 | 84.26/175.30/214.02 | 119.89/210.59/375.12 | 52.18/76.06 | 6.00/29.86 | 247 | 13417 | 29.93 | +1.14 | 14.86/17.52 | 15 |
| Rectangle | 2 | 100 | 21.98/41.21/72.27 | 34.05/50.74/72.29 | 13.08/20.90 | 3.97/13.92 | 386 | 6475 | 28.88 | +0.59 | 2.81/4.02 | 20 |
| Rectangle | 2 | 250 | 43.34/76.34/104.81 | 64.45/111.22/145.22 | 20.99/34.75 | 4.52/10.69 | 337 | 9508 | 46.29 | +1.12 | 6.76/8.20 | 20 |
| Rectangle | 2 | 500 | 44.46/109.54/191.08 | 63.76/139.22/256.77 | 33.87/53.64 | 3.37/13.89 | 301 | 12092 | 30.68 | +1.84 | 9.35/12.73 | 20 |
| Rectangle | 4 | 100 | 15.55/30.56/50.13 | 30.57/60.29/78.88 | 10.54/21.41 | 2.88/9.14 | 587 | 6487 | 32.59 | +0.69 | 2.06/3.56 | 30 |
| Rectangle | 4 | 250 | 25.12/74.70/124.22 | 71.64/135.24/191.99 | 19.31/40.11 | 4.01/11.24 | 417 | 7883 | 42.20 | +1.27 | 4.94/10.21 | 30 |
| Rectangle | 4 | 500 | 83.65/165.98/243.59 | 130.13/278.79/415.62 | 41.07/74.53 | 5.16/22.76 | 354 | 10181 | 35.73 | +2.06 | 12.94/23.48 | 30 |
| Circle | 1 | 100 | 35.48/61.08/77.44 | 55.79/90.78/117.86 | 24.19/36.45 | 6.87/24.99 | 370 | 8600 | 84.18 | -6.81 | 4.13/6.30 | 15 |
| Circle | 1 | 250 | 81.48/158.35/234.10 | 97.50/184.21/211.03 | 54.07/57.05 | 7.29/18.84 | 280 | 11348 | 26.34 | +0.88 | 11.88/11.31 | 15 |
| Circle | 1 | 500 | 99.72/148.42/245.91 | 110.21/220.28/362.41 | 53.69/71.48 | 5.47/19.41 | 235 | 13605 | 24.09 | +1.34 | 17.28/17.18 | 15 |
| Circle | 2 | 100 | 17.98/32.52/45.75 | 19.98/43.82/69.70 | 10.54/16.99 | 2.73/10.44 | 551 | 8646 | 16.38 | +0.67 | 2.48/2.63 | 20 |
| Circle | 2 | 250 | 27.73/65.50/99.24 | 48.51/95.28/141.70 | 19.50/34.70 | 3.72/10.97 | 397 | 10854 | 24.74 | +1.27 | 5.47/6.19 | 20 |
| Circle | 2 | 500 | 43.34/103.68/193.85 | 62.26/132.62/268.84 | 33.82/49.18 | 3.29/10.62 | 307 | 12700 | 16.22 | +2.08 | 9.68/11.41 | 20 |
| Circle | 4 | 100 | 15.52/34.45/62.34 | 38.60/72.07/89.76 | 10.36/26.25 | 3.73/9.58 | 645 | 6432 | 45.29 | +0.80 | 2.38/4.25 | 30 |
| Circle | 4 | 250 | 44.35/84.50/185.34 | 72.79/155.75/203.88 | 25.18/44.99 | 3.75/10.63 | 458 | 8444 | 53.29 | +1.49 | 6.81/10.01 | 30 |
| Circle | 4 | 500 | 83.26/163.88/241.81 | 121.96/212.41/337.48 | 40.07/76.65 | 4.11/17.25 | 374 | 10327 | 40.66 | +2.33 | 13.94/16.93 | 30 |

## Findings

- Navigation revisions and accepted movement-order counts matched in every pair. The tested routes used the normal fast path in these maps. Standalone chunk seam, clearance, stale-build and destruction-navigation tests supply separate evidence for the native route path.
- Vision averaged 2.73–7.36 ms per scheduled or draining update. The work cap is checked between chunks. A costly chunk or host preemption can exceed the target wall-clock budget.
- Instanced radar markers removed the original per-contact label tree. In the preliminary 100-unit rectangular run, median presentation CPU time fell from 11.13 ms with individual labels to 5.07 ms with instancing, under similar host load. The final matrix used the subsequent sample-bucket and row-bitset changes.
- Fog added substantial whole-frame costs in several pairs, and the fog-disabled baseline also exceeded a 16.67 ms step in many synthetic cases. These results do not establish a 60 FPS budget or performance parity. The 500-unit cases exceed the live production cap.
