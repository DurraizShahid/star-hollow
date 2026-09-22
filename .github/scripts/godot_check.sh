#!/usr/bin/env bash
set -u

log_file="$(mktemp)"
set +e
"$@" >"$log_file" 2>&1
status=$?
set -e

cat "$log_file"

if grep -E -q 'SCRIPT ERROR|Parse Error|ERROR: Failed to load script|ERROR: Failed to instantiate|Invalid call|Invalid get index|Cannot get class' "$log_file"; then
  echo "::error::Godot emitted a script/runtime error even though the process may have exited successfully."
  rm -f "$log_file"
  exit 1
fi

rm -f "$log_file"
exit "$status"
