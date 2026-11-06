#!/usr/bin/env bash
# Все тесты headless + проверка детерминизма между процессами.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

# Обновить кэш классов (class_name) — нужно на свежем клоне.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

out=$("$GODOT" --headless --path . -s tests/run_tests.gd 2>&1) || { echo "$out"; echo "ОШИБКА: тесты провалены"; exit 1; }
echo "$out"
if echo "$out" | grep -qE "SCRIPT ERROR|Parse Error|^ERROR:"; then
  echo "ОШИБКА: движок сообщил об ошибках скриптов"
  exit 1
fi

h1=$("$GODOT" --headless --path . -s tools/hash_scenario.gd | grep '^HASH ')
h2=$("$GODOT" --headless --path . -s tools/hash_scenario.gd | grep '^HASH ')
echo "Детерминизм: $h1 / $h2"
if [ -z "$h1" ] || [ "$h1" != "$h2" ]; then
  echo "ОШИБКА: хеши между процессами не совпали"
  exit 1
fi
echo "scripts/test.sh: всё зелёное"
