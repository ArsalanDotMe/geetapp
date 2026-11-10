# geet landing page

Static HTML and CSS with a small progressive-enhancement script for feature animations. No runtime framework, analytics, or external font requests.

Preview from the repository root:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

Open http://127.0.0.1:4173. Production is https://geet.mashaltech.ee, deployed to the `geet-website` Cloudflare Worker in the existing account.

```sh
python3 scripts/prepare-website.py
node --test website/worker.test.mjs
npx --yes wrangler@4.152.0 deploy --config website/wrangler.jsonc
```

Wrangler uses the maintainer's existing local login. If it expires, run `npx --yes wrangler@4.152.0 login` and complete authentication yourself before deploying. Only the generated `website/dist/` directory is served. The Worker route preserves `/discover/*` through the existing `geet-discover` R2 binding, including ETags and conditional refreshes. Keep the R2 custom domain enabled as the origin for this route. Do not replace or delete the feed when deploying the site.

The page uses the native app's Mist & Slate tokens from `Sources/Geet/DesignSystem.swift`, self-hosted Newsreader, the text-free Listener portrait, and real native Library and Discover captures. Light and dark appearances follow the system. The Listener stays still while slow CSS ripples animate behind it. Reduced motion disables the animation. Navigation and FAQ disclosures work without JavaScript.

The hero Download button uses an Apple logo from Phosphor, with the included license, and points to the latest release's `geet-apple-silicon.dmg` asset. GitHub links point to the public `ArsalanDotMe/geetapp` repository. Publish and verify the release before deploying the site.

Individual sections cover adding playlists, Discover, media keys, and ad-free listening. The media-key and waveform illustrations loop while visible, pause off-screen, and respect reduced motion. The footer credits Mashal Tech and links to its official website. The separate marketing videos live in `demo-animation/out/` and are not shipped with the site.

Three Astra reviewers visually critiqued every section against desktop and mobile captures. Review artifacts are in ignored `review/`.

The ad-free illustration uses self-hosted SiriWave 2.4.0, classic (`ios`) style, with three curves in the current theme's accent colour. Source: https://github.com/kopiro/siriwave. The upstream MIT license is included at `assets/vendor/siriwave-LICENSE.txt`. It pauses outside the viewport and when the page is hidden; reduced motion shows a static SVG. No audio or microphone is used.
