#!/bin/bash
# Sync rime-ice dictionaries (cn_dicts/en_dicts) into SharedSupport

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <SharedSupport directory>" >&2
    exit 1
fi

DEST_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RIME_ICE_DIR="${REPO_ROOT}/rime-ice"

if [ ! -d "${RIME_ICE_DIR}" ]; then
    echo "rime-ice directory not found at ${RIME_ICE_DIR}" >&2
    exit 1
fi

if [ ! -d "${DEST_DIR}" ]; then
    echo "SharedSupport directory ${DEST_DIR} does not exist" >&2
    exit 1
fi

copy_dict_dir() {
    local dir_name="$1"
    local src="${RIME_ICE_DIR}/${dir_name}"
    local dest="${DEST_DIR}/${dir_name}"

    if [ ! -d "${src}" ]; then
        echo "Missing ${dir_name} in ${RIME_ICE_DIR}" >&2
        exit 1
    fi

    mkdir -p "${dest}"
    rsync -a --delete "${src}/" "${dest}/"
}

copy_dict_dir "cn_dicts"
copy_dict_dir "en_dicts"
