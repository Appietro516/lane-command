#!/usr/bin/env bash
set -euo pipefail

godot=${GODOT:-godot}
output=${1:?Pass an absolute build output directory}
if [[ "$output" != /* || -e "$output" ]]; then
    echo "Use a new, absolute build output directory." >&2
    exit 1
fi

version=$(cat .godot-version)
if [[ ! $version =~ ^4\.[0-9]+\.[0-9]+-stable$ ]] ||
   [[ $("$godot" --version) != "${version/-/.}".official.* ]]; then
    echo "Install the official Godot $version editor and matching export templates." >&2
    exit 1
fi

python3 - <<'PY'
import configparser
from pathlib import Path

project = configparser.ConfigParser(interpolation=None, strict=False)
project.read_string("[project]\n" + Path("project.godot").read_text(encoding="utf-8-sig"))
rendering = project["rendering"] if "rendering" in project else {}
method = rendering.get("renderer/rendering_method.web", rendering.get("renderer/rendering_method"))
if method != '"gl_compatibility"':
    raise SystemExit("Web export requires the Compatibility renderer (gl_compatibility).")
application = project["application"] if "application" in project else {}
if not application.get("run/main_scene", "").strip('"'):
    raise SystemExit("Set a main scene before exporting.")
features = application.get("config/features", "")
version = Path(".godot-version").read_text().strip()
if f'"{version.rsplit(".", 1)[0]}"' not in features:
    raise SystemExit("project.godot features and .godot-version must use the same Godot major/minor.")
if '"C#"' in features or any(Path(".").glob("*.csproj")) or any(
    path.suffix == ".gdextension" and not any(part.startswith(".") for part in path.parts)
    for path in Path(".").rglob("*.gdextension")
):
    raise SystemExit("The standard single-threaded Web build does not support .NET or GDExtension.")
PY

run_godot() {
    local log
    log=$(mktemp)
    if ! "$godot" --headless --path . "$@" 2>&1 | tee "$log" ||
        grep -Eq '^[[:space:]]*(SCRIPT ERROR|ERROR):' "$log"; then
        rm -f "$log"
        echo "Godot failed during $*." >&2
        return 1
    fi
    rm -f "$log"
}

mkdir -p "$output/windows" "$output/web"
run_godot --import
run_godot --quit-after 120
run_godot --export-release "Task Runner Windows" "$output/windows/game.exe"
run_godot --export-release "Task Runner Web" "$output/web/index.html"

for file in windows/game.exe windows/game.pck web/index.html web/index.js web/index.wasm web/index.pck; do
    if [[ ! -s "$output/$file" ]]; then
        echo "Godot did not produce $file." >&2
        exit 1
    fi
done
python3 -m zipfile -c "$output/windows-x86_64.zip" "$output"/windows/*
python3 -m zipfile -t "$output/windows-x86_64.zip"
