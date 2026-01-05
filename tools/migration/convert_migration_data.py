#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


RE_VECTOR2I = re.compile(r"Vector2i\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)")
RE_TRAILING_COMMA = re.compile(r",\s*([}\]])")


EMPLOYEE_ID_MAP: dict[str, str] = {
    "new_business_developer": "new_business_dev",
    "recruiting_girl": "recruiter",
    "marketing_trainee": "marketer",
    "vice_precident": "vice_president",
    "junior_vice_precident": "junior_vice_president",
    "senior_vice_precident": "senior_vice_president",
    "executive_vice_precident": "executive_vp",
    "recuriting_manager": "recruiting_manager",
    "zippelin_pilot": "zeppelin_pilot",
    "zeppeliner": "zeppelin_pilot",
    "CFO": "cfo",
}

MILESTONE_ID_MAP: dict[str, str] = {
    "first_to_hire_3_people_in_1_turn": "first_hire_3",
    "first_throw_away_drink_or_food": "first_throw_away",
    "first_waitress_played": "first_waitress",
    "first_to_have_20": "first_have_20",
    "first_to_have_100": "first_have_100",
    "first_to_lower_price": "first_lower_prices",
    "first_to_train_someone": "first_train",
    "first_burger_produced": "first_burger_produced",
    "first_pizza_produced": "first_pizza_produced",
    "first_errand_boy_played": "first_errand_boy",
    "first_cart_operator_played": "first_cart_operator",
    "first_to_pay_20_or_more_in_salaries": "first_pay_20_salaries",
    "first_billboard_placed": "first_billboard",
    "first_burger_marketed": "first_burger_marketed",
    "first_pizza_marketed": "first_pizza_marketed",
    "first_drink_marketed": "first_drink_marketed",
    "first_airplane_campaign": "first_airplane",
    "first_radio_campaign": "first_radio",
}


MANDATORY_EMPLOYEE_IDS: set[str] = {
    "pricing_manager",
    "discount_manager",
    "luxury_manager",
    "cfo",
    "recruiting_manager",
    "hr_director",
    "waitress",
}


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _extract_assignment_expr(text: str, key: str) -> str | None:
    m = re.search(rf"(?m)^\s*{re.escape(key)}\s*=\s*", text)
    if not m:
        return None
    i = m.end()
    while i < len(text) and text[i].isspace():
        i += 1

    # Array[Dictionary]([ ... ])
    if text.startswith("Array[Dictionary](", i):
        i = text.index("(", i) + 1
        while i < len(text) and text[i].isspace():
            i += 1

    if i >= len(text):
        return None

    if text[i] == "[":
        return _extract_balanced(text, i, "[", "]")
    if text[i] == "{":
        return _extract_balanced(text, i, "{", "}")

    raise ValueError(f"Unsupported assignment expression for {key} at offset {i}: {text[i:i+40]!r}")


def _extract_balanced(text: str, start: int, open_ch: str, close_ch: str) -> str:
    level = 0
    in_str = False
    escape = False
    i = start
    while i < len(text):
        ch = text[i]
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
            elif ch == open_ch:
                level += 1
            elif ch == close_ch:
                level -= 1
                if level == 0:
                    return text[start : i + 1]
        i += 1
    raise ValueError(f"Unclosed expression starting at {start} ({open_ch}..{close_ch})")


def _gdexpr_to_jsonish(expr: str) -> str:
    expr = RE_VECTOR2I.sub(r"[\1, \2]", expr)
    expr = RE_TRAILING_COMMA.sub(r"\1", expr)
    return expr


def _normalize_employee_id(raw_id: str) -> tuple[str, list[str]]:
    mapped = EMPLOYEE_ID_MAP.get(raw_id, raw_id)
    aliases: list[str] = []
    if mapped != raw_id:
        aliases.append(raw_id)
    return mapped, aliases


