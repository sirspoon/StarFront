#!/usr/bin/env bash
# Plays computer-vs-computer battles without a screen and prints each result.
# Usage: tools/autotest.sh [first_seed] [count]   (GODOT=path/to/godot to override)
GODOT=${GODOT:-godot}
first=${1:-1}; count=${2:-8}
cd "$(dirname "$0")/.."
"$GODOT" --headless --import >/dev/null 2>&1
for ((s=first; s<first+count; s++)); do
  ("$GODOT" --headless --fixed-fps 20 -- --autotest --seed=$s 2>&1 | grep -E "RESULT|ERROR" | sed "s/^/seed $s: /") &
done
wait
