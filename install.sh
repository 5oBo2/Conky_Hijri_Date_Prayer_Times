#!/usr/bin/env bash
# Install the four-widget project exactly as supplied; no migrations or aliases.
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
  files=(
    Prayer_Times.lua Hijri_Date.lua Prayer_Data.lua Surface.lua
    Hover_State.lua Settings.lua prayer_fetch.py
    Weather.lua Weather_Data.lua weather_fetch.py Sun_Moon_Astrolabe.lua
    conky_prayer_times.conf conky_date.conf conky_weather.conf conky_sun_moon.conf
    configure.py layout.py doctor.py start.sh restart.py install.sh
    settings.ini README.md HOVER_ZONE.md
  )
  for filename in "${files[@]}"; do
    cp -- "$SOURCE/$filename" "$DEST/$filename"
  done
  if [[ -f "$SOURCE/athan.wav" ]]; then
    cp -- "$SOURCE/athan.wav" "$DEST/athan.wav"
  fi
  mkdir -p -- "$DEST/assets"
  cp -a -- "$SOURCE/assets/weather" "$DEST/assets/"
fi
# Retired scripts are not part of the current project and are never run.
rm -f -- "$DEST/upgrade_settings.py" "$DEST/restart_new.py"
chmod +x "$DEST/start.sh" "$DEST/install.sh" "$DEST/configure.py" \
  "$DEST/restart.py" "$DEST/doctor.py" "$DEST/prayer_fetch.py" "$DEST/weather_fetch.py"
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
echo "Optional Athan audio: $DEST/athan.wav"
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
