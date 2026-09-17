#!/bin/bash
# Fast temperature gathering helper for Omarchy temperature widget.
# Tries `sensors -j`, supplements with `nvidia-smi` if present,
# and falls back to /sys/class/hwmon if sensors is not installed.

set -e

# Try sensors -j
sensors_json=""
if command -v sensors >/dev/null 2>&1; then
  sensors_json=$(sensors -j 2>/dev/null || true)
fi

# If sensors returned valid JSON
if [ -z "$sensors_json" ] || [ "$sensors_json" = "{}" ]; then
  # Fallback to sysfs hwmon
  hwmon_entries=()
  for h in /sys/class/hwmon/hwmon*; do
    [ -d "$h" ] || continue
    name=$(cat "$h/name" 2>/dev/null || basename "$h")
    sub_entries=()
    for t in "$h"/temp*_input; do
      [ -f "$t" ] || continue
      base="${t%_input}"
      label=$(cat "${base}_label" 2>/dev/null || basename "$base")
      val=$(cat "$t" 2>/dev/null || true)
      if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
        deg=$(awk "BEGIN {printf \"%.1f\", $val / 1000}")
        crit=$(cat "${base}_crit" 2>/dev/null || true)
        max=$(cat "${base}_max" 2>/dev/null || true)
        sub="\"$label\": {\"temp1_input\": $deg"
        if [ -n "$max" ] && [ "$max" -gt 0 ] 2>/dev/null; then
          max_deg=$(awk "BEGIN {printf \"%.1f\", $max / 1000}")
          sub="$sub, \"temp1_max\": $max_deg"
        fi
        if [ -n "$crit" ] && [ "$crit" -gt 0 ] 2>/dev/null; then
          crit_deg=$(awk "BEGIN {printf \"%.1f\", $crit / 1000}")
          sub="$sub, \"temp1_crit\": $crit_deg"
        fi
        sub="$sub}"
        sub_entries+=("$sub")
      fi
    done
    if [ ${#sub_entries[@]} -gt 0 ]; then
      joined_subs=$(IFS=,; echo "${sub_entries[*]}")
      hwmon_entries+=("\"$name\": { \"Adapter\": \"HWMON\", $joined_subs }")
    fi
  done
  if [ ${#hwmon_entries[@]} -gt 0 ]; then
    joined_hwmon=$(IFS=,; echo "${hwmon_entries[*]}")
    sensors_json="{ $joined_hwmon }"
  else
    sensors_json="{}"
  fi
fi

# Supplement with nvidia-smi if available
nvidia_json=""
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_info=$(nvidia-smi --query-gpu=name,temperature.gpu,temperature.memory --format=csv,noheader,nounits 2>/dev/null || true)
  if [ -n "$gpu_info" ]; then
    idx=0
    nvidia_parts=()
    while IFS=, read -r g_name g_temp g_mem; do
      g_name=$(echo "$g_name" | xargs)
      g_temp=$(echo "$g_temp" | xargs)
      g_mem=$(echo "$g_mem" | xargs)
      if [ -n "$g_temp" ] && [ "$g_temp" != "[N/A]" ]; then
        entry="\"GPU $idx ($g_name)\": {\"temp1_input\": $g_temp"
        if [ -n "$g_mem" ] && [ "$g_mem" != "[N/A]" ]; then
          entry="$entry, \"temp2_input\": $g_mem"
        fi
        entry="$entry}"
        nvidia_parts+=("$entry")
      fi
      idx=$((idx + 1))
    done <<< "$gpu_info"
    if [ ${#nvidia_parts[@]} -gt 0 ]; then
      joined_nvidia=$(IFS=,; echo "${nvidia_parts[*]}")
      nvidia_json="\"nvidia-gpu\": { \"Adapter\": \"PCI adapter\", $joined_nvidia }"
    fi
  fi
fi

if [ -n "$nvidia_json" ]; then
  if [ "$sensors_json" = "{}" ] || [ -z "$sensors_json" ]; then
    echo "{ $nvidia_json }"
  else
    clean_sensors=$(echo "$sensors_json" | sed 's/}[[:space:]]*$/ /')
    echo "${clean_sensors}, $nvidia_json }"
  fi
else
  echo "$sensors_json"
fi
