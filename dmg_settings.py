"""dmgbuild settings for NOVAViewer-mac.dmg"""
import os

application = defines.get("app", "dist/NOVAViewer.app")  # noqa: F821
appname     = os.path.basename(application)

files    = [application]
symlinks = {"Applications": "/Applications"}
background = "assets/dmg_bg.png"

window_rect = ((200, 120), (660, 400))
icon_size   = 128
text_size   = 13

icon_locations = {
    appname:       (165, 185),
    "Applications": (495, 185),
}
