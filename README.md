# Aureus Wealth Terminal

Aureus is an open-source, local-first, visualization-first personal wealth terminal for macOS. Dashboard, Wealth, Markets, Portfolio, Analytics, Ledger, Goals and Settings bring local wealth records, deterministic calculations and market visualization together. CNY is the default unified valuation currency; USD originals, applied FX and converted CNY values stay distinct. The maintained product has no AI or LLM capability.

## License and supported platform

Aureus-owned source, integration scripts and accompanying Aureus-owned documentation are under the [MIT License](LICENSE), with no additional commercial-use or hardware restriction in that license. Third-party components retain their own licenses; see [Third-Party Notices](THIRD_PARTY_NOTICES.md).

Official maintenance and binaries cover **Apple Silicon (arm64 / M-series Macs) only**, with a **macOS 14.0 minimum deployment target**. A deployment target is not proof that every supported chip or macOS version has been tested. Intel, Universal, Windows and Linux work may be explored by the community, without an official support commitment.

The maintained product's Personal Local Mode is single-user, local-only, personal/internal and non-commercial: it is not a hosted service or a vehicle for commercial display, sale or redistribution of Provider data. This describes the maintained product and Provider usage scope; it adds no restriction to the MIT source license. MIT grants no rights to third-party market data.

## Formal 1.0.0 release decision and limits

This is the **formal 1.0.0 release / build 1**, under a user-exception release decision accepting unfinished manual, performance, log-privacy and final runtime validation. It is not a preview, beta or release candidate. Overall technical evidence remains **PARTIAL**; the release decision does not turn unverified checks into technical passes.

Accepted historical Unit evidence is 502 definitions / 639 executions passed on earlier versioned inputs. Six controlled synthetic Search/History failure observations and stale/Clear observations have limited USER REPORTED acceptance. They do not establish real-network behavior or this final 1.0.0 application's runtime success. Cancel/Probe preservation, complete keyboard/VoiceOver and display-condition coverage, security-scope release counts, six performance protocols/measurements, OSLog delivery/retention/manual redaction, and final runtime validation remain limited or unverified. Some synthetic backup checks have bounded evidence; not every recovery scenario is accepted. Historical failed UI runs remain failed and are not combined with later individual passes. These known gaps are accepted for this release decision, not presented as completed tests. App launch, Unit, UI, manual QA, performance and system-log inspection were not run in this release-preparation round.

No real financial records, credentials or Provider payloads are supplied. Keep private records and backups outside source trees and public/shared folders. Backups are **not independently encrypted by Aureus**; use private storage you control with appropriate system/storage encryption. Do not keep your only backup inside the App; retain independent private copies of important records.

Twelve Data V1 processing is session-only: persistent writes are Disabled and retention rights remain BLOCKED. The isolated permanent store and recoverable market cache retain separate capacity, TTL and cleanup rules; cleanup must not delete permanent wealth records. Production credentials are entered only by the user in native Settings and stored in the application's Keychain scope. Catalog visibility or synthetic success is not proof of the user's actual Plan or endpoint × MIC permission. This release makes no new live Provider or legal-rights claim.

## Install Aureus 1.0.0

The DMG contains a locally **ad-hoc signed** App. It has **no Developer ID signature and is not notarized by Apple**. A matching checksum shows file integrity relative to that checksum, not trusted publisher identity or freedom from malware. Obtain the release and its checksum from a source you trust.

