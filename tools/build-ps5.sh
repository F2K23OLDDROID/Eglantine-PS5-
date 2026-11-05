#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# One-command PS5 build for WSL or Linux, consolidating the upstream sources
# (heydemoura/EglantinePS5 frontend + Djihads80/Eglantine core + viejunerd NUP/Bananza patches).
#
#   bash tools/build-ps5.sh                 # app in build/release/PPSA98515
#   bash tools/build-ps5.sh --release       # ... and the release files in dist/
#   bash tools/build-ps5.sh --dev TITLE_ID  # development build in build/dev/PPSA98515
#   bash tools/build-ps5.sh --jobs 8        # parallel compile jobs
#   bash tools/build-ps5.sh --clean         # remove build/ and dist/ first
#   bash tools/build-ps5.sh --no-toolchain  # skip the host tool check
#
# The program the console runs is build/release/PPSA98515/eboot.bin (a signed PS5 ELF
# container). build/headless-native/llvm-pie.elf is the same program before signing;
# build/headless-native/eboot.elf is it after the PS5 module link.
#
# The build is a release build (-O3, function/data sections) tuned for the PS5's AMD Zen 2
# CPU (-march=znver2). EDEN_PS5_BUILD_PRESET=custom turns the CPU tuning off and generic
# targets baseline x86-64.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

mode=package
dev_title=
jobs=
clean=0
toolchain=1
while [[ $# -gt 0 ]]; do
    case $1 in
    --release) mode=release ;;
    --dev)
        [[ $# -ge 2 ]] || { echo 'Usage: tools/build-ps5.sh --dev TITLE_ID' >&2; exit 2; }
        mode=dev
        dev_title=$2
        shift
        ;;
    --jobs)
        [[ $# -ge 2 && $2 =~ ^[1-9][0-9]*$ ]] || { echo 'Usage: tools/build-ps5.sh --jobs N' >&2; exit 2; }
        jobs=$2
        shift
        ;;
    --clean) clean=1 ;;
    --no-toolchain) toolchain=0 ;;
    -h | --help)
        cat <<'USAGE'
Usage: tools/build-ps5.sh [--release | --dev TITLE_ID] [--jobs N] [--clean] [--no-toolchain]

  (no option)          app in build/release/PPSA98515 (default)
  --release            also write the ZIP and checksums to dist/
  --dev TITLE_ID       development build in build/dev/PPSA98515, booting TITLE_ID
  --jobs N             parallel compile jobs (default: all cores)
  --clean              remove build/ and dist/ first
  --no-toolchain       skip the host tool check

The signed PS5 ELF is build/release/PPSA98515/eboot.bin; the unstripped ELF is
build/headless-native/llvm-pie.elf.
USAGE
        exit 0
        ;;
    *)
        echo "Unknown option: $1 (try: tools/build-ps5.sh --help)" >&2
        exit 2
        ;;
    esac
    shift
done

if [[ $(uname -s) != Linux ]]; then
    echo 'EglantinePS5 builds on Linux. On Windows, run this inside WSL (wsl --install Ubuntu-26.04).' >&2
    exit 1
fi
if grep -qi microsoft /proc/version 2>/dev/null; then
    case $root in
    /mnt/[a-z]/*)
        echo "Note: this checkout is on a Windows drive ($root). It builds, but keeping it under"
        echo '      your Linux home directory (for example ~/EglantinePS5) is faster. The build'
        echo '      cache is already kept on the Linux filesystem.'
        ;;
    esac
fi
command -v make >/dev/null || { echo 'make is missing: sudo apt install build-essential' >&2; exit 1; }

if ((toolchain)); then
    echo '== Host tools'
    if ! make toolchain; then
        echo >&2
        echo 'Install the missing packages on Ubuntu 26.04 with:' >&2
        echo '  sudo apt install --no-install-recommends $(grep -v "^#" tools/ci/ubuntu-packages.txt)' >&2
        exit 1
    fi
fi

((clean)) && make clean
echo '== Inputs (submodule, pinned dependencies, Eglantine patches)'
make deps

make_args=()
[[ -n $jobs ]] && make_args+=("JOBS=$jobs")
case $mode in
release) make release "${make_args[@]}" ;;
dev) make dev DEV_TITLE="$dev_title" "${make_args[@]}" ;;
*) make package "${make_args[@]}" ;;
esac

if [[ $mode == dev ]]; then
    app="$root/build/dev/PPSA98515"
else
    app="$root/build/release/PPSA98515"
fi
elf="$root/build/headless-native/llvm-pie.elf"
[[ -f $app/eboot.bin ]] || { echo "Build finished without $app/eboot.bin" >&2; exit 1; }
[[ -f $elf ]] || { echo "Build finished without $elf" >&2; exit 1; }

echo
echo '== Built'
printf '  %-58s %s\n' "$app/eboot.bin" "$(du -h "$app/eboot.bin" | cut -f1) (signed PS5 ELF container)"
printf '  %-58s %s\n' "$elf" "$(du -h "$elf" | cut -f1) (unstripped ELF)"
printf '  %-58s %s\n' "$root/build/headless-native/eboot.elf" "$(du -h "$root/build/headless-native/eboot.elf" | cut -f1) (linked PS5 ELF)"
if [[ $mode == release ]]; then
    shopt -s nullglob
    for file in "$root"/dist/*.zip "$root"/dist/SHA256SUMS; do
        printf '  %-58s %s\n' "$file" "$(du -h "$file" | cut -f1)"
    done
    shopt -u nullglob
fi
echo
echo 'Copy the app folder to /data/homebrew/PPSA98515 on the console, or run:'
echo "  make install PS5_HOST=<console address>"
