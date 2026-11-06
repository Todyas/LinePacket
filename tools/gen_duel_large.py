#!/usr/bin/env python3
"""Генератор maps/duel_large.json: левая половина описана вручную, правая — зеркало, центр на оси."""
import json

W = 3000
# Левая половина: (тип, x, y, владелец)
L = [
    ("core", 200, 800, 0),        # 0
    ("gateway", 380, 800, 0),     # 1
    ("machine", 380, 610, -1),    # 2
    ("machine", 380, 990, -1),    # 3
    ("machine", 200, 620, -1),    # 4
    ("machine", 200, 980, -1),    # 5
    ("router", 580, 800, -1),     # 6  вход в домашнюю подсеть
    ("machine", 600, 560, -1),    # 7
    ("machine", 600, 1040, -1),   # 8
    ("machine", 800, 690, -1),    # 9
    ("machine", 800, 910, -1),    # 10
    ("router", 800, 420, -1),     # 11 вход в северную ничейную подсеть
    ("machine", 1010, 300, -1),   # 12
    ("machine", 1010, 520, -1),   # 13
    ("gateway", 800, 200, -1),    # 14 ничейный шлюз севера
    ("router", 800, 1180, -1),    # 15 вход в южную ничейную подсеть
    ("machine", 1010, 1080, -1),  # 16
    ("machine", 1010, 1300, -1),  # 17
    ("machine", 800, 1400, -1),   # 18
    ("machine", 1200, 650, -1),   # 19
    ("machine", 1200, 950, -1),   # 20
    ("machine", 1200, 800, -1),   # 21
]
# Центр на оси: (тип, x, y)
C = [
    ("gateway", W // 2, 300),     # богатый шлюз севера
    ("gateway", W // 2, 1300),    # богатый шлюз юга
    ("router", W // 2, 800),      # центральный маршрутизатор
    ("machine", W // 2, 560),
    ("machine", W // 2, 1040),
]
# Связи левой половины и центра. Индексы центра — "c0".."c4".
LL = [
    (0, 1, "optic"), (0, 4, "cable"), (0, 5, "cable"),
    (1, 2, "cable"), (1, 3, "cable"), (1, 6, "cable"), (2, 4, "cable"), (3, 5, "cable"),
    (6, 7, "cable"), (6, 8, "cable"), (6, 9, "cable"), (6, 10, "cable"), (7, 9, "cable"), (8, 10, "cable"),
    (7, 11, "wifi"), (11, 13, "cable"), (11, 14, "cable"), (12, 13, "cable"), (12, 14, "cable"),
    (8, 15, "wifi"), (15, 16, "cable"), (15, 18, "cable"), (16, 17, "cable"), (17, 18, "cable"),
    (19, 21, "cable"), (20, 21, "cable"),
    (13, 19, "cable"), (16, 20, "cable"),
    (12, "c0", "optic"), (17, "c1", "optic"), (21, "c2", "optic"),
    (19, "c3", "cable"), (20, "c4", "cable"),
]
CC = [("c0", "c3", "cable"), ("c1", "c4", "cable"), ("c3", "c2", "cable"), ("c4", "c2", "cable")]

n = len(L)
nodes = []
for i, (t, x, y, o) in enumerate(L):
    nodes.append({"id": i, "type": t, "x": x, "y": y, "owner": o})
for i, (t, x, y, o) in enumerate(L):
    nodes.append({"id": n + i, "type": t, "x": W - x, "y": y, "owner": 1 if o == 0 else -1})
cid = {}
for j, (t, x, y) in enumerate(C):
    cid["c%d" % j] = 2 * n + j
    nodes.append({"id": 2 * n + j, "type": t, "x": x, "y": y, "owner": -1})

def idx(v, mirror):
    if isinstance(v, str):
        return cid[v]
    return v + (n if mirror else 0)

links, seen = [], set()
def add(a, b, k):
    key = (min(a, b), max(a, b))
    if key in seen:
        return
    seen.add(key)
    links.append({"a": a, "b": b, "kind": k})
for a, b, k in LL:
    add(idx(a, False), idx(b, False), k)
for a, b, k in LL:
    add(idx(a, True), idx(b, True), k)
for a, b, k in CC:
    add(idx(a, False), idx(b, False), k)

d = {"name": "Большая Дуэль", "players": 2, "nodes": nodes, "links": links}
with open("maps/duel_large.json", "w") as f:
    json.dump(d, f, ensure_ascii=False, indent=1)
deg = {}
for l in links:
    deg[l["a"]] = deg.get(l["a"], 0) + 1
    deg[l["b"]] = deg.get(l["b"], 0) + 1
print(len(nodes), "узлов", len(links), "линков", "gateways:", sum(1 for x in nodes if x["type"] == "gateway"))
print("макс. степень:", sorted(deg.items(), key=lambda kv: -kv[1])[:6])
