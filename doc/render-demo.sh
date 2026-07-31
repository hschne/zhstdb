#!/usr/bin/env bash

set -euo pipefail

function main() {
    local root

    command -v vhs >/dev/null 2>&1 || die "vhs is required"
    command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg is required"

    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    cd "$root"
    vhs doc/demo.tape \
        -o doc/assets/demo.gif \
        -o doc/assets/demo.mp4
    ffmpeg -loglevel error -y -ss 4 \
        -i doc/assets/demo.mp4 -frames:v 1 doc/assets/preview.png
}

die() {
    echo "Error: $1" >&2
    exit "${2:-1}"
}

usage() {
    cat <<EOF
Usage: $(basename "$0")

Regenerate the README demo, MP4, and still from doc/demo.tape.
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    [[ $# -eq 0 ]] || die "This command accepts no arguments"
    main
fi
