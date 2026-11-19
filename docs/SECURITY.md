# Public repository, private infrastructure

**Status (2026-11-19): build gated off. No GitHub secrets provisioned by this repository, no SSH/Tailscale credentials generated or posted, no game or key uploaded.**

## Security boundaries

- Public repository contains only auditable scripts and workflow text.
- EMS is the source of game files and `prod.keys`, and destination for produced IPA.
- A GitHub-hosted runner is **not trusted to retain secrets**. During a run it necessarily gets the selected game files and a copy of `prod.keys` in ephemeral disk and executes an external nxnative build.
- Public Actions logs can be read by strangers. Never enable shell tracing (`set -x`) in secret-handling steps or print game paths, environment secrets, key files, tar contents or output IPA.
- Generated IPA can contain copyrighted game files. Uploading it with `actions/upload-artifact` in a public repository is explicitly disallowed.
- Tailscale is network authorization, **not** file authorization. SSH and filesystem ACLs still matter.

## Setup prerequisites (not yet completed)

1. **EMS: dedicate a non-administrator account** (e.g., `nxnative-ci`) for the builder. Do not reuse the existing Windows user or administrator. Use key-based OpenSSH login only for this identity and deny shell/port forwarding if feasible while preserving SFTP. Verify Windows sshd supports the selected restriction settings before deployment.
2. **EMS NTFS ACLs:** for the new account, grant read to `D:\Emulators\Switch\.nxnative-staging` and write to `D:\Emulators\Switch\.nxnative-outputs` *only*. Explicitly verify that it cannot traverse/read `D:\Emulators\Switch\Games - ROMs`, the original `Ryujinx` key directory, user profiles, or other volumes. Do not grant Full Control to the whole Switch directory; parent traversal permissions require care. A temporary copied key in one staging subfolder is still secret data.
3. **EMS OpenSSH:** verify its **host key fingerprint out of band** using local administrator access; paste the public `known_hosts` line into the GitHub secret `EMS_SSH_KNOWN_HOSTS`. Never trust first-use `ssh-keyscan` from CI.
4. **Dedicated SSH key:** generate a separate Ed25519 keypair exclusively for this workflow; put public half into the dedicated account's authorized_keys, and private half into GitHub Actions encrypted secret `EMS_SSH_PRIVATE_KEY`. Set `EMS_SSH_USER` to only the dedicated account name. Rotate and revoke if exposed. Do not use a personal SSH key.
5. **Tailscale:** create a dedicated OAuth client limited to auth-key issuance tagged `tag:github-builder` (and make the tagged runners ephemeral). Configure tailnet grants so the builder tag can reach **EMS TCP/22 only**, not Cerberus or the rest of the tailnet. Retain existing user-to-EMS access. Never broadly allow `tag:github-builder` to `*:* `. Validate a denied connection to an unrelated tailnet endpoint.
6. **GitHub Actions secrets:** provision `TS_OAUTH_CLIENT_ID`, `TS_OAUTH_CLIENT_SECRET`, `EMS_SSH_PRIVATE_KEY`, `EMS_SSH_KNOWN_HOSTS`, `EMS_SSH_USER`. These five secrets are not stored in git and should only be entered through GitHub's secure settings flow. Restrict repository write access and workflow editing privileges; protect default branch against unreviewed changes. Be aware anyone who can modify and run a workflow with secrets can extract them.
7. **Security gate:** only after all checks pass, set repo variable `ENABLE_PRIVATE_BUILDS` to `true`. Until then, dispatch jobs skip. If an encrypted secret is compromised, disable this variable first, then rotate and revoke at EMS/Tailscale/GitHub.

## Build preparation

On EMS, run `scripts/stage-ems.ps1 -GameFolder '<exact-folder-name>'`. It creates a random staging ID, an archive of the selected folder, a *temporary copy* of `prod.keys`, and an empty output directory. Do not run the staging command yet unless disk space and dedicated-account ACLs have been verified.

Enter only the random build ID in GitHub's manual workflow dispatch form. After completion or failure, run `scripts/cleanup-ems.ps1 -BuildId '<id>'` and confirm. This cleanup is not yet automatic; design a restricted coordinator if automatic expiry is required.

## Hardening still required before production

- No branch protections or GitHub secrets were created by this automation.
- The standard builder currently tracks upstream `main`; pin an audited upstream commit to prevent unexpected code changes before exposing secrets.
- Third-party GitHub Actions should also be pinned to immutable full-length commit SHAs.
- Validate Windows OpenSSH SFTP drive-letter syntax with dummy data.
- Run authenticated transfer tests using benign dummy files, including **denied** reads outside the staging directory.
- Prove SSH login is not an administrator account and cannot access the original key directory.
- Verify runner support for Xcode >=27.2. `xcode-27` is a valid Apple Silicon runner label, but its actual installed Xcode still needs checking.
- Typical GitHub ARM macOS runners have ~14 GB disk. nxnative upstream estimates **2x game size + 10 GB** free; large builds may need non-free larger runners or another host.
- First IPA build requires explicit user-selected title, tested inputs, and a secure output path.

## Firmware

Firmware `D:\Emulators\Switch\Ryujinx\publish\Firmware.22.1.0` is **not** part of the documented standard nxnative command. Never stage it by default.

## Operational rule

Do not enable private builds, create privileged accounts, widen tailnet access or upload any real game/key materials as part of a dry run. A green non-sensitive preflight does **not** mean the private pipeline has been security-validated.