1. Compare the downloaded archives with the supplied `SHA256SUMS` (for example, run `shasum -a 256 -c SHA256SUMS` in the folder containing both archives).
2. Open `Aureus-1.0.0-macos-arm64.dmg`, review the installation and license information, then manually copy `Aureus.app` to your chosen application folder. Do not replace an existing App or private data without your own recovery plan. Eject the image before opening the installed copy.
3. macOS may block the first opening. Only if you trust the source and have checked integrity, follow the system's permitted per-app approval flow: after an attempted opening, check System Settings → Privacy & Security for **Open Anyway**, if available, and personally confirm the system prompt. Managed-device policy may prevent this. See [Apple's current safety guidance](https://support.apple.com/en-us/102445).
4. Stop if macOS reports malware, damage, tampering or an unexplained warning. Do not disable Gatekeeper, strip quarantine or bypass a malicious-software warning. System authentication must be handled by the user.

Ordinary installation and use require no QA launch arguments: open the installed App normally to use the existing Local mode. Do not use synthetic/test switches for your personal records. Some screens retain old Stage/candidate headings as legacy text; they are not the release version identifier and were not corrected in this release.

Packaging, a read-only DMG mount and an install-directory copy are not an installed-App launch test. This final App has not been launched in the release-preparation round. A local unquarantined copy does not establish freshly downloaded first-opening behavior. These runtime uncertainties are accepted by the user-exception decision, without a launch-quality guarantee.

For problem reports, provide the version, macOS/chip, reproduction steps, expected and actual results, and only sanitized supporting material. Never publicly share real financial data, keys, full logs or private backups. Remaining performance and log-privacy verification is incomplete.

## Build from source

Use an extracted, clean source ZIP, not a directory containing private data or build products. The ZIP's root README is this public guide; internal project reports and evidence are intentionally excluded. Review the source and scripts before running commands.

The development baseline is Xcode 26.6 (Swift 6 language mode); the current build host's SDK does not increase the deployment target. GRDB is pinned to **7.11.1**, revision **b83108d10f42680d78f23fe4d4d80fc88dab3212**, in the shared `Package.resolved`. Lightweight Charts **5.2.0** is bundled locally, with no npm install or runtime CDN. Dependency acquisition is a separate user action: this recipe requires an existing Xcode package cache with the exact locked GRDB checkout. If it is absent or differs, stop and prepare it explicitly; the packaging script never downloads or resolves dependencies.

From the clean extracted source directory, set `AUREUS_SOURCE_PACKAGES` to your existing verified Xcode `SourcePackages` directory. Create a fresh sibling work directory and build from its source copy, retaining the clean source for packaging:

```sh
AUREUS_SOURCE="$(pwd -P)"
AUREUS_WORK="$(mktemp -d "${AUREUS_SOURCE}/../Aureus-build-XXXXXX")"
AUREUS_SOURCE_PACKAGES="/absolute/path/to/verified/SourcePackages"
/usr/bin/ditto "$AUREUS_SOURCE" "$AUREUS_WORK/Source"
/usr/bin/xcodebuild build \
  -project "$AUREUS_WORK/Source/Aureus.xcodeproj" \
  -scheme Aureus -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$AUREUS_WORK/ReleaseDerivedData" \
  -resultBundlePath "$AUREUS_WORK/ReleaseBuild.xcresult" \
  -clonedSourcePackagesDirPath "$AUREUS_SOURCE_PACKAGES" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES ENABLE_TESTABILITY=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Confirm the command's actual exit, complete result bundle, build result and input identity before packaging. Locate and inspect the actual Release App output; do not substitute an old App. Tests are provided as synthetic definitions, but this build/packaging recipe does not run them.

## Package a verified Release App

The script accepts three **absolute paths**: a verified Release App, the unchanged clean source snapshot, and a new output directory whose parent already exists. The output must not overlap either input. For example, after assigning `AUREUS_RELEASE_APP` to the actual inspected build output:

```sh
/bin/bash -n "$AUREUS_SOURCE/scripts/package-macos-arm64.sh"
/bin/bash "$AUREUS_SOURCE/scripts/package-macos-arm64.sh" \
  "$AUREUS_RELEASE_APP" "$AUREUS_SOURCE" "$AUREUS_WORK/Package"
```

The script never builds, runs tests, launches the App, fetches dependencies, invokes Git, notarizes or publishes. It copies the App into new staging, adds public licenses, checks arm64 code and resources, signs enumerated nested code inside-out and then the App with the snapshot's frozen entitlements. It creates a UDZO DMG, verifies it, mounts it read-only at its own mount point, copies the App into its own install-check directory, checks full bundle identity and signature, detaches only that image, and verifies an extracted source ZIP. It preserves failures and does not retry or clean up automatically. If an image remains mounted on failure, its exact mount point is recorded for explicit handling.

Outputs in `Package/Artifacts` are `Aureus-1.0.0-macos-arm64.dmg`, `Aureus-1.0.0-source.zip`, and `SHA256SUMS`. Only these public artifacts are intended for handoff after artifact review. `Package/Audit` contains local command paths and product records and is **not public material**. The script's checks do not replace source-whitelist review or establish installed-App runtime success. Upload is a separate user action; artifact preparation does not mean public publication.

## Third-party materials

The source ZIP includes the complete GRDB MIT notice in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and Charts [Apache-2.0 LICENSE](Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/LICENSE), [NOTICE](Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/NOTICE), and [provenance](Aureus/Resources/ThirdParty/LightweightCharts/5.2.0/PROVENANCE.md). TradingView attribution remains visible in the native Markets interface.

The packaged App carries readable licensing under `Contents/Resources/Licenses`: Aureus `LICENSE`, the full `THIRD_PARTY_NOTICES.md`, `GRDB-LICENSE`, `Charts-LICENSE`, `Charts-NOTICE`, and `Charts-PROVENANCE.md`. The original Charts resource directory and required GRDB resource/privacy bundle are also preserved. Third-party copyright and license terms are not relabeled as Aureus MIT.
