#!/usr/bin/env python3
"""Liest die festen Runden aus den Swift-Quellen und schreibt levels.c."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(__file__).resolve().parent / "levels.c"

LEVEL = re.compile(
    r'Level\(name:\s*"((?:\\.|[^"\\])*)"(?:,\s*sink:\s*(\d+))?,\s*rows:\s*\[(.*?)\]\s*\)',
    re.S,
)
ROW = re.compile(r'"([^"]*)"')


def grab(text, start, end):
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


def parse(text):
    found = []
    for name, sink, body in LEVEL.findall(text):
        rows = ROW.findall(body)
        if not rows:
            raise SystemExit(f"keine Reihen in {name}")
        found.append((name, int(sink or 0), rows))
    return found


def c_string(text):
    out = ['"']
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ord(ch) < 32:
            out.append("\\x%02x" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def main():
    sim = (ROOT / "Sources" / "Sim.swift").read_text()
    camp = (ROOT / "Sources" / "Campaign.swift").read_text()
    opening = parse(grab(sim, "private static let opening", "private static let levels"))
    extra = parse(grab(camp, "static let extraLevels", "extension Sim") if "extension Sim" in camp[camp.index("extraLevels"):] else camp)
    if len(extra) < 100:
        extra = parse(camp)
    levels = opening + extra
    names = [name for name, _, _ in levels]
    if len(levels) != 208:
        raise SystemExit(f"erwartet 208 Runden, gefunden {len(levels)} ({len(opening)} + {len(extra)})")
    if len(set(names)) != len(names):
        raise SystemExit("doppelter Rundenname")
    lines = [
        "/* Erzeugt von gen_levels.py aus den Swift-Runden. */",
        '#include "levels.h"',
        "",
    ]
    for index, (name, sink, rows) in enumerate(levels):
        lines.append(f"static const char *const rows_{index}[] = {{")
        for row in rows:
            lines.append(f"    {c_string(row)},")
        lines.append("};")
    lines.append("")
    lines.append("const LevelDef k_levels[] = {")
    for index, (name, sink, rows) in enumerate(levels):
        lines.append(
            f"    {{ {c_string(name)}, {sink}, rows_{index}, {len(rows)} }},"
        )
    lines.append("};")
    lines.append(f"const int k_level_count = {len(levels)};")
    lines.append("")
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(levels)} Runden, erste {names[0]}, letzte {names[-1]}")


if __name__ == "__main__":
    main()
