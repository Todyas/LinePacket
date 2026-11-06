#!/usr/bin/env bash
# Сборка для Linux и Windows в build/. Нужны Godot 4.3 и шаблоны экспорта 4.3.stable
# (Editor → Manage Export Templates, либо распаковать .tpz в ~/.local/share/godot/export_templates/4.3.stable).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
mkdir -p build/linux build/windows
"$GODOT" --headless --path . --export-release "Linux x86_64" build/linux/LinePacket.x86_64
"$GODOT" --headless --path . --export-release "Windows x86_64" build/windows/LinePacket.exe
chmod +x build/linux/LinePacket.x86_64
echo "Готово: build/linux/LinePacket.x86_64, build/windows/LinePacket.exe"
