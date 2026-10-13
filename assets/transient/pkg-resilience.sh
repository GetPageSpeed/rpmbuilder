# shellcheck shell=bash
# Package-manager retry helpers for image builds, sourced by setup.sh.
#
# Why this exists: a scheduled image build died on 2026-10-13 (almalinux:8
# arm64) because the AlmaLinux mirror pool was mid-sync -- the repomd.xml dnf
# fetched referenced primary/filelists files every mirror had already pruned.
# The old retry() could never recover from that: dnf cached the stale
# repomd.xml on attempt 1 and attempts 2..5 asked for the same dead hashes.
#
# Recovery ladder for dnf/yum commands run through retry():
#   after every failure  -> "clean metadata", so the next attempt refetches repomd
#   after the 2nd failure -> EL vendor repos (AlmaLinux/Rocky) switch from the
#                            mirrorlist to their origin baseurl, which is always
#                            self-consistent
# el_restore_mirrorlist puts the vendor repo files back byte-for-byte, so the
# shipped image keeps the geo mirror pool and no hard dependency on one host.

EL_REPO_DIR=${EL_REPO_DIR:-/etc/yum.repos.d}
EL_ORIGIN_MARK="#rpmbuilder-origin-fallback"
EL_ON_ORIGIN=0
RETRY_SLEEP=${RETRY_SLEEP:-5}

# Vendor repo files that have a usable commented-out origin baseurl.
el_vendor_repo_files() {
    local f
    for f in "${EL_REPO_DIR}"/almalinux*.repo "${EL_REPO_DIR}"/[Rr]ocky*.repo; do
        [ -f "$f" ] && grep -q '^mirrorlist=' "$f" && echo "$f"
    done
    return 0
}

# Within each section that has an active mirrorlist=, comment it out (marked)
# and activate the commented baseurl= (marked, original line preserved).
el_switch_to_origin() {
    local f tmp switched=0
    while IFS= read -r f; do
        tmp="${f}.rpmbuilder-tmp"
        awk -v mark="${EL_ORIGIN_MARK}" '
            NR == FNR {
                if ($0 ~ /^\[/) sec = $0
                if ($0 ~ /^mirrorlist=/) has_ml[sec] = 1
                next
            }
            /^\[/ { sec = $0 }
            has_ml[sec] && /^mirrorlist=/ { print mark " " $0; next }
            has_ml[sec] && /^#[[:space:]]*baseurl=/ {
                line = $0
                sub(/^#[[:space:]]*/, "", line)
                print mark "-baseurl:" $0
                print line
                next
            }
            { print }
        ' "$f" "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"
        switched=1
    done < <(el_vendor_repo_files)
    if [ "$switched" = 1 ]; then
        echo "Switched EL vendor repos to origin baseurl (mirror pool looks inconsistent)"
        EL_ON_ORIGIN=1
    fi
}

el_restore_mirrorlist() {
    [ "${EL_ON_ORIGIN}" = 1 ] || return 0
    local f tmp
    for f in "${EL_REPO_DIR}"/*.repo; do
        [ -f "$f" ] && grep -q "^${EL_ORIGIN_MARK}" "$f" || continue
        tmp="${f}.rpmbuilder-tmp"
        awk -v mark="${EL_ORIGIN_MARK}" '
            skip { skip = 0; next }
            index($0, mark "-baseurl:") == 1 {
                print substr($0, length(mark "-baseurl:") + 1)
                skip = 1
                next
            }
            index($0, mark " ") == 1 { print substr($0, length(mark " ") + 1); next }
            { print }
        ' "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"
    done
    EL_ON_ORIGIN=0
    echo "Restored EL vendor repos to their mirrorlist"
}

# Called by retry() after a failed attempt; $1 = attempt number, $2 = command.
pkg_retry_recover() {
    local attempt="$1" cmd="$2"
    case "${cmd##*/}" in
        dnf|yum) ;;
        *) return 0 ;;
    esac
    if (( attempt >= 2 )) && [ "${EL_ON_ORIGIN}" = 0 ]; then
        el_switch_to_origin
    fi
    "$cmd" clean metadata >/dev/null 2>&1 || true
}

# Retry function: tries a command multiple times, recovering between attempts
retry() {
    local -r max_attempts="$1"
    shift
    local attempt=1
    while (( attempt <= max_attempts )); do
        echo "Attempt ${attempt} to run: $*"
        if "$@"; then
            return 0
        fi
        if (( attempt < max_attempts )); then
            pkg_retry_recover "$attempt" "$1"
            echo "Attempt ${attempt} failed. Waiting $(( RETRY_SLEEP * attempt )) seconds before retry..."
            sleep $(( RETRY_SLEEP * attempt ))
        fi
        ((attempt++))
    done
    echo "All ${max_attempts} attempts failed for: $*"
    return 1
}
