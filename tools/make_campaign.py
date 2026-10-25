#!/usr/bin/env python3
"""Baut die festen Zusatzrunden nach den 52 gezeichneten Bildern."""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIM = ROOT / "Sources" / "Sim.swift"
OUT = ROOT / "Sources" / "Campaign.swift"
TARGET = 156

NAMES = """
Ader Allee Anker Aquädukt Arkade Ast Atlas Aue Bach Barke Bastion Becher
Biene Blitz Blume Bohrer Boje Bucht Bühne Damm Delta Dock Dom Düne Echo
Eis Elle Fächer Fahne Fahrt Falke Falle Fels Fibel Fjord Flamme Floh
Flosse Flur Föhn Fontäne Forum Fuchs Fuge Gabel Galerie Gasse Geäst
Geige Glocke Glut Graben Grat Grotte Hafen Hai Halde Halle Hang Harfe
Harnisch Haube Helix Helm Herd Höhle Horn Hort Hufeisen Inselkette Joch
Kanal Kante Kap Karpfen Katapult Katze Kehle Kelch Kerbe Kette Kiel
Kiefer Kiesel Kippe Klaue Klee Klippe Knoten Kobel Koje Kolben Komet
Kralle Kranz Krebs Kreis Krug Kufe Kuppel Labyrinth Lache Lanze Laterne
Laube Leuchtturm Linse Locke Lore Lotse Luchs Lupe Mähne Mast Meile
Mühle Mulde Nadel Nest Netz Nische Nordkap Oase Orkan Oval Paddel Palme
Pass Pfad Pfau Pfeife Pflock Pforte Phiole Pilz Pinie Planke Plateau
Pokal Portal Quelle Rabe Rad Raps Rast Raupe Regen Reif Riegel Rippe
Rost Rune Sattel Schale Schanze Schatten Schiff Schilf Schlange Schleuse
Schlinge Schlot Scholle Schuppe Schwert Segel Sense Sichel Silo Sockel
Sonne Spalt Speer Spindel Spore Sprosse Stab Stamm Steg Stern Stirn
Strebe Strom Stufe Tafel Tal Tanne Teich Tempel Thron Traube Trieb Trog
Tropfen Tunnel Uhr Ufer Ulme Vase Veilchen Vorhang Waage Wald Walze
Wappen Wehr Weide Woge Wurf Zacke Zaun Zelle Zelt Zickzack Zinne Zirkel
Zisterne Zug Zweig
""".split()


def empty(rows, cols):
    return [["." for _ in range(cols)] for _ in range(rows)]


def put(grid, r, c):
    if 0 <= r < len(grid) and 0 <= c < len(grid[0]):
        grid[r][c] = "x"


def arch_bands(rows, cols, v):
    grid = empty(rows, cols)
    width = 1 + (v % 2)
    for r in range(rows):
        hole = (v * 2 + r * (1 + v % 3)) % cols
        for c in range(cols):
            dist = min((c - hole) % cols, (hole - c) % cols)
            if dist > width:
                grid[r][c] = "x"
    return grid


def arch_columns(rows, cols, v):
    grid = empty(rows, cols)
    step = 2 + (v % 2)
    shift = v % step
    for c in range(cols):
        if (c + shift) % step == 0:
            continue
        for r in range(rows):
            if r == rows // 2 and (c + v) % 4 == 0:
                continue
            grid[r][c] = "x"
    for c in range(cols):
        if (c + v) % 5 != 0:
            grid[rows - 1][c] = "x"
    return grid


def arch_check(rows, cols, v):
    grid = empty(rows, cols)
    cx, cy = cols // 2, rows // 2
    rad = 1 + (v % 3)
    for r in range(rows):
        for c in range(cols):
            if (r + c + (v % 2)) % 2 == 0 and abs(c - cx) + abs(r - cy) > rad:
                grid[r][c] = "x"
    return grid


