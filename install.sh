#!/usr/bin/env bash
# Install one canonical 4-widget project to ~/.config/conky.
set -euo pipefail
SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/conky"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
make_autostart=1
run_wizard=1
reset_settings=0
for opt in "$@"; do
  case "$opt" in
    --no-autostart) make_autostart=0 ;;
    --no-configure) run_wizard=0 ;;
    --reset-settings) reset_settings=1 ;;
    -h|--help)
      printf 'Usage: bash install.sh [--no-autostart] [--no-configure] [--reset-settings]\n'
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
    configure.py layout.py upgrade_settings.py doctor.py
    start.sh restart.py restart_new.py install.sh
    settings.ini README.md HOVER_ZONE.md
  )
  for filename in "${files[@]}"; do
    if [[ "$filename" == settings.ini && -f "$DEST/settings.ini" && "$reset_settings" == 0 ]]; then
      echo 'Keeping your existing settings.ini (use --reset-settings to replace it).'
      continue
    fi
    cp -- "$SOURCE/$filename" "$DEST/$filename"
  done
  if [[ -f "$SOURCE/athan.wav" ]]; then
    cp -- "$SOURCE/athan.wav" "$DEST/athan.wav"
  fi
  mkdir -p -- "$DEST/assets"
  cp -a -- "$SOURCE/assets/weather" "$DEST/assets/"

fi
# Tidy a previously installed Weather-v2/Celestial folder, even if the user
# extracted this package directly into ~/.config/conky. Always back up first.
legacy=(
  Sun_Moon.lua conky_sun_moon_astrolabe.conf start_astrolabe.sh
  README_ASTROLABE.md NEW_WIDGETS.md REFINEMENT_V2.md
  Astrolabe_Preview.html Astrolabe_Preview.png
)
needs_prune=0
for old in "${legacy[@]}"; do
  [[ ! -e "$DEST/$old" ]] || needs_prune=1
done
[[ ! -e "$DEST/assets/moon" && ! -e "$DEST/assets/moon_old" ]] || needs_prune=1
if [[ "$needs_prune" == 1 ]]; then
  if [[ "$SOURCE" == "$DEST" ]]; then
    BACKUP="${DEST}-backup-$(date +%Y%m%d-%H%M%S)-$$"
    cp -a -- "$DEST" "$BACKUP"
    echo "Existing Conky folder backed up before migration: $BACKUP"
  fi
  for old in "${legacy[@]}"; do
    rm -f -- "$DEST/$old"
  done
  rm -rf -- "$DEST/assets/moon" "$DEST/assets/moon_old"
  echo 'Removed retired Sun/Moon files and version-specific notes; current README.md is canonical.'
fi
python3 "$DEST/upgrade_settings.py"
chmod +x "$DEST/start.sh" "$DEST/install.sh" "$DEST/configure.py" \
  "$DEST/restart.py" "$DEST/restart_new.py" "$DEST/doctor.py" \
  "$DEST/prayer_fetch.py" "$DEST/weather_fetch.py" "$DEST/upgrade_settings.py"
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
