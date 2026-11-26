#!/usr/bin/env python3
"""Run the same Godot scene with pristine and optionally instrumented source."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RESOURCE = "res://tests/performance/navigation_benchmark.tscn"
PREFIX = "NAV_BENCH "
PROBE = 'var _nav_probe := Engine.get_singleton(&"LaneNavigationProbe")'

# Signatures are taken from the baseline. Fail loudly when its source changes.
NAV_METHODS = [
    ("_rebuild_graph", "", False),
    ("_visible_corners", "point, is_start, cache", True),
    ("line_clear", "start, end, ignored_obstacle, allow_exit", True),
    ("path", "start, end", True),
    ("with_clearance", "clearance", True),
    ("is_passable", "point", True),
    ("add_obstacle", "footprint, angle", True),
    ("remove_obstacle", "id", False),
    ("reachable_without_obstacle", "start, end, clearance, ignored_id", True),
]
BATTLE_METHODS = [
    ("_step_combat", "", False),
    ("_plan_turn", "unit, units, cells", True),
    ("_nearby_enemies", "units, cells, position, side, radius", True),
    ("_plan_local_engagement", "unit, units, radius, holding", True),
    ("_find_attack_route", "unit, center, obstacle, attack_range", True),
    ("_route_to", "unit, destination", False),
]


def replace_once(source, before, after):
    if source.count(before) != 1:
        raise ValueError(f"Expected one profiling anchor: {before!r}")
    return source.replace(before, after, 1)


def wrap(source, name, args, returns):
    signature = re.search(rf"^func {name}\([^)]*\)[^\n]*:\n", source, re.MULTILINE)[0]
    call = f"_probe_impl{name}({args})"
    key = f'"{name}"'
    if name == "line_clear":
        key = '"line_clear/" + _nav_probe.caller()'
    if name == "path":
        key = '"path/%.2f" % _probe_clearance'
    body = f"\tif not _nav_probe.active:\n\t\t{'return ' if returns else ''}{call}\n"
    if not returns:
        body += "\t\treturn\n"
    body += f"\t_nav_probe.begin({key})\n"
    body += f"\t{'var result := ' if returns else ''}{call}\n\t_nav_probe.end()\n"
    if returns:
        body += "\treturn result\n"
    return replace_once(source, signature, signature + body + "\n\n"
                        + signature.replace(f"func {name}(", f"func _probe_impl{name}("))


# AStar2D timings include binding overhead. The alias preserves the native
# instance and forwards the original arguments/defaults synchronously.
NATIVE_METHODS = [
    ("clear", "", "", "void"),
    ("get_point_count", "", "", "int"),
    ("add_point", "id: int, position: Vector2", "id, position", "void"),
    ("get_point_ids", "", "", "PackedInt64Array"),
    ("get_point_position", "id: int", "id", "Vector2"),
    ("connect_points", "from: int, to: int", "from, to", "void"),
    ("get_point_path", "from: int, to: int", "from, to", "PackedVector2Array"),
    ("remove_point", "id: int", "id", "void"),
]


def instrument_navigation(source):
    source = replace_once(source, "var revision := 0", PROBE + "\nvar _probe_clearance := 0.0\n\nvar revision := 0")
    anchors = [
        ("\tif clearance == 0.0:\n", '\tif clearance == 0.0:\n\t\t_nav_probe.count("clearance_bypass")\n'),
        ("\tif routes == null:\n", '\tif routes != null:\n\t\t_nav_probe.count("clearance_hit")\n'
         '\tif routes == null:\n\t\t_nav_probe.count("clearance_miss")\n'),
        ("\t\t_clearance_routes[clearance] = routes", "\t\troutes._probe_clearance = clearance\n"
         "\t\t_clearance_routes[clearance] = routes"),
        ("\tif cache.has(point):\n", '\tif cache.has(point):\n\t\t_nav_probe.count("endpoint_hit")\n'),
        ("\tvar links := PackedInt64Array()", '\t_nav_probe.count("endpoint_miss")\n\tvar links := PackedInt64Array()'),
        ("\treturn id\n", '\t_nav_probe.count("footprint_add_including_clearance_copies")\n\treturn id\n'),
        ("\tif _obstacles.erase(id):\n", '\tif _obstacles.erase(id):\n\t\t_nav_probe.count("revision_remove")\n'),
        ("\tif line_clear(start, end, -1, true):\n", '\tif line_clear(start, end, -1, true):\n'
         '\t\t_nav_probe.count("direct_path")\n'),
        ("\tif _graph_revision != revision:", '\t_nav_probe.count("blocked_direct_path")\n\tif _graph_revision != revision:'),
    ]
    for before, after in anchors:
        source = replace_once(source, before, after)
    for method, params, args, result in NATIVE_METHODS:
        source = source.replace(f"_graph.{method}(", f"_probe_astar_{method}(")
        call = f"_graph.{method}({args})"
        source += f"\n\nfunc _probe_astar_{method}({params}) -> {result}:\n"
        source += f"\tif not _nav_probe.active:\n\t\t{'return ' if result != 'void' else ''}{call}\n"
        if result == "void":
            source += "\t\treturn\n"
        source += f'\t_nav_probe.begin("astar/{method}/" + _nav_probe.caller())\n'
        source += f"\t{'var result := ' if result != 'void' else ''}{call}\n\t_nav_probe.end()\n"
        if result != "void":
            source += "\treturn result\n"
    for spec in NAV_METHODS:
        source = wrap(source, *spec)
    return source


def instrument(project):
    nav = project / "match/battle_navigation.gd"
    nav.write_text(instrument_navigation(nav.read_text()))
    battle = project / "match/battle.gd"
    source = replace_once(battle.read_text(), "const UnitCatalog", PROBE + "\n\nconst UnitCatalog")
    source = replace_once(
        source, "\t\t_set_route(unit, destination, _unit_navigation(unit).path(unit.position, destination))",
        '\t\t_nav_probe.count("route_to_repath")\n'
        '\t\tif unit.route_revision >= 0 and unit.route_revision != navigation.revision:\n'
        '\t\t\t_nav_probe.count("revision_repath")\n'
        "\t\t_set_route(unit, destination, _unit_navigation(unit).path(unit.position, destination))")
    for spec in BATTLE_METHODS:
        source = wrap(source, *spec)
    battle.write_text(source)
    match = project / "match/match.gd"
    source = replace_once(match.read_text(), "const Fortifications", PROBE + "\n\nconst Fortifications")
    source = wrap(source, "_try_cpu_purchase", "", False)
    match.write_text(source)


def run(command, log):
    with log.open("w") as output:
        subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                       timeout=900, check=True)
    rows = []
    with log.open() as output:
        for line in output:
            if line.startswith(("SCRIPT ERROR:", "ERROR:")):
                raise RuntimeError(f"Godot error in {log}: {line.rstrip()}")
            if line.startswith(PREFIX):
                rows.append(line.removeprefix(PREFIX))
    return rows


def compare(baseline_file, probe_rows):
    fields = ("case", "phase", "units", "obstacles", "revision_delta", "unit_state_hash")
    with baseline_file.open() as baseline:
        expected = [tuple(row[field] for field in fields)
                    for row in map(json.loads, baseline) if row.get("kind") == "phase"]
    observed = [tuple(row[field] for field in fields)
                for row in map(json.loads, probe_rows) if row.get("kind") == "phase"]
    if expected != observed:
        raise RuntimeError("Baseline and probe scenarios produced different battle states")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="Fresh scratch directory")
    parser.add_argument("--mode", choices=["both", "baseline", "probes"], default="both")
    parser.add_argument("--suite", choices=["all", "matrix", "match", "normal", "ownership"], default="all")
    parser.add_argument("--display", choices=["headless", "native"], default="headless")
    parser.add_argument("--obstacles", default="20,40,60")
    args = parser.parse_args()
    try:
        populations = [int(value) for value in args.obstacles.split(",")]
    except ValueError:
        parser.error("--obstacles takes comma-separated integers")
    if any(count < 6 or count > 126 for count in populations):
        parser.error("--obstacles populations must fit the 6 to 126 footprint fixture")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    # Copy live files so the harness can run from a worktree before it is committed.
    # Restrict source scope to the game and the benchmark.
    for mode in ("baseline", "probes") if args.mode == "both" else (args.mode,):
        project = output / mode
        for folder in ("match", "tests/performance"):
            shutil.copytree(ROOT / folder, project / folder, ignore=shutil.ignore_patterns("__pycache__"))
        for name in ("project.godot", "main.tscn", "game.tscn"):
            shutil.copy2(ROOT / name, project)
        if mode == "probes":
            instrument(project)
        godot = shutil.which(os.environ.get("GODOT", "godot"))
        run([godot, "--headless", "--path", str(project), "--import"], output / f"{mode}-import.log")
        display = ["--headless"] if args.display == "headless" else [
            "--resolution", "1280x800", "--disable-vsync", "--audio-driver", "Dummy"]
        rows = run([godot, *display, "--path", str(project), "--fixed-fps", "60", "--quit-after", "6000",
                    RESOURCE, "--", args.suite, mode, sha, args.obstacles], output / f"{mode}.log")
        if not rows or json.loads(rows[-1]) != {"complete": True}:
            raise RuntimeError(f"Incomplete benchmark: {output / f'{mode}.log'}")
        (output / f"{mode}.jsonl").write_text("".join(rows))
        if mode == "probes" and args.mode == "both":
            compare(output / "baseline.jsonl", rows)
        print(f"{mode}: {len(rows) - 2} measured phases, {output / f'{mode}.jsonl'}", flush=True)


if __name__ == "__main__":
    main()
