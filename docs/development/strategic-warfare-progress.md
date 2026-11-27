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
