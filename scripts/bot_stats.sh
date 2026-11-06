#!/usr/bin/env bash
# Матчи бот против бота: scripts/bot_stats.sh [число матчей] [первый сид] [потолок минут]
# Печатает строку на матч и сводку: победы, средняя длина, захваты, доход.
set -u
cd "$(dirname "$0")/.."
N="${1:-20}"
FIRST="${2:-1}"
CAP="${3:-40}"
GODOT="${GODOT:-godot}"
OUT="$(mktemp -d)"
"$GODOT" --headless --path . --import >/dev/null 2>&1
JOBS="${JOBS:-4}"
seq "$FIRST" "$((FIRST + N - 1))" | xargs -P "$JOBS" -I{} sh -c "\"$GODOT\" --headless --path . -s tools/bot_match.gd -- {} $CAP 2>&1 | grep '^MATCH' > \"$OUT/{}.txt\""
cat "$OUT"/*.txt | sort -t= -k2 -n
python3 - "$OUT" <<'PY'
import sys, glob, re
rows = []
for f in glob.glob(sys.argv[1] + "/*.txt"):
    for line in open(f):
        m = dict(re.findall(r"(\w+)=(\[[^\]]*\]|[-\w.]+)", line))
        rows.append(m)
if not rows:
    print("нет данных"); sys.exit(1)
wins = [r for r in rows if r["winner"] != "-1"]
mins = [float(r["minutes"]) for r in rows]
w0 = sum(1 for r in wins if r["winner"] == "0")
print("матчей: %d, победой закончились: %d (P1: %d, P2: %d)" % (len(rows), len(wins), w0, len(wins) - w0))
print("длина, мин: средняя %.1f, мин %.1f, макс %.1f" % (sum(mins) / len(mins), min(mins), max(mins)))
PY
rm -rf "$OUT"
