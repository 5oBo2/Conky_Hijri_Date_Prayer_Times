# Weather icon comparison probe

The probe is a temporary, full-screen Conky window for reviewing every weather
icon against its original artwork. Each tile shows the **original PNG on the
left** and the **production Cairo vector renderer on the right**. The vector
side uses the current `appearance.next_prayer_color` for sun/moon contours.

## Launch

From the project root:

```bash
python3 tools/weather_icon_probe.py
```

The launcher detects the primary XRandR monitor (or the X display bounds) and
opens a borderless, opaque Conky window over that screen. It does not modify
`settings.ini`, the original PNGs, or the normal widget configs.

Click the **CLOSE** control in the upper-right corner, or close it from a terminal:

```bash
python3 tools/weather_icon_probe.py --stop
```

If automatic screen detection is unavailable, supply dimensions explicitly:

```bash
python3 tools/weather_icon_probe.py --width 1920 --height 1080
```

For a monitor that is not at the top-left of the X screen, optional `--x` and
`--y` offsets can be supplied.

## Requirements

- Conky with the same X11/XWayland Cairo support as the regular widgets.
- `assets/weather/*.png` originals. The production weather widgets do not need
  these PNGs at runtime, but this comparison probe deliberately loads them.
- `lib/Weather_Icon_Paths.lua` and `lib/Weather_Icons.lua` for the vector side.

The probe displays all 20 source icon IDs in four columns and five rows. The
original and vector renderings use the same 256x256 coordinate system and are
scaled to the same display size. The PNG remains white; the Cairo renderer
uses the configured celestial accent, making both shape fidelity and color
behavior easy to inspect.

Logs are written to `~/.cache/conky-prayer-times/weather-icon-probe.log`.
