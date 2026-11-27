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
