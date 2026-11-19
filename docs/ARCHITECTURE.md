# EMS -> Cerberus -> nxnative build architecture

**Status: proposed, not deployed.**

## Source
Windows host **EMS**: `D:\Emulators\Switch`. Game inputs, keys and firmware remain here until a selected build requires them. Do not inventory or upload filenames to a public action log.

## Coordinator
Cerberus may stage a *selected* game package and required key file. The transfer design must first establish EMS-to-Cerberus connectivity and authenticated macOS runner retrieval. Prefer expiring, one-time credentials, narrow file scopes, read-only sharing, TLS, and reliable revocation. No anonymous public endpoint.

## Builder
Use a temporary Apple silicon macOS environment with the exact upstream nxnative requirements. As of initial research, upstream specifies macOS 26.6+, Xcode 27.2, Python 3.12+, Homebrew, Xcode's iOS platform and MetalToolchain. Do not assume an arbitrary GitHub-hosted runner meets these requirements.

The official command after setup is `python3 scripts/build_ipa_from_nsp.py /path/to/game -k /path/to/prod.keys`.

## Outputs
Unsigned IPA and optional separate RomFS; deliver through a controlled private channel. GitHub Actions artifacts are unsuitable for keys or unrestricted game dumps. IPA contents can themselves include copyrighted game data, so artifact publication requires an explicit private-output decision.

## Current blockers
1. EMS is not connected to remote file tools; source directory structure is unverified.
2. Private staging/transfer has not been configured.
3. Suitable Apple silicon macOS/Xcode runner availability has not been validated.
4. No title selected and no build has been attempted.

## Initial validation
Run repository preflight. Then inventory extensions/counts locally without sending proprietary data, identify suitable macOS build capacity and implement a first authenticated transfer test using harmless dummy files.