def _normalize_employee_ids_in_value(value: Any) -> Any:
    if isinstance(value, str):
        return EMPLOYEE_ID_MAP.get(value, value)
    if isinstance(value, list):
        return [_normalize_employee_ids_in_value(v) for v in value]
    if isinstance(value, dict):
        return {k: _normalize_employee_ids_in_value(v) for k, v in value.items()}
    return value


def _convert_tile(path: Path) -> tuple[str, dict[str, Any]]:
    text = _read_text(path)
    m = re.search(r'(?m)^\s*id\s*=\s*"([^"]+)"\s*$', text)
    if not m:
        raise ValueError(f"Tile missing id: {path}")
    raw_id = m.group(1)

    letter = raw_id
    if raw_id.lower().startswith("tile_"):
        letter = raw_id.split("_", 1)[1]
    tile_id = f"tile_{letter.lower()}"

    road_expr = _extract_assignment_expr(text, "road_segments")
    if road_expr is None:
        raise ValueError(f"Tile missing road_segments: {path}")
    road_segments = json.loads(_gdexpr_to_jsonish(road_expr))
    # Ensure every segment has bridge flag, matching current TileDef JSON schema.
    for y in range(len(road_segments)):
        for x in range(len(road_segments[y])):
            cell = road_segments[y][x]
            if not isinstance(cell, list):
                raise ValueError(f"Tile road cell is not list at {path} {x},{y}: {cell!r}")
            for seg in cell:
                if isinstance(seg, dict) and "bridge" not in seg:
                    seg["bridge"] = False

    printed_structures: list[dict[str, Any]] = []
    printed_expr = _extract_assignment_expr(text, "printed_structures")
    if printed_expr is not None:
        printed_raw = json.loads(_gdexpr_to_jsonish(printed_expr))
        for item in printed_raw:
            if not isinstance(item, dict):
                continue
            out: dict[str, Any] = {}
            for key in ["piece_id", "anchor", "rotation", "house_id", "house_number"]:
                if key in item:
                    out[key] = item[key]
            if out:
                printed_structures.append(out)

    drink_sources: list[dict[str, Any]] = []
    drink_expr = _extract_assignment_expr(text, "drink_sources")
    if drink_expr is not None:
        drink_raw = json.loads(_gdexpr_to_jsonish(drink_expr))
        for item in drink_raw:
            if not isinstance(item, dict):
                continue
            if "pos" in item and "type" in item:
                drink_sources.append({"pos": item["pos"], "type": item["type"]})

    out = {
        "id": tile_id,
        "display_name": f"板块 {letter}",
        "road_segments": road_segments,
        "printed_structures": printed_structures,
        "drink_sources": drink_sources,
        "blocked_cells": [],
        "allowed_rotations": [0, 90, 180, 270],
    }
    return tile_id, out


def _convert_employees(path: Path) -> list[dict[str, Any]]:
    text = _read_text(path)
    expr = _extract_assignment_expr(text, "employees")
    if expr is None:
        raise ValueError(f"Employees seed missing employees = [...] : {path}")
    raw = json.loads(_gdexpr_to_jsonish(expr))
    out: list[dict[str, Any]] = []

    for item in raw:
        if not isinstance(item, dict):
            continue
        raw_id = str(item.get("id", "")).strip()
        if not raw_id:
            continue

        emp_id, aliases = _normalize_employee_id(raw_id)
        normalized = _normalize_employee_ids_in_value(item)

        result: dict[str, Any] = {
            "id": emp_id,
            "name": normalized.get("name", ""),
            "description": normalized.get("description", ""),
            "salary": bool(normalized.get("salary", False)),
            "unique": bool(normalized.get("unique_1x", normalized.get("unique", False))),
            "manager_slots": int(normalized.get("manager_slots", 0) or 0),
            "range": {
                "type": normalized.get("range_type", None),
                "value": int(normalized.get("range_value", 0) or 0),
            },
            "train_to": normalized.get("train_to", []),
            "train_capacity": int(normalized.get("train_capacity", 0) or 0),
            "tags": normalized.get("tags", []),
            "usage_tags": normalized.get("usage_tags", []),
            "mandatory": emp_id in MANDATORY_EMPLOYEE_IDS,
        }
        if aliases:
            result["aliases"] = aliases

        out.append(result)

    out.sort(key=lambda e: e.get("id", ""))
    return out


