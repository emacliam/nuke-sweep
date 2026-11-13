# Signing and notarization

## Current state (4 November 2026)

Installed distribution identity:

```
Developer ID Application: ZYNCRAFT TECHNOLOGIES (PRIVATE) LIMITED (MS3CH542QN)
Team: MS3CH542QN
Expires: 3 December 2027
```

Nuke Sweep 0.8.1 (build 9) applies the approved name and icon. It retains `local.nuke.mac` and `local.nuke.mac.widgets`, existing preference keys, widget kinds and local history paths. The current release is built and Developer ID signed. App/extension signature verification, DMG signature verification, bundle plist validation, and DMG checksum verification pass. All 106 existing tests pass. Native visual checks confirm the compact sidebar, monitor popover, and widget preview, and existing history loads correctly.

Current artifact: `dist/Nuke-Sweep-0.8.1.dmg`

SHA-256: `0d88309050b818ac85900deeba98d5974760a3fcf881efc3ff83f17c4477ca3c`

Apple accepted the rebranded 0.8.1 app and DMG on 4 November 2026. Both have stapled, validated tickets. Gatekeeper accepts both as `Notarized Developer ID`.

- App submission: `6b963982-06a3-4822-93f0-bbe976bbb0ff`
- DMG submission: `9e65d3ff-18da-4857-bac1-e17aba07e687`


Previous Nuke 0.8.0 accepted submissions:

- App: `c4592204-234f-4ecd-97a2-99524f460a3f`
- DMG: `6566cf8b-7b73-4cbe-9eaa-38d987224b7d`

The `nuke-notary` keychain credential profile is configured.

## 1. Install a Developer ID Application certificate

1. Enroll in the Apple Developer Program with the team that owns `MS3CH542QN`.
2. In Xcode → Settings → Accounts → select the team → Manage Certificates → **+** → **Developer ID Application**.
3. Confirm it is present:

```sh
security find-identity -v -p codesigning
```

Look for `Developer ID Application: ZYNCRAFT TECHNOLOGIES (PRIVATE) LIMITED (MS3CH542QN)`. The team ID for a Developer ID certificate can differ from the Apple Development team display above; use the exact identity string `codesign` reports.

## 2. Store notary credentials in the keychain

Create an app-specific password at <https://appleid.apple.com> (Sign-In and Security → App-Specific Passwords). Then run, in your own Terminal:

```sh
xcrun notarytool store-credentials "nuke-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

Do not paste the password into chat or commit it. The profile lives in your login keychain.

## 3. Build, sign, notarize

```sh
export NUKE_SIGN_IDENTITY="Developer ID Application: ZYNCRAFT TECHNOLOGIES (PRIVATE) LIMITED (MS3CH542QN)"
export NUKE_NOTARY_PROFILE="nuke-notary"
./scripts/build-app.sh
./scripts/build-dmg.sh
```

The scripts:

- sign the widget extension and app with Hardened Runtime and, for Developer ID identities, a secure timestamp;
- submit a zip of the app to `notarytool`, wait, staple and validate the app;
- create and sign the DMG;
- submit the DMG, wait, staple and validate it;
- run `spctl` on the DMG.

## 4. Verify

```sh
codesign --verify --deep --strict "dist/Nuke Sweep.app"
spctl -a -vv "dist/Nuke Sweep.app"
hdiutil verify dist/Nuke-Sweep-0.8.1.dmg
spctl -a -t open --context context:primary-signature -vv dist/Nuke-Sweep-0.8.1.dmg
```

Expected: `accepted`, `source=Notarized Developer ID`.

## Notes

- Hardened Runtime is enabled for real identities. Nuke needs no JIT, injection or disabled-library-validation entitlement.
- The widget extension keeps its app-sandbox entitlement.
- Notarization is an online service. First launch on another Mac may need network access for the ticket; stapling avoids that for the app and DMG.
- If you rotate the certificate or password, recreate the `nuke-notary` profile.


## Release verification

Run `./scripts/verify-release.sh --strict path/to/Nuke-Sweep-VERSION.dmg`. It mounts the DMG read-only and verifies the embedded app and widget, matching Developer ID teams, Gatekeeper acceptance, stapled tickets, and the adjacent SHA-256 file. A checksum from a release host can also be supplied as the second path.

To stage a new version separately, set `NUKE_APP_PATH`, `NUKE_VERSION`, and `NUKE_BUILD_NUMBER` before building the app. Keep `NUKE_APP_PATH` set and use `NUKE_DMG_PATH` for the new DMG. The DMG script writes a sibling checksum and refuses to overwrite either output.

## Upgrading from 0.8.x to 0.9.0

The production identifiers are `com.zyncraft.nukesweep` and `com.zyncraft.nukesweep.widgets`. On first launch the app copies missing Nuke preferences from the previous domain. Receipts and scan history stay in `~/Library/Application Support/Nuke`. Existing destination preferences take precedence. Development builds keep their own data.

macOS may ask for folder access, Full Disk Access, notifications, or Keychain access again. Launch the new signed build once before adding its Storage widget. If an existing widget still points at the old extension, remove that widget and add Storage again from Edit Widgets. A signed extension and valid notarization ticket establish package integrity. They do not verify gallery discovery or live widget rendering.

## Sparkle updates

Sparkle starts in a production build when the bundle contains its Ed25519 public key and HTTPS feed URL. The Updates page offers a manual check and a preference for background checks. Installation is user initiated.

1. Run SwiftPM resolution, then use `.build/artifacts/nuke/Sparkle/bin/generate_keys --account com.zyncraft.nukesweep -p` to retrieve the established public key. Keep the private key in Keychain and maintain a secure recovery backup.
2. Check that the returned key matches the public key in `scripts/build-app.sh`. Build with a new `NUKE_VERSION` and an increased `NUKE_BUILD_NUMBER`. Sign and notarize the app and the DMG using the existing release scripts.
3. Put the verified installer and optional matching release notes in a staging directory. Preserve any previous update archives and feed entries that should remain available. Run `./scripts/generate-appcast.sh staging-directory`.
4. Publish the archive under `website/downloads/` and the generated feed under `website/updates/appcast.xml`. Publish generated delta archives alongside their full archives if the feed references them. Regenerate signatures after changing the feed or signed notes.
5. On a test Mac, install the previous Sparkle-enabled build and check for updates from Settings. Verify the update installs, relaunches, and preserves existing preferences and history.

The 0.9.0 release predates Sparkle. Its existing Updates page sends users to GitHub for the first Sparkle-enabled installer.
