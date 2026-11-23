#!/usr/bin/env bash
# Launch the four independent Conky widgets or one selected widget.
set -euo pipefail
DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
selection=all
delay=0
while (($#)); do
  case "$1" in
    --widget)
      [[ $# -ge 2 ]] || { echo 'Missing --widget value' >&2; exit 2; }
      selection="$2"; shift 2 ;;
    --delay)
      [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { echo 'Delay must be a nonnegative integer' >&2; exit 2; }
      delay="$2"; shift 2 ;;
    -h|--help)
      printf 'Usage: bash start.sh [--widget all|prayer|date|weather|sun_moon] [--delay SECONDS]\n'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$selection" in all|prayer|date|weather|sun_moon) ;; *) echo "Unknown widget: $selection" >&2; exit 2 ;; esac
# Validate the intentionally selected X11/XWayland backend before launch.
python3 "$DIR/doctor.py" --runtime-only || exit 1
if [[ "$delay" != "0" ]]; then sleep "$delay"; fi
launch() { conky -d -c "$DIR/configs/$1"; }
case "$selection" in
  all)      launch conky_date.conf; launch conky_prayer_times.conf; launch conky_weather.conf; launch conky_sun_moon.conf ;;
  date)     launch conky_date.conf ;;
  prayer)   launch conky_prayer_times.conf ;;
  weather)  launch conky_weather.conf ;;
  sun_moon) launch conky_sun_moon.conf ;;
esac
