# geet typeface comparison

Newsreader was selected as geet's brand typeface. Use the [brand guide](../README.md) and [selected font package](../Listener/typography/) for current typography decisions. This comparison is retained as the selection study.

`geet-typeface-comparison.png` shows the actual font outlines side by side. The SVG is also self-contained, with all sample lettering and labels converted to vector paths. There are no fallback fonts or generated approximations in either output.

All three samples use a nominal size of 200 and regular weight 400, in ink `#20211C` on ivory `#F4F0E7`. They share the same baseline and have no added tracking. Each word is centered in a column of equal width. Their natural differences in width and height are preserved.

Fraunces uses optical size 72, softness 50, and wonk 1. Newsreader uses optical size 72. Instrument Serif is the regular static font. These are display settings intended for comparing brand typography; other Fraunces settings can change its appearance considerably.

Font files and their OFL licenses are retained in `fonts/`. Sources:

- [Instrument Serif, Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/instrumentserif)
- [Fraunces, Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/fraunces)
- [Newsreader, Google Fonts repository](https://github.com/google/fonts/tree/main/ofl/newsreader)

To regenerate on macOS with Swift and `rsvg-convert`:

```sh
swift -module-cache-path /private/tmp/geet-typography-module-cache Design/Branding/Typography/render-comparison.swift "$PWD/Design/Branding/Typography"
rsvg-convert --output Design/Branding/Typography/geet-typeface-comparison.png Design/Branding/Typography/geet-typeface-comparison.svg
```

This comparison does not change the app or its symbol-only logo.
