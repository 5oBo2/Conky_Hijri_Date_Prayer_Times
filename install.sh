#!/usr/bin/env bash
# Install the four-widget project, preserving user settings and saved layouts.
set -euo pipefail
SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/conky"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
make_autostart=1
run_wizard=1
for opt in "$@"; do
  case "$opt" in
    --no-autostart) make_autostart=0 ;;
    --no-configure) run_wizard=0 ;;
    -h|--help)
      printf 'Usage: bash install.sh [--no-autostart] [--no-configure]\n'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$opt" >&2; exit 2 ;;
  esac
done
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Python 3 is required.' >&2
  exit 1
fi
if [[ "$SOURCE" != "$DEST" ]]; then
  if [[ -e "$DEST" ]]; then
    BACKUP="${DEST}-backup-$(date +%Y%m%d-%H%M%S)-$$"
    cp -a -- "$DEST" "$BACKUP"
    echo "Existing Conky folder backed up: $BACKUP"
  fi
  mkdir -p -- "$DEST"
  for filename in configure.py doctor.py start.sh restart.py install.sh README.md ROADMAP.md widget_geometry.ini; do
    cp -- "$SOURCE/$filename" "$DEST/$filename"
  done
  for folder in configs widgets lib workers docs; do
    mkdir -p -- "$DEST/$folder"
    cp -a -- "$SOURCE/$folder/." "$DEST/$folder/"
  done
  # Never overwrite live settings, manual monitor geometry, saved layouts, or
  # named full-settings profiles when installing into an existing directory.
  if [[ ! -e "$DEST/settings.ini" ]]; then
    cp -- "$SOURCE/settings.ini" "$DEST/settings.ini"
  fi
  if [[ -f "$SOURCE/monitor_geometry.json" && ! -e "$DEST/monitor_geometry.json" ]]; then
    cp -- "$SOURCE/monitor_geometry.json" "$DEST/monitor_geometry.json"
  fi
  for folder in profiles layouts; do
    if [[ -d "$SOURCE/$folder" ]]; then
      mkdir -p -- "$DEST/$folder"
      cp -an -- "$SOURCE/$folder/." "$DEST/$folder/"
    fi
  done
  if [[ -f "$SOURCE/athan.wav" && ! -e "$DEST/athan.wav" ]]; then
    cp -- "$SOURCE/athan.wav" "$DEST/athan.wav"
  fi
  if [[ -d "$SOURCE/assets" ]]; then
    mkdir -p -- "$DEST/assets"
    cp -an -- "$SOURCE/assets/." "$DEST/assets/"
  fi
  # The old top-level Lua, conf and worker copies are superseded by the
  # organized layout. Do not leave ambiguous duplicates in the install root.
  rm -f -- "$DEST"/{Prayer_Times,Hijri_Date,Weather,Sun_Moon_Astrolabe,Settings,Surface,Hover_State,Prayer_Data,Weather_Data}.lua
  rm -f -- "$DEST"/{conky_prayer_times,conky_date,conky_weather,conky_sun_moon}.conf
  rm -f -- "$DEST"/{prayer_fetch,weather_fetch,layout}.py
fi
# Retired compatibility scripts are never launched or installed.
rm -f -- "$DEST/upgrade_settings.py" "$DEST/restart_new.py"
chmod +x "$DEST/start.sh" "$DEST/install.sh" "$DEST/configure.py" \
  "$DEST/restart.py" "$DEST/doctor.py" "$DEST/workers/prayer_fetch.py" "$DEST/workers/weather_fetch.py"
if [[ "$make_autostart" == 1 ]]; then
  mkdir -p -- "$AUTOSTART"
  escaped_dest="${DEST//\\/\\\\}"
  escaped_dest="${escaped_dest//\"/\\\"}"
  cat > "$AUTOSTART/conky-prayer-clock.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Conky: Prayer, Hijri, Weather and Celestial Astrolabe
Comment=Launch the four transparent Conky widgets
Exec=/bin/bash "$escaped_dest/start.sh" --delay 5
TryExec=conky
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP
  echo "Installed KDE/XDG autostart entry: $AUTOSTART/conky-prayer-clock.desktop"
fi
echo "Installed four widgets in: $DEST"
echo "Optional Athan audio: $DEST/athan.wav or $DEST/assets/athan.wav"
# Conky draws source-traced Cairo paths. Original PNGs are optional
# development references and are no longer required to render weather.
if [[ "$run_wizard" == 1 && -t 0 ]]; then
  printf '\nConfigure location, font, scale and placement for all four now? [Y/n] '
  read -r answer || answer=n
  if [[ ! "$answer" =~ ^[nN] ]]; then
    python3 "$DEST/configure.py" --widget all
  fi
else
  echo "Placement wizard: python3 '$DEST/configure.py' --layout --widget all"
fi
echo "Validate: python3 '$DEST/configure.py' --check"
echo "Start all: bash '$DEST/start.sh'"
echo "Safe restart all: python3 '$DEST/restart.py'"
