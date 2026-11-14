#!/usr/bin/env bash
# Build a version-matched JetKVM application from source and deploy via OTA.
set -Eeuo pipefail

error() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[JetKVM mod] %s\n' "$*"; }

mod_root=''
ref='release/0.5.10'
device=''
key=''
audio=false
theme=false
fill=false
preview=false

while (($#)); do
    case "$1" in
        --root|--ref|--device|--ssh-key)
            (($# >= 2)) || error "Missing value for $1"
            case "$1" in
                --root) mod_root=$2 ;;
                --ref) ref=$2 ;;
                --device) device=$2 ;;
                --ssh-key) key=$2 ;;
            esac
            shift 2 ;;
        --audio) audio=true; shift ;;
        --theme) theme=true; shift ;;
        --fill) fill=true; shift ;;
        --preview) preview=true; shift ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ -n "$mod_root" && -d "$mod_root/patches" ]] || error 'Patch directory unavailable.'
[[ "$ref" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || error 'Invalid upstream ref.'
if [[ "$audio" != true && "$theme" != true && "$fill" != true ]]; then
    error 'No features selected.'
fi
if [[ "$preview" != true ]]; then
    [[ "$device" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || error 'Device must be an IPv4 address.'
fi

command -v git >/dev/null || error 'Git is missing in WSL.'
command -v ssh >/dev/null || error 'OpenSSH client is missing in WSL.'

if [[ -n "$key" ]]; then
    if [[ "$key" == '~/'* ]]; then key="$HOME/${key:2}"; fi
    [[ -f "$key" ]] || error "SSH key not found: $key"
    # dev_deploy.sh invokes ssh repeatedly. Export this wrapper only to its
    # child bash process; do not modify the user's global SSH configuration.
    export JETKVM_MOD_SSH_KEY="$key"
    ssh() { command ssh -i "$JETKVM_MOD_SSH_KEY" -o IdentitiesOnly=yes "$@"; }
    export -f ssh
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/jetkvm-custom-mod.XXXXXXXX")
[[ -n "$work_dir" && -d "$work_dir" ]] || error 'Cannot create temporary build directory.'
repo="$work_dir/kvm"
success=false
finish() {
    if [[ "$success" == true ]]; then
        rm -rf -- "$work_dir"
    else
        printf '\nBuild files retained for troubleshooting: %s\n' "$work_dir" >&2
    fi
}
trap finish EXIT

info "Downloading official JetKVM source at $ref..."
git clone --depth 1 --branch "$ref" https://github.com/jetkvm/kvm.git "$repo"

if [[ "$ref" == release/0.5.10 ]]; then
    expected='f152581df82c519ecc4349f471dfc8612fbf0c48'
    actual=$(git -C "$repo" rev-parse HEAD)
    [[ "$actual" == "$expected" ]] || error "Unexpected 0.5.10 source revision ($actual). Refusing to apply an unverified patch."
else
    info 'WARNING: This upstream version is not tested. Attempting compatible three-way merges if needed.'
    # The original 0.5.10 blobs are needed by git apply --3way on a newer
    # shallow checkout. Never force a conflict resolution automatically.
    git -C "$repo" fetch --depth 1 origin release/0.5.10
fi

selected=()
if [[ "$audio" == true ]]; then selected+=("$mod_root/patches/01-hdmi-audio.patch"); fi
if [[ "$theme" == true ]]; then selected+=("$mod_root/patches/02-black-theme.patch"); fi
if [[ "$fill" == true ]]; then
    if [[ "$audio" == true ]]; then
        selected+=("$mod_root/patches/03-fill-window-with-audio.patch")
    else
        selected+=("$mod_root/patches/03-fill-window.patch")
    fi
fi

for patch_file in "${selected[@]}"; do
    info "Applying $(basename "$patch_file")..."
    if git -C "$repo" apply --check "$patch_file"; then
        git -C "$repo" apply "$patch_file"
    elif [[ "$ref" != release/0.5.10 ]] && git -C "$repo" apply --3way --check "$patch_file"; then
        git -C "$repo" apply --3way "$patch_file"
    else
        error "Patch conflict in $(basename "$patch_file"). This source version needs a reviewed port."
    fi
    # Keep temporary index/worktree synchronized for a later --3way patch.
    git -C "$repo" add -A
done
git -C "$repo" diff --check || error 'Patch whitespace validation failed.'
git -C "$repo" diff --cached --check || error 'Merged patch whitespace validation failed.'
info 'All selected source patches applied successfully.'

if [[ "$preview" == true ]]; then
    info 'Preview succeeded. No build or device changes performed.'
    success=true
    exit 0
fi

command -v docker >/dev/null || error 'Docker is required in WSL for the JetKVM cross-build.'
docker info >/dev/null 2>&1 || error 'Docker is not running or not integrated with this WSL distribution.'
command -v node >/dev/null || error 'Node.js is required for the JetKVM UI build.'
command -v go >/dev/null || error 'Go is required to start the JetKVM build.'
command -v make >/dev/null || error 'GNU Make is required for the JetKVM build.'

info "Checking SSH access to root@$device..."
ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 "root@$device" true || error 'SSH authentication failed. Enable Developer Mode and configure root SSH access.'

if [[ "$audio" == true ]]; then
    info 'Checking TC358743 HDMI audio hardware support...'
    ssh "root@$device" 'grep -qi tc358743 /proc/asound/cards 2>/dev/null' || error 'No TC358743 ALSA capture card found. The application patch alone cannot enable missing kernel/device-tree support.'
fi

info 'Backing up the currently running JetKVM application...'
ssh "root@$device" '
    set -e
    app=""
    for candidate in /userdata/jetkvm/bin/jetkvm_app /userdata/jetkvm/jetkvm_app; do
        if [ -f "$candidate" ]; then app="$candidate"; break; fi
    done
    if [ -z "$app" ]; then
        echo "Cannot find installed jetkvm_app for backup" >&2
        exit 1
    fi
    backupdir=/userdata/jetkvm/mod-backups
    mkdir -p "$backupdir"
    stamp=$(date +%Y%m%d-%H%M%S)
    backup="$backupdir/jetkvm_app.$stamp"
    cp -p "$app" "$backup"
    test -s "$backup"
    echo "Backup saved at $backup"
' || error 'Could not back up the existing JetKVM app. Stopping safely.'

info 'Building all selected modifications and installing via JetKVM OTA staging...'
info 'This can take a while on the first build. The device will reboot after a successful build.'
(
    cd "$repo"
    GOTOOLCHAIN=go1.26.11 ./dev_deploy.sh -r "$device" --install
)

info 'Installation submitted. Wait for the device to reboot and reconnect.'
success=true
