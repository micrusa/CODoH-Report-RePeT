#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '%s\n' 'Run source ./create-api-key.sh [duration] to export the key in your current shell.' >&2
    exit 1
fi

_codoh_create_api_key() {
    local duration=${1-1h} unit expiry name key traced=0 status=0
    if [[ $# -gt 1 || ! $duration =~ ^[1-9][0-9]*[mh]$ ]]; then
        printf '%s\n' 'Usage: source ./create-api-key.sh [duration] (e.g. 5m or 1h, default 1h).' >&2
        return 1
    fi
    case ${duration: -1} in
        m) unit=minutes ;;
        h) unit=hours ;;
    esac
    if ! command -v ibmcloud >/dev/null || ! command -v jq >/dev/null; then
        printf '%s\n' 'Install the IBM Cloud CLI and jq first.' >&2
        return 1
    fi
    expiry=$(date -u -d "+${duration%?} $unit" '+%Y-%m-%dT%H:%M:%S+0000') || return
    name="codoh-terraform-$(date -u '+%Y%m%dT%H%M%S')-$$"

    if [[ $- == *x* ]]; then
        traced=1
        set +x
    fi
    if key=$(set -o pipefail
        ibmcloud iam api-key-create "$name" --expiry "$expiry" --output JSON |
            jq -er '.apikey | strings | select(length > 0)'
    ); then
        unset IC_API_KEY
        export IBMCLOUD_API_KEY="$key"
        printf 'Exported IBM Cloud key %s (expires %s UTC).\n' "$name" "$expiry"
    else
        printf '%s\n' 'Key creation failed. Check your IBM Cloud CLI login and account.' >&2
        status=1
    fi
    if (( traced )); then
        set -x
    fi
    return "$status"
}

if _codoh_create_api_key "$@"; then
    unset -f _codoh_create_api_key
else
    unset -f _codoh_create_api_key
    return 1
fi
