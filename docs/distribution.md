# Download and install Aureus

## Official 1.0.0 / build 1

[Release notes](https://github.com/freeforest/Aureus/releases/tag/v1.0.0)

Download these three release assets into one folder:

- [Aureus-1.0.0-macos-arm64.dmg](https://github.com/freeforest/Aureus/releases/download/v1.0.0/Aureus-1.0.0-macos-arm64.dmg)
- [Aureus-1.0.0-source.zip](https://github.com/freeforest/Aureus/releases/download/v1.0.0/Aureus-1.0.0-source.zip)
- [SHA256SUMS](https://github.com/freeforest/Aureus/releases/download/v1.0.0/SHA256SUMS)

Official maintenance covers Apple Silicon / arm64 / M-series Macs. macOS 14.0 is the minimum deployment target, not evidence of testing on every Mac or OS version. The source is MIT licensed without a hardware restriction.

## Signing and verification limits

The binary is locally ad-hoc signed, has no Developer ID, and is not notarized by Apple. Checksums check file identity; they do not establish a trusted publisher identity or replace macOS security checks.

This is a formal user-exception release, not a preview. Technical evidence remains PARTIAL. Remaining manual, performance, log-privacy, and final-App runtime checks are unfinished. See the [verification summary](evidence/release-1.0.0.md).

## Verify downloads

In Terminal, change to the folder containing all three downloaded files, then run:

```sh
shasum -a 256 -c SHA256SUMS
```

Both archives must report OK. Stop on a mismatch or missing file; do not install an unverified substitute. Download checks do not prove that the App has launched successfully.

## Install and first open

1. Keep an independent private backup of important records before changing an existing installation.
2. Open the verified DMG and read its INSTALL instructions.
3. Copy Aureus.app to your chosen application folder, preserving any existing installation until you have a recovery plan. Eject the DMG after copying.
4. Open your copied App normally. No QA, Demo, or temporary-store arguments are required for ordinary use.
5. If macOS requires approval for an unidentified developer, use only the per-App approval flow macOS offers, and only if you trust the source. Availability and wording depend on macOS.

If macOS reports malware, damage, or suspected tampering, stop. Do not disable Gatekeeper, remove quarantine attributes, or bypass malware warnings. The final downloaded App's first-open behavior was not fully verified for this release.

## Keep backups private

Aureus does not independently encrypt backups. Store important copies separately under protections you manage; do not rely on the App's only internal copy. Never attach a private backup or database to a public issue.

## Build and package

Use the release's clean source ZIP and the [public guide](../PUBLIC_README.md#build-from-source). The published archive's root README comes from that guide. This presentation update does not modify the archive, script, version, signing, or existing release.

[Documentation](README.md) · [Privacy & Data](privacy-and-data.md)