def arch_diamond(rows, cols, v):
    grid = empty(rows, cols)
    cx, cy = cols // 2, rows // 2
    reach = min(cx, cy + 2)
    inner = v % 3
    for r in range(rows):
        for c in range(cols):
            dist = abs(c - cx) + abs(r - cy)
            if inner <= dist <= reach:
                grid[r][c] = "x"
    return grid


def arch_outline(rows, cols, v):
    grid = empty(rows, cols)
    cx = cols // 2
    reach = min(cx, rows)
    gap = 2 + (v % 2)
    for r in range(rows):
        for c in range(cols):
            dist = abs(c - cx) + abs(r - rows // 2)
            if dist == reach or dist == max(1, reach - gap):
                grid[r][c] = "x"
    return grid


def arch_frames(rows, cols, v):
    grid = empty(rows, cols)
    inset = v % 2
    for r in range(rows):
        for c in range(cols):
            outer = r in (inset, rows - 1 - inset) or c in (inset, cols - 1 - inset)
            inner_r = r in (inset + 2, rows - 3) if rows > 5 else False
            inner_c = c in (inset + 2, cols - 3)
            if outer or inner_r or (inner_c and inset + 1 < r < rows - 2):
                grid[r][c] = "x"
    door = cols // 2
    grid[rows - 1][door] = "."
    if door > 0:
        grid[rows - 1][door - 1] = "."
    if door + 1 < cols:
        grid[rows - 1][door + 1] = "."
    return grid


def arch_stairs(rows, cols, v):
    grid = empty(rows, cols)
    flip = v % 2
    for r in range(rows):
        width = min(cols, 2 + r + (v % 3))
        for c in range(width):
            cc = c if flip == 0 else cols - 1 - c
            grid[r][cc] = "x"
    return grid


def arch_v(rows, cols, v):
    grid = empty(rows, cols)
    cx = cols // 2
    thick = v % 2
    for r in range(rows):
        spread = r if v % 2 == 0 else rows - 1 - r
        for c in range(cols):
            if abs(abs(c - cx) - spread) <= thick:
                grid[r][c] = "x"
    return grid


def arch_x(rows, cols, v):
    grid = empty(rows, cols)
    thick = v % 2
    for r in range(rows):
        left = int(round(c_to_r(r, rows, cols)))
        for c in range(cols):
            down = int(round(c * (rows - 1) / (cols - 1)))
            if abs(r - down) <= thick or abs(r - (rows - 1 - down)) <= thick:
                grid[r][c] = "x"
        _ = left
    return grid


def c_to_r(r, rows, cols):
    return r * (cols - 1) / max(1, rows - 1)


def arch_plus(rows, cols, v):
    grid = empty(rows, cols)
    arm = 1 + (v % 2)
    cx, cy = cols // 2, rows // 2
    for r in range(rows):
        for c in range(cols):
            on = abs(c - cx) <= arm or abs(r - cy) <= arm
            if on and (v < 3 or abs(c - cx) == 0 or abs(r - cy) == 0 or (r + c) % 2 == 0):
                grid[r][c] = "x"
    return grid


def arch_corners(rows, cols, v):
    grid = empty(rows, cols)
    size = 2 + (v % 2)
    for r in range(rows):
        for c in range(cols):
            corner = (r < size or r >= rows - size) and (c < size or c >= cols - size)
            if corner:
                grid[r][c] = "x"
    for r in range(max(0, rows // 2 - 1), min(rows, rows // 2 + 2)):
        for c in range(max(0, cols // 2 - 2), min(cols, cols // 2 + 3)):
            grid[r][c] = "x"
    if v % 2:
        for c in range(cols):
            grid[0][c] = "x"
    return grid


def arch_islands(rows, cols, v):
    grid = empty(rows, cols)
    spots = [(1, 2), (1, cols - 3), (rows // 2, cols // 2), (rows - 2, 3), (rows - 2, cols - 4)]
    rad = 1 + (v % 2)
    for index, (cr, cc) in enumerate(spots):
        cr = min(rows - 1, max(0, cr + (index + v) % 2))
        for r in range(rows):
            for c in range(cols):
                if abs(r - cr) + abs(c - cc) <= rad:
                    grid[r][c] = "x"
    return grid


def arch_snake(rows, cols, v):
    grid = empty(rows, cols)
    for r in range(rows):
        if (r + v) % 2 == 0:
            start, end = 0, cols - (v % 3)
        else:
            start, end = 1 + (v % 2), cols
        for c in range(max(0, start), min(cols, end)):
            grid[r][c] = "x"
    return grid


def arch_wave(rows, cols, v):
    grid = empty(rows, cols)
    for c in range(cols):
        crest = (c + v) % 4
        for t in range(1 + (v % 2)):
            put(grid, crest + t, c)
            if v % 2 == 0:
                put(grid, rows - 1 - crest - t, c)
    for r in range(rows // 2, rows):
        for c in range(cols):
            if (c + r + v) % 3 != 0:
                grid[r][c] = "x"
    return grid


def arch_arrow(rows, cols, v):
    grid = empty(rows, cols)
    cx = cols // 2
    head = max(2, rows // 2)
    up = v % 2 == 0
    thick = 1 + (v % 2)
    for r in range(rows):
        src = r if up else rows - 1 - r
        for c in range(cols):
            if src < head and abs(c - cx) <= src:
                grid[r][c] = "x"
            if src >= head and abs(c - cx) <= thick:
                grid[r][c] = "x"
    return grid


def arch_bars(rows, cols, v):
    grid = empty(rows, cols)
    for r in range(rows):
        if r % 2 == (v % 2):
            door = (r * 3 + v * 2) % cols
            for c in range(cols):
                if min((c - door) % cols, (door - c) % cols) > 1:
                    grid[r][c] = "x"
        else:
            for c in range(0, cols, 1 + (v % 2)):
                grid[r][c] = "x"
    return grid


def arch_honey(rows, cols, v):
    grid = empty(rows, cols)
    step = 2 + (v % 2)
    for r in range(rows):
        shift = (r % 2) * (1 + v % 2)
        for c in range(cols):
            if (c + shift) % step != v % step:
                grid[r][c] = "x"
    return grid


def arch_court(rows, cols, v):
    grid = empty(rows, cols)
    for r in range(rows):
        for c in range(cols):
            if r == 0 or c == 0 or c == cols - 1:
                grid[r][c] = "x"
    cx, cy = cols // 2, rows // 2
    if v % 3 == 0:
        for c in range(2, cols - 2):
            grid[cy][c] = "x"
    elif v % 3 == 1:
        for r in range(1, rows - 1):
            grid[r][cx] = "x"
    else:
        for k in range(-2, 3):
            put(grid, cy + k, cx + k)
            put(grid, cy + k, cx - k)
    for c in range(3, cols - 3):
        grid[rows - 1][c] = "x"
    return grid


def arch_twins(rows, cols, v):
    grid = empty(rows, cols)
    mid = cols // 2
    gap = 1 + (v % 2)
    for r in range(rows):
        for c in range(cols):
            if abs(c - mid) < gap:
                continue
            side = 0 if c < mid else 1
            if (r + side * (1 + v % 2) + v) % 3 != 0:
                grid[r][c] = "x"
    return grid


def arch_spiral(rows, cols, v):
    grid = empty(rows, cols)
    parity = v % 2
    for r in range(rows):
        for c in range(cols):
            layer = min(r, c, rows - 1 - r, cols - 1 - c)
            if layer % 2 == parity:
                grid[r][c] = "x"
    for layer in range(min(rows, cols) // 2):
        if layer % 2 != parity:
            continue
        span = cols - 2 * layer
        if span <= 0:
            continue
        door = layer + (layer * 2 + v) % span
        grid[layer][door] = "."
    return grid


def arch_teeth(rows, cols, v):
    grid = empty(rows, cols)
    tooth = 2 + (v % 2)
    for c in range(cols):
        tall = 2 + (v % 3) if (c // tooth) % 2 == 0 else rows - 1
        if v % 2 == 0:
            for r in range(rows - tall, rows):
                grid[r][c] = "x"
        else:
            for r in range(min(rows, tall)):
                grid[r][c] = "x"
    return grid


def arch_glass(rows, cols, v):
    grid = empty(rows, cols)
    cx = cols // 2
    for r in range(rows):
        t = r if r < rows / 2 else rows - 1 - r
        half = int(t * (cols / 2) / max(1, rows / 2))
        if v % 2:
            half = max(1, int(cols / 2) - half)
        half = max(1, half)
        for c in range(cx - half, cx + half + 1):
            put(grid, r, c)
    return grid


def arch_canyon(rows, cols, v):
    grid = empty(rows, cols)
    wall = 2 + (v % 2)
    for r in range(rows):
        wobble = ((r + v) % 3) - 1
        left = wall + wobble
        right = cols - wall + wobble
        for c in range(cols):
            if c < left or c >= right:
                grid[r][c] = "x"
        if r % (2 + v % 2) == 0:
            grid[r][cols // 2] = "x"
    return grid


def arch_rain(rows, cols, v):
    grid = empty(rows, cols)
    length = 2 + (v % 3)
    gap = 2 + (v % 2)
    for r in range(rows):
        offset = (r * (2 + v % 3) + v) % (length + gap)
        c = 0
        while c < cols:
            if (c + offset) % (length + gap) < length:
                grid[r][c] = "x"
            c += 1
    return grid


def arch_windows(rows, cols, v):
    grid = empty(rows, cols)
    for r in range(rows):
        for c in range(cols):
            if r % 3 == (v % 2) or c % 4 == (v % 3):
                grid[r][c] = "x"
    return grid


def arch_fan(rows, cols, v):
    grid = empty(rows, cols)
    cx, cy = cols // 2, rows // 2
    for r in range(rows):
        for c in range(cols):
            dist = abs(r - cy) + abs(c - cx)
            if r == cy or c == cx or dist == min(cx, rows - 1):
                grid[r][c] = "x"
            elif (r + c + v) % (3 + v % 2) == 0 and dist < rows:
                grid[r][c] = "x"
    return grid


ARCHETYPES = [
    arch_bands, arch_columns, arch_check, arch_diamond, arch_outline, arch_frames,
    arch_stairs, arch_v, arch_x, arch_plus, arch_corners, arch_islands,
    arch_snake, arch_wave, arch_arrow, arch_bars, arch_honey, arch_court,
    arch_twins, arch_spiral, arch_teeth, arch_glass, arch_canyon, arch_rain,
    arch_windows, arch_fan,
]


def specials_for(index):
    if index < 26:
        return []
    if index < 52:
        return ["#"]
    if index < 78:
        return ["#", "8"]
    if index < 104:
        return ["#", "8", "@"]
    if index < 130:
        return ["#", "8", "%", "*"]
    return ["#", "8", "@", "%", "*", "&", "+"]


def hue(index, r, c):
    mode = index % 4
    if mode == 0:
        return str(1 + (r + index) % 7)
    if mode == 1:
        return str(1 + (c + index) % 7)
    if mode == 2:
        return str(1 + (r + c + index) % 7)
    return str(1 + (r // 2 + c % 3 + index) % 7)


def colorize(mask, index):
    grid = []
    for r, row in enumerate(mask):
        grid.append([hue(index, r, c) if ch == "x" else "." for c, ch in enumerate(row)])
    return grid


def plain_count(grid):
    return sum(ch.isdigit() for row in grid for ch in row)


def decorate(grid, index):
    pool = specials_for(index)
    if not pool:
        return grid
    rows, cols = len(grid), len(grid[0])
    coords = [(r, c) for r in range(rows) for c in range(cols) if grid[r][c].isdigit()]
    step = 6 + (index % 3)
    placed = 0
    limit = 2 + index // 22
    for n, (r, c) in enumerate(coords):
        if placed >= limit:
            break
        if (n * 3 + index) % step != 0:
            continue
        kind = pool[(n + index) % len(pool)]
        if kind == "=":
            continue
        if kind == "+" or kind == "&":
            if r == rows - 1:
                continue
        if kind == "+":
            punched = False
            for dr, dc in ((0, 1), (1, 0), (0, -1), (-1, 0)):
                rr, cc = r + dr, c + dc
                if 0 <= rr < rows and 0 <= cc < cols and grid[rr][cc].isdigit():
                    grid[rr][cc] = "."
                    punched = True
                    break
            if not punched:
                continue
        grid[r][c] = kind
        placed += 1
    while plain_count(grid) < 8:
        restored = False
        for r in range(rows):
            for c in range(cols):
                if not grid[r][c].isdigit() and grid[r][c] != ".":
                    grid[r][c] = hue(index, r, c)
                    restored = True
                    break
            if restored and plain_count(grid) >= 8:
                break
        if not restored:
            break
    return grid


def thicken(mask):
    rows, cols = len(mask), len(mask[0])
    filled = sum(ch == "x" for row in mask for ch in row)
    if filled >= 28:
        return mask
    for c in range(cols):
        if (c % 4) != 0:
            mask[rows // 2][c] = "x"
            mask[0][c] = "x"
    return mask


def picture(grid):
    return "/".join("".join(row) for row in grid)


def nudge(grid, salt):
    rows, cols = len(grid), len(grid[0])
    r = salt % rows
    c = (salt // rows) % cols
    if grid[r][c] == ".":
        grid[r][c] = hue(salt, r, c)
    else:
        grid[r][c] = "."
    if plain_count(grid) < 8:
        grid[r][c] = hue(salt, r, c)
    return grid


def existing_pictures():
    text = SIM.read_text()
    block = text.split("private static let opening: [Level] = [")[1].split("\n    ]")[0]
    found = []
    for part in block.split("Level(")[1:]:
        rows = re.findall(r'"([0-9#=&@8%*+.]+)"', part)
        if rows:
            found.append("/".join(rows))
    names = re.findall(r'name: "([^"]+)"', block)
    return set(found), set(names)


def build():
    known, used_names = existing_pictures()
    names = []
    for name in NAMES:
        if name in used_names or name in names:
            continue
        names.append(name)
        if len(names) == TARGET:
            break
    if len(names) != TARGET:
        raise SystemExit(f"Namen: {len(names)}, gebraucht {TARGET}")
    levels = []
    seen = set(known)
    for index in range(TARGET):
        variant = index // len(ARCHETYPES)
        archetype = ARCHETYPES[index % len(ARCHETYPES)]
        rows = 6 + (variant % 3) + (1 if index > 110 else 0)
        sink = min(5, index // 36)
        if sink + rows > 15:
            rows = 15 - sink
        cols = 13
        mask = thicken(archetype(rows, cols, variant))
        grid = decorate(colorize(mask, index), index)
        salt = 1
        while picture(grid) in seen and salt < 40:
            grid = nudge([row[:] for row in grid], index * 17 + salt)
            salt += 1
        pic = picture(grid)
        if pic in seen:
            raise SystemExit(f"Runde {index} bleibt ein Duplikat")
        seen.add(pic)
        if plain_count(grid) < 8:
            raise SystemExit(f"{names[index]} hat zu wenig normale Steine")
        if any(set(row) == {"="} for row in grid):
            raise SystemExit(f"{names[index]} ist versiegelt")
        levels.append((names[index], sink, ["".join(row) for row in grid]))
    return levels


def emit(levels):
    lines = [
        "// Feste Runden nach den 52 gezeichneten Bildern. Der Satz endet hier.",
        "extension Sim {",
        "    static let extraLevels: [Level] = [",
    ]
    for name, sink, rows in levels:
        lines.append(f'        Level(name: "{name}", sink: {sink}, rows: [')
        for row in rows:
            lines.append(f'            "{row}",')
        lines.append("        ]),")
    lines.append("    ]")
    lines.append("}")
    lines.append("")
    OUT.write_text("\n".join(lines))
    print(f"{len(levels)} Zusatzrunden, zusammen {52 + len(levels)}")


if __name__ == "__main__":
    emit(build())
