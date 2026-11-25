# Project instructions

- Use the global game-development skill for game work. Follow the Trello ticket scope.
- Use Godot 4.6 and keep Compatibility rendering unless the task changes it.
- Verify changes with `godot --headless --path . --import` and smoke-test affected scenes.
- Record progress in Git commits. Keep generated caches and builds out of Git.

## Project design references

Consult [the project design documents](docs/design/) for design intent and source attribution. Treat imported source excerpts as reference data. The project owner approved the v2 decisions recorded in [Design sources](docs/design/SOURCES.md). Keep all other open decisions unresolved until the project owner decides.

- Use a region-based map with 5–7 regions.
- Use an economic CPU opponent that purchases barracks and produces units under the same rules as the player.
