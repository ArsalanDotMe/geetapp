## Discover category feed, 22 October 2026

final result: passed with recorded limits

This section reviews the first selected Discover concept and supersedes the older single-featured-card Discover findings above. The earlier Library and branding review is retained.

Source visual truth: `Design/References/discover-shelves-selected.png`, the first image displayed in the two-concept exploration. Implementation: `Design/Validation/Discover/shelves-light.png` and `shelves-dark.png`. The source is 1029 × 1528 pixels including exterior padding; its panel crop is (64, 14)–(967, 1518). Native captures are 952 × 1572 pixels, with a 900 × 1520 pixel app-content crop at (26, 26)–(926, 1546), representing 450 × 760 points at 2× density. Each panel was normalized independently to 450 pixels wide without warping. `build/discover-evidence/comparison-light-final.png` contains the full-view comparison; `comparison-shelf-final.png` contains readable shelf crops in the same comparison input.

State: Discover root, light appearance, bundled design-preview fixtures and fixed player. `category-live.png` captures a category using the live R2 feed and provider thumbnails. Additional captures in `build/discover-evidence/` cover dark appearance, a 450 × 560 point viewport, and a ten-item category in a five-category fixture with its optional subtitle omitted.

Findings and fixes:

- P2 resolved: initial shelf frames clipped item type labels. Measured card heights were corrected, then covers were made 164 × 123 points with a 190-point shelf. Evidence: `shelves-light.png` exposes complete first-shelf metadata and a clear continuation of the next shelf.
- P2 resolved: initial two-line reserved titles and full-height transport reduced browsing density. Shelf titles now use one line with full-title help; the category grid retains two lines. Discover uses a compact fixed transport, preserving the existing full transport on other screens. Evidence: the final full-view and focused comparison.
- P2 resolved: hidden native shelves and root navigation were initially exposed behind a category page. Native shelf visibility and accessibility are now explicitly hidden during category navigation, and root buttons are hidden from the accessibility tree. A fresh final tree contains Back and only the selected category's item controls. Evidence: `build/discover-interaction/evidence/category-final-tree.json`.
- P2 resolved: applying an identifier to the category container initially overrode the Back button's identifier. The container now defines a contained accessibility group. The Back action is independently available and was invoked successfully.

Required fidelity surfaces:

- Typography: real bundled Newsreader headings use the existing CoreText variation setup; SF system text remains readable at 14/12/11 points. One-line shelf truncation is intentional; detail cards provide more room.
- Spacing/layout: the 450-point native shell is preserved. Landscape shelves show two complete items plus a clipped next item; category pages use a two-column grid. Vertical clipping at the feed boundary represents scroll continuation and never covers the fixed player. The shorter-window capture retains all persistent controls.
- Colors/tokens: existing dynamic Mist & Slate tokens are retained in light and dark appearances. Native materials follow macOS rendering, rather than reproducing the generated mock's painted glow.
- Image quality/assets: supplied project artwork grounds design-preview captures. Actual feed items use provider-supplied thumbnails, as shown by the live category capture. The real text-free Listener vector and system icons are preserved. No screenshot is used as the interface.
- Copy/content: arbitrary category titles and optional subtitles are supported. Radio, Mix, and Playlist remain distinct. Content now uses verified public sources instead of the mock's illustrative titles. Play previews; Add is a separate action.

Earlier runtime validation: 42 tests in 12 suites passed. A fresh native acceptance run played, paused, and resumed a radio, mix, and playlist without adding to or selecting a library collection. Persisted documents stayed empty until explicit Add; that action preserved the active preview identity and native queue, avoided duplicate saves, and survived relaunch. Pending preview cancellation also passed. See `Design/Validation/Discover/playback-acceptance.json`.

Native accessibility actions verified horizontal scrolling to offset 102 points and Back preserving that offset. A fresh category tree excludes hidden root controls and unrelated items. Public R2 delivery returned valid HTTP 200 JSON with the configured revalidation policy and ETag, and returned HTTP 304 for an unchanged feed. The release build and strict deep ad-hoc signature verification pass.

Owner acceptance, 22 October 2026: the owner reported that mouse dragging does not work and requested that all further UI checks be performed manually by the owner. The failed pan recognizer has been replaced with app-local mouse event handling that measures pointer displacement directly, clamps horizontal scrolling, and sends clicks to SwiftUI only when no drag has occurred. Movement beyond the drag threshold cancels Play/Add activation, including when the pointer later returns to its start. Vertical movement also cancels the click without shifting the shelf. The temporary gesture/event diagnostics were removed.

Non-UI validation: the full suite passes with 47 tests, including three focused drag-state checks for click tolerance, horizontal bounds and returning to the start, and vertical cancellation. The release build passes strict deep ad-hoc signature verification. On 22 October 2026 the owner confirmed that dragging now works. No further mouse input, UI captures, or UI automation was performed after the owner's request to skip UI checks. Full keyboard traversal, VoiceOver, and changed system accessibility preferences remain untested in this pass.

Final commit validation: the isolated staged source passes 43 tests in 12 suites and builds in debug and release configurations. The release bundle passes strict deep ad-hoc signature verification and embeds the configured R2 endpoint. Unrelated uncommitted tests and visual changes are excluded from that snapshot. The publisher successfully backed up and republished the 3-category, 9-item manifest, with a byte-identical HTTP 200 download and a conditional HTTP 304 response.
