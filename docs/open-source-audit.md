# Open-source publication audit

Reviewed on 2026-10-23, starting at commit `cb18944`. The original history has
18 commits, one branch, and no tags. GitHub's remote refs were checked as well
as local refs. The existing history is retained.

- Gitleaks 8.30.1 scanned all 18 commits with `--all --full-history`; no secrets
  were detected. The previously untracked website was scanned separately with
  the same result. A final scan is required after staging publication changes.
- Historical paths and text evidence were reviewed for credentials, local
  secrets, signing files, private links, and personal app data. No credential
  files or user-library database were tracked. Validation records explicitly
  exclude the owner's unlisted playlist URL and identifier.
- An additional scan covered all 529 historical objects for access-bearing URL
  parameters and private-key headers. The only match was deliberately fake
  diagnostic text in `ListenerMessageTests.swift`. Archive-aware Gitleaks
  scanning also completed without findings.
- Existing author name and email remain in commit metadata. Cloudflare account
  and zone identifiers and the public Discover URL are configuration, not
  credentials. They remain public as part of the deployment setup.
- Ignored `Tools/`, `.build/`, `build/`, `.wrangler/`, `.env*`, and website
  `review/` are excluded. The website's deployment stages an explicit allowlist
  so documentation, review captures, and Worker source are not served as assets.
- Added an MIT license for geet's code. Fonts and the website symbol retain
  their existing licenses. Included pinned helper licenses, complete binary
  notices, and source directions. The separate yt-dlp executable retains its
  GPL distribution terms. Third-party playlist artwork is not relicensed.
- Public release verification requires Developer ID signatures, Apple
  notarization, stapled tickets, Gatekeeper checks, mount integrity, bundled
  helper execution, and matching source/checksum metadata.

Automated secret scanning and source review reduce publication risk but cannot
prove that every possible credential format or third-party artwork right has
been identified. The audit concerns the committed repository and release
contents; ignored local app data is not published.
