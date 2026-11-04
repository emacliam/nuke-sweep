# Nuke Sweep showcase

Static HTML/CSS/JS. No build dependencies, account system, forms, analytics, or cookies. Real app screenshots and approved branding are local assets. Instrument Sans is self-hosted with its SIL license.

- Production URL: https://sweep.zyncraft.com
- Vercel project: nuke-sweep, emacliams-projects team
- GitHub source: https://github.com/emacliam/nuke-sweep
- Root directory: `website`
- Framework preset: Other / no framework
- Build command: none
- Output directory: `.`

Run locally from the repository root:

```sh
python3 -m http.server 4173 --directory website
```

## Release updates

1. Build and test the app with the approved branding.
2. Sign with Developer ID, submit to Apple, and staple/validate the app and DMG.
3. Copy the final notarized DMG into `downloads/`.
4. Update `downloads/SHA256SUMS.txt` from that exact file.
5. Update version, requirements, release notes, download paths, and structured metadata in `index.html`, the root README, and release notes together.
6. Verify the hosted DMG hash matches the local approved file.

The screenshot tabs support arrow, Home and End keys. Navigation includes a mobile menu and Escape dismissal. FAQs use native details. Motion respects reduced-motion preferences. `privacy.html` documents actual app and website behavior.

## Asset provenance

`cleanup.png`, `developer.png`, and `widgets.png` are captures of the real Nuke Sweep 0.8.1 app. The mark and icon derive from the user-approved Nuke Sweep identity in `branding/nuke-sweep`. Fonts originate from Google Fonts and are served locally.

## Version 0.8.2 distribution verification

- App notarization: `33530095-5e01-4885-adcf-894789bc11f1` — Accepted.
- DMG notarization: `69d57035-4781-407f-9991-d5a711ea5a89` — Accepted.
- Both tickets stapled and validated; Gatekeeper reports Notarized Developer ID.
- DMG SHA-256: `28b086a1987215a42935812bcd9fe5b6acb361552007610026e4af9e8e6b15ab`.
- Download and release copy updated together. The screenshots retain the 0.8.1 capture provenance above; the 0.8.2 cleanup workflows are described in the linked developer guide and release notes.
