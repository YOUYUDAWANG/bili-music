#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
deployment_root="${BILIMUSIC_LDDC_ROOT:-${script_directory:h}}"
token_path="${deployment_root}/server-token.txt"
executable="${deployment_root}/venv/bin/bilimusic-lddc-backend"

if [[ ! -r "${token_path}" ]]; then
    print -u2 -- "Missing LDDC backend token file"
    exit 1
fi

if [[ ! -x "${executable}" ]]; then
    print -u2 -- "Missing LDDC backend virtual environment"
    exit 1
fi

export LDDC_BACKEND_TOKEN="$(<"${token_path}")"
export LDDC_BACKEND_HOST="${LDDC_BACKEND_HOST:-127.0.0.1}"
export LDDC_BACKEND_PORT="${LDDC_BACKEND_PORT:-8788}"
export LDDC_BACKEND_TIMEOUT_SECONDS="${LDDC_BACKEND_TIMEOUT_SECONDS:-18}"

exec "${executable}"
