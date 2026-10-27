#pragma once

#include <QIcon>
#include <QPixmap>

// Takedawn's icon: the project's own artwork (assets/icon, the crimson T on the
// navy panel). The build renders the SVG to PNGs (render_icon.py, 16 to 512
// pixels) and compiles them in; no rendered image is kept in the repository.

// The window and application icon, with every size.
QIcon AppIcon();

// The icon `logical` device-independent pixels square, for a screen of that
// device pixel ratio: scaled from the nearest larger size.
QPixmap AppIconPixmap(int logical, qreal device_pixel_ratio);
