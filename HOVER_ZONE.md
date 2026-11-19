# Fajr/Sunrise hover zone

Hovering over the small region containing the Fajr and Sunrise headings shows elapsed time since the last Athan, even after the automatic elapsed-time period ends. Moving away from this zone within Conky clears the hover immediately on the next mouse event. On KDE Wayland, a missed window-leave event can still leave it visible until `hover_failsafe_seconds` expires. A stationary pointer also times out with this fallback.

The complete package defaults to:

```ini
[behavior]
hover_area = fajr_sunrise
hover_debug_outline = no
hover_failsafe_seconds = 1
elapsed_minutes = 60
```

This original Archive.zip behavior is preserved in the unified installation. Adjust the `[behavior]` keys in your shared `settings.ini` or run `python3 configure.py --widget prayer`.

To visualize the exact active zone temporarily, set `hover_debug_outline = yes`, restart prayer Conky and look for the red outline. Turn it back to `no` after confirming.

Restart only the prayer widget with `python3 restart.py --widget prayer`, or log out and back in. You do not need to touch your KDE Autostart entries or `athan.wav`.

## Checking the screen layout

`python3 ~/.config/conky/configure.py --check-layout` validates `fajr_sunrise` and prints estimated widget rectangles. `--layout` runs the placement assistant, and `--manual-screens` accepts monitor coordinates if KScreen cannot report them. See README.md for the complete instructions.
