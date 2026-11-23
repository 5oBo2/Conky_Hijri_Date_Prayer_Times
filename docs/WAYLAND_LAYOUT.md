# Historical native Wayland layout experiment (superseded)

This file is kept only because older saved profiles and roadmap entries refer
to this path. The output-local layout experiment did not reliably place Conky
1.24.2 widgets on the user's two KDE Wayland monitors.

**Current architecture and migration gate:**
[Native Wayland migration decision](NATIVE_WAYLAND_MIGRATION.md).

**Current command:** `python3 configure.py --reflow-layout --widget all`
uses saved output/anchor intent to regenerate X11/XWayland global positions.