def _convert_milestones(path: Path) -> list[dict[str, Any]]:
    text = _read_text(path)
    expr = _extract_assignment_expr(text, "milestones")
    if expr is None:
        raise ValueError(f"Milestones seed missing milestones = [...] : {path}")
    raw = json.loads(_gdexpr_to_jsonish(expr))
    out: list[dict[str, Any]] = []

    for item in raw:
        if not isinstance(item, dict):
            continue
        raw_id = str(item.get("id", "")).strip()
        if not raw_id:
            continue
        milestone_id = MILESTONE_ID_MAP.get(raw_id, raw_id)

        trigger_event = item.get("trigger_event", "")
        trigger_filter = item.get("trigger_filter", None)

        effects = item.get("effects", [])
        effects = _normalize_employee_ids_in_value(effects)

        expires_at = None
        if milestone_id in {"first_burger_marketed", "first_pizza_marketed", "first_drink_marketed", "first_train"}:
            expires_at = 2
        elif milestone_id == "first_hire_3":
            expires_at = 3

        result: dict[str, Any] = {
            "id": milestone_id,
            "name": item.get("name", ""),
            "trigger": {"event": trigger_event, "filter": trigger_filter} if trigger_filter is not None else {"event": trigger_event},
            "effects": effects,
            "exclusive_type": milestone_id,
            "expires_at": expires_at,
        }
        out.append(result)

    out.sort(key=lambda m: m.get("id", ""))
    return out


def _write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Convert legacy .tres seeds into JSON for reference.\n"
            "NOTE: The runtime source-of-truth is modules/*/content/**/*.json (not this output)."
        )
    )
    parser.add_argument("--root", default=".", help="Project root (default: .)")
    parser.add_argument(
        "--seeds-dir",
        default="tools/migration/legacy_seeds",
        help="Legacy .tres seeds directory relative to --root (default: tools/migration/legacy_seeds)",
    )
    parser.add_argument(
        "--out-dir",
        default="tools/migration/out_legacy_json",
        help="Output directory relative to --root (default: tools/migration/out_legacy_json)",
    )
    parser.add_argument("--force", action="store_true", help="Overwrite existing output files")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    migration_dir = root / str(args.seeds_dir)
    tiles_in = migration_dir / "tiles"
    if not tiles_in.exists():
        raise SystemExit(f"Missing migration tiles dir: {tiles_in}")

    out_root = root / str(args.out_dir)
    tiles_out = out_root / "tiles"
    employees_out = out_root / "employees"
    milestones_out = out_root / "milestones"

    # Tiles
    for tile_path in sorted(tiles_in.glob("Tile_*.tres")):
        tile_id, tile_data = _convert_tile(tile_path)
        out_path = tiles_out / f"{tile_id}.json"
        if out_path.exists() and not args.force:
            continue
        _write_json(out_path, tile_data)

    # Employees (one JSON per employee)
    employees = _convert_employees(migration_dir / "base_employees_full.tres")
    for emp in employees:
        emp_id = emp["id"]
        out_path = employees_out / f"{emp_id}.json"
        if out_path.exists() and not args.force:
            continue
        _write_json(out_path, emp)

    # Milestones (one JSON per milestone)
    milestones = _convert_milestones(migration_dir / "base_milestones_full.tres")
    for ms in milestones:
        ms_id = ms["id"]
        out_path = milestones_out / f"{ms_id}.json"
        if out_path.exists() and not args.force:
            continue
        _write_json(out_path, ms)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
