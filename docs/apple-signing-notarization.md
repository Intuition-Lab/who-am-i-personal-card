# Apple Developer ID signing and notarization

The formal GitHub Release path signs the fully assembled `Who Am I.app`, signs
the final DMG, submits that DMG to Apple's notary service, staples the accepted
ticket, and runs Gatekeeper assessment before calculating release checksums.
Development and pull-request builds remain ad-hoc signed and never claim to be
notarized.

## Reviewed signing topology

The distributed App currently contains one universal `arm64`/`x86_64` Mach-O
executable and no nested `.app`, framework, XPC service, extension, plug-in,
dynamic library, or `.so`. `scripts/sign-macos-release.sh` refuses a newly
introduced nested-code topology until an explicit inner-first signing rule is
reviewed.

The approved entitlements file is
`apps/personal-card/macos/WhoAmI.entitlements`. It is intentionally empty. The
App is not sandboxed, Node and Persome run as owner-local external processes,
and the launcher does not need JIT, unsigned executable memory, debugger,
library-validation, iCloud, camera, microphone, contacts, or network-client
entitlements. Accessibility and Screen Recording consent belongs to the local
Runtime onboarding flow; signing does not grant those permissions.

The immutable release order is:

1. compile the universal Swift launcher with an ad-hoc development signature;
2. embed the complete verified product and pinned Runtime payload;
3. generate and verify the embedded payload manifest;
4. apply the final Developer ID App signature with hardened runtime and secure
   timestamp;
5. generate the outer package manifest and equivalent tar archive;
6. create and Developer ID sign the DMG;
7. submit the DMG with `notarytool --wait`, require `Accepted`, staple and
   validate the ticket;
8. verify App and DMG signatures with `codesign --deep --strict`, assess both
   with `spctl`, and verify the disk image with `hdiutil`;
9. calculate the final release SHA-256 values after stapling.

No file in the signed App or final DMG may be changed after its applicable
signature. No release checksum may be calculated before notarization and
stapling finish.

## GitHub Environment configuration

The `build` and `publish` jobs use the protected `github-release` Environment.
Keep its existing independent reviewer and tag restrictions. Add these
Environment secrets:

| Name | Value |
| --- | --- |
| `APPLE_DEVELOPER_ID_P12_BASE64` | Base64 of a Developer ID Application certificate plus private key exported as `.p12` |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | Export password for that `.p12` |
| `APPLE_SIGNING_KEYCHAIN_PASSWORD` | Random one-run password used for the temporary CI keychain |
| `APPLE_NOTARY_API_KEY_BASE64` | Base64 of the App Store Connect notary API private key (`AuthKey_*.p8`) |
| `APPLE_NOTARY_KEY_ID` | Ten-character App Store Connect API key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect API issuer UUID |

Add these Environment variables; they are identities, not credentials:

| Name | Value |
| --- | --- |
| `APPLE_SIGN_IDENTITY` | Exact `Developer ID Application: Legal Name (TEAMID)` certificate name |
| `APPLE_TEAM_ID` | Ten-character Apple Developer Team ID |

Use an App Store Connect API key authorized for notarization. Do not use an
Apple ID password or app-specific password in the workflow. Do not store the
certificate, private key, passwords, API key, or temporary keychain as a GitHub
artifact, cache, release file, repository secret, log attachment, or support
bundle.

## Certificate preparation

On a trusted Mac, create or download the Developer ID Application certificate
for the approved Team. Export only that certificate and its private key from
Keychain Access as a password-protected `.p12`. Base64-encode the file without
line wrapping and store the result directly as the Environment secret. Create
an App Store Connect API key for notarization, download its `.p8` once, encode
it the same way, and store its key ID and issuer ID separately.

`scripts/build-notarized-release-assets.sh` performs the ephemeral CI import:

- decodes both private artifacts into an owner-only temporary directory;
- creates and unlocks a new temporary keychain;
- imports the `.p12` with access restricted to Apple signing tools;
- validates that the configured identity exists in that keychain;
- stores and validates a one-run `notarytool` keychain profile;
- builds, signs, notarizes, staples, and verifies the exact five assets;
- deletes the temporary keychain and temporary private-key files on success,
  failure, signal, or cancellation handled by the shell trap.

GitHub-hosted macOS runners are ephemeral, but cleanup is still mandatory. A
self-hosted runner must additionally verify after every run that the temporary
keychain path and decoded `.p12`/`.p8` files no longer exist. Rotate the
certificate or API key immediately if a runner, log, cache, artifact, or
account is suspected to be compromised.

## Local verification and fail-closed behavior

Pull requests run the ad-hoc package path and the signing failure-path tests.
They cannot prove Apple trust. A tag release invokes the notarized wrapper and
stops before building when any Environment value is absent. It also stops when
the certificate identity, Team ID, hardened-runtime flag, notary response,
stapled ticket, Gatekeeper assessment, or DMG structure is wrong.

The following commands are required against the final artifact and are already
run by the scripts and Release workflow:

```bash
codesign --verify --deep --strict "Who Am I.app"
codesign --verify --strict who-am-i-<version>-self-contained-macos.dmg
xcrun stapler validate who-am-i-<version>-self-contained-macos.dmg
spctl --assess --type open --context context:primary-signature \
  who-am-i-<version>-self-contained-macos.dmg
```

`security find-identity -v -p codesigning` must show a valid Developer ID
Application identity before a real local signing run. A machine with zero valid
identities can exercise only the ad-hoc and fail-closed tests; it must not mark
the real signing/notarization checklist item complete.

## Installed-App boundary

The downloadable App inside the DMG is the Developer ID signed and notarized
artifact covered by this pipeline. The current installer later builds an
owner-specific `~/Applications/Who Am I.app` locally because its Info.plist
contains owner-local product paths; that generated App remains ad-hoc signed.
Do not claim that the installed App is Developer ID signed until the launcher
is made path-independent and the release ships a pre-signed installed-App
payload. This architecture item is separate from, and not concealed by, the
downloadable-artifact notarization result.
