# geet Listener assets

The geet logo is the Listener portrait alone. No text or wordmark is part of the logo or app icon.

## Files

- `svg/geet-logo.svg`: tightly fitted vector symbol that inherits `currentColor`.
- `svg/geet-logo-{ink,forest,ivory,black,white}.svg`: fixed-color, transparent vector symbols with clear space.
- `png/geet-logo-*-{512,1024,2048}.png`: transparent PNG exports.
- `pdf/geet-logo-*.pdf`: vector PDF exports.
- `svg/geet-app-icon.svg`: macOS app icon, ivory rounded tile with a forest portrait and transparent outer canvas.
- `png/geet-app-icon-{1024,2048}.png`: macOS icon master exports.
- `svg/geet-app-icon-unmasked.svg` and its PNG: full-bleed square artwork for surfaces that apply their own mask.
- `macos/Geet.icns` and `macos/Geet.iconset/`: native Mac icon and the complete standard iconset, from 16 to 1024 pixels.
- `macos/geet-menu-bar-template.pdf` and PNGs: monochrome template artwork at 18 points, with 1x and 2x PNGs. Set `isTemplate = true` when using these with AppKit.
- `preview.png`: the symbol in light and dark treatments, app icon, small icon exports, and menu bar samples at native dimensions. No wordmark appears in this preview.
- `manifest.json`: palette, export details, sizes, and file hashes.
- `typography/Newsreader.ttf`, `typography/OFL.txt`, and `typography/tokens.json`: the selected brand font, its license, and typography settings.

The build inputs at `Design/Assets/app-icon.png` and `Sources/Geet/Resources/Geet.icns` use this icon. The menu bar loads the vector template from `Sources/Geet/Resources/GeetMenuBar.pdf` at 18 points and marks it as a template so macOS supplies the appropriate color for the current appearance.

## Use

Use ink or forest on a light background, and ivory or white on a dark background. Preserve the transparent negative space in the face and headphones. The square fixed-color logos include a 64-unit clear-space inset on a 1024-unit canvas. Keep this clear space when placing the symbol beside other content.

Use the rounded macOS icon with its existing outer transparency for Mac application bundles. Use the unmasked version only where the destination provides the icon mask. Don't crop a second rounded tile around the macOS export.

Small versions preserve the recognisable head, bob, and headphones; some facial and hair detail naturally disappears at 16 to 18 pixels. Use the logo at larger sizes when that detail matters.

## Palette

| Color | Value |
| --- | --- |
| Ink | `#20211C` |
| Ivory | `#F4F0E7` |
| Forest | `#355A48` |
| Amber, supporting artwork only | `#C19A63` |

## Typography

Newsreader Regular, weight 400, is geet's brand typeface. Use it for the brand name and editorial headings with normal letter spacing. Large display work uses optical size 72; smaller text uses an optical size matching its point size, within 6–72.

The main window header has no app-name label. In the app, branded headings use 24 points for editorial messages and 28 points for the support headline. Controls, menus, settings labels, playlist rows, and body text use the native macOS system font. The bundled font is loaded lazily when a branded heading is displayed.

Brand typography is separate from the symbol. The logo and all icon exports remain text-free. See the [brand guide](../README.md) for the overall identity.

## Source and reproduction

The source is a built-in ImageGen refinement of the approved [Listener concept](../Exploration/04-listener.png). The initial extraction included an unused wordmark. Only the isolated portrait was retained for this asset package, following the request for a text-free logo. The exact generation prompt is in `source/generation-prompt.txt`.

`source/listener-symbol.png` is the isolated raster portrait. `source/listener-traced.svg` is its Potrace trace. The deliverable SVGs contain filled vector paths and require no fonts, network access, or embedded bitmap artwork. The app icon additionally uses an SVG shadow filter.

To reproduce the exports and update the app-icon and menu-bar build inputs:

```sh
python3 Design/Branding/Listener/export-assets.py
```

This requires Python 3, `rsvg-convert`, and macOS `iconutil`. The source trace can be regenerated with ImageMagick and Potrace if the raster master changes. No Python packages are required by the export script.
