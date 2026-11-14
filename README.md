# JetKVM HDMI Audio + Black Theme + Fill Window

Community modification for the **original JetKVM**. Pick any combination of:

- **HDMI audio** — TC358743 capture, HDMI/USB/off source selector, browser-side 0–200% volume, G.722, and the tested buffered sender that fixed intermittent audio skipping.
- **Black theme** — neutral charcoal/black surfaces without turning status and action buttons into indistinguishable blobs.
- **Fill Window** — expand video into the browser viewport without browser fullscreen; hover at the top centre to show **Exit Window Fill**.

The installer asks about each feature separately. No feature forces the others.

> **Compatibility:** The patches are based on JetKVM **app 0.5.10**, commit `f152581df82c519ecc4349f471dfc8612fbf0c48`. The all-enabled configuration was tested on a JetKVM running system firmware 0.2.8. **Other app versions or system images have not been validated.** This repository does not modify the kernel or flash system firmware.

## Requirements

- Windows 10/11 with **WSL2** and a working Linux distribution (Ubuntu recommended).
- Git, Bash, Make, OpenSSH client, Go (with `GOTOOLCHAIN=go1.26.11` support), Node.js 22+, and Docker with WSL integration.
- Internet access for the initial source clone, build container, and Go/Node dependencies.
- A JetKVM with **Developer Mode and SSH access enabled** (`root` account). Password authentication works, but an SSH key is more convenient because upstream deployment uses multiple connections.
- For **HDMI audio**, the JetKVM system/kernel must already expose an ALSA card named `tc358743`. If the card is missing, the installer stops before touching the device.

The first local build may take quite a while and download substantial tooling. Keep the JetKVM powered throughout installation.

## Windows PowerShell installation

1. Download this repository using GitHub **Code → Download ZIP** and extract it, or clone it with Git.
2. Open **PowerShell** in the extracted directory.
3. Run:

   ```powershell
   .\Install.ps1 -DeviceIP 192.168.1.100
   ```

4. Answer **Y/N** for audio, black theme, and Fill Window. Enter an optional SSH key path in WSL (for example `~/.ssh/id_ed25519`).
5. Review the source-version and device warnings; type **INSTALL** to confirm.

The script builds a **fresh checkout** of JetKVM with the selected patches, backs up the current JetKVM application on the device, and uses the official app-update staging method. The device reboots after deployment.

### Install only certain features

No interactive feature questions when `-Features` is supplied:

```powershell
# Black theme only
.\Install.ps1 -DeviceIP 192.168.1.100 -Features BlackTheme

# HDMI audio and Fill Window, original navy theme
.\Install.ps1 -DeviceIP 192.168.1.100 -Features Audio,FillWindow

# Every feature, with an explicit WSL SSH key
.\Install.ps1 -DeviceIP 192.168.1.100 -Features Audio,BlackTheme,FillWindow -SshKey ~/.ssh/id_ed25519
```

To verify that the selected source patches apply **without building or connecting to a JetKVM**:

```powershell
.\Install.ps1 -Features Audio,BlackTheme,FillWindow -PreviewOnly
```

### What happens after an official firmware update?

An **official app update** replaces the modified application. Re-run this installer **once the repository includes patches verified for that new app version**. The default build remains pinned to 0.5.10; do **not** assume it retains newer official features.

The `-UpstreamRef` parameter can attempt a different official tag, for example:

```powershell
.\Install.ps1 -Features Audio,BlackTheme,FillWindow -UpstreamRef release/0.5.11 -PreviewOnly
```

The installer first attempts an exact patch, then a three-way merge using the original source if needed. If a conflict remains, it stops **before deployment**. A clean merge is not a guarantee that the resulting application works with a new release: treat other refs as experimental until tested. Do **not** force-apply an old patch to a changed app or use a generated binary for an unrelated device version.

A **system/kernel update** is different. It can remove HDMI audio device-tree support. This installer only checks for the existing `tc358743` ALSA capture card; it does not patch or replace the kernel. The `rv1106-system` tree used during development had no tracked local changes, so there is no known-good system patch to distribute yet.

JetKVM automatic updates may overwrite the custom app. Consider turning off Auto Update in **Settings → General** if retaining these modifications matters more than automatic official updates.

## Backups, recovery, and risk

- Immediately before deployment, the installer copies the currently installed app to `/userdata/jetkvm/mod-backups/jetkvm_app.<timestamp>` on the device. It refuses to deploy if it cannot make a backup.
- You can return to an official app using JetKVM's supported app update interface. Restoring an individual on-device backup is a separate, advanced recovery operation; this project does not run it automatically.
- The installer **reboots the JetKVM** after a successful build and app staging operation. It does not flash the bootloader or kernel.
- Upstream `dev_deploy.sh` currently uses relaxed SSH host-key checks internally. Use this on a network you trust and review the scripts before running them.
- The HDMI feature has been tested on one device. **Other hardware revisions and partial feature combinations still require real-device testing.**

## Source layout

| Path | Purpose |
| --- | --- |
| `Install.ps1` | Windows feature prompts and WSL launcher |
| `scripts/install.sh` | Source clone, version gate, patch checks, backup and deployment |
| `patches/01-hdmi-audio.patch` | Backend capture + WebRTC pacing + audio settings and local volume |
| `patches/02-black-theme.patch` | Visual black/charcoal theme only |
| `patches/03-fill-window.patch` | Fill Window without the audio feature |
| `patches/03-fill-window-with-audio.patch` | Fill Window variant for when the audio feature is selected |

The two Fill Window patch variants are deliberate: both features edit `WebRTCVideo.tsx`. They avoid ambiguous hunks and make all eight Yes/No combinations apply cleanly.

## Credits and license

Based on [JetKVM's open-source application](https://github.com/jetkvm/kvm), GPL-2.0. Original modifications from a JetKVM 0.5.10 working build (`39de3c0`). Patch files are published under the same GPL-2.0 terms. Not affiliated with or supported by JetKVM.
