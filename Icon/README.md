# Gramkey app icon

**Concept:** stacked keycaps with a ⌃ (Control) caret, read as "keyboard" plus "shortcuts". The caret is *cut out* of the front keycap and a gap separates the two keycaps, so the silhouette survives in clear and tinted modes.

| File | What |
|---|---|
| `02-keycap-back.svg` | amber back keycap (#FF9F0A), with a 28px gap around the front keycap |
| `03-keycap-front.svg` | white front keycap (#F5F5F7) with the caret knocked out |
| `preview-sheet.png` | default / dark / clear / tinted, plus the 180→29px size ladder |
| `../App/Assets.xcassets/AppIcon.appiconset` | flattened 1024 PNG used by the build today |

Layers are generated geometry, not hand-drawn: edit `build_icon.py`, then run `pip install shapely && python3 Icon/build_icon.py Icon`.

## Icon Composer setup card (optional Liquid Glass upgrade)
```
File: AppIcon.icon          Platforms: iOS
Background: Gradient #3A3D4F → #15161E (top → bottom)
Groups (back→front):
  G1 Back key:  02-keycap-back.svg  | Mode Individual | Specular Automatic | Blur off | Translucency 20% | Shadow Chromatic
  G2 Front key: 03-keycap-front.svg | Mode Individual | Specular Automatic | Blur off | Translucency 0%  | Shadow Neutral
Dark:   bg #2A2C3A → #0E0F15, back key #FF9F0A, front key #E5E5EA
Mono:   verify silhouette in clear light/dark + tinted (caret cut-out and the key gap must stay visible)
Check:  Effects 26 vs 27 toggle; grid overlay; preview sizes; device wallpaper backgrounds
```
To switch: save `AppIcon.icon` next to `project.yml`, add it to the app target's sources, and keep `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`. Xcode back-generates icons for iOS < 26, so the asset catalog can then be removed.
