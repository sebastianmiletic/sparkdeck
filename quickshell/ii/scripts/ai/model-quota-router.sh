#!/usr/bin/env bash
set -euo pipefail

state_file="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/ai-model-usage.json"
lock_file="${state_file}.lock"
today="$(TZ=America/Los_Angeles date +%F)"
skip_seconds=600

canonical_model() {
    case "$1" in
        gemini-3-flash-preview) echo "gemini-3-flash" ;;
        gemini-3.7-flash-preview) echo "gemini-3.7-flash" ;;
        gemini-3.6-flash-preview) echo "gemini-3.6-flash" ;;
        gemini-3.5-flash-lite-preview) echo "gemini-3.5-flash-lite" ;;
        gemini-3.1-flash-lite-preview) echo "gemini-3.1-flash-lite" ;;
        gemini-flash-latest) echo "gemini-2.5-flash" ;;
        gemini-flash-lite-latest) echo "gemini-2.5-flash-lite" ;;
        *) echo "$1" ;;
    esac
}

api_names_for() {
    case "$(canonical_model "$1")" in
        gemini-3.7-flash) echo "gemini-3.7-flash gemini-3.7-flash-preview" ;;
        gemini-3.6-flash) echo "gemini-3.6-flash gemini-3.6-flash-preview" ;;
        gemini-3-flash) echo "gemini-3-flash-preview gemini-3-flash" ;;
        gemini-3.5-flash-lite) echo "gemini-3.5-flash-lite gemini-3.5-flash-lite-preview" ;;
        gemini-3.1-flash-lite) echo "gemini-3.1-flash-lite gemini-3.1-flash-lite-preview" ;;
        gemini-2.5-flash) echo "gemini-2.5-flash gemini-flash-latest" ;;
        gemini-2.5-flash-lite) echo "gemini-2.5-flash-lite gemini-flash-lite-latest" ;;
        gemini-2.0-flash) echo "gemini-2.0-flash" ;;
        gemini-2.0-flash-lite) echo "gemini-2.0-flash-lite" ;;
        gemma-4-31b-it) echo "gemma-4-31b-it" ;;
        gemma-3-27b-it) echo "gemma-3-27b-it" ;;
        *) echo "$(canonical_model "$1")" ;;
    esac
}

api_name_for() {
    local model="$1" state api
    model="$(canonical_model "$model")"
    state="$(load_state)"
    api="$(jq -r --arg model "$model" '.apiNames[$model] // empty' <<< "$state")"
    if [[ -n "$api" ]]; then
        printf '%s\n' "$api"
        return 0
    fi
    # Prefer the first alias; existence is resolved during next/fallback.
    awk '{print $1}' <<< "$(api_names_for "$model")"
}

quota_for() {
    case "$(canonical_model "$1")" in
        gemini-3.7-flash|gemini-3.6-flash|gemini-3-flash) echo 20 ;;
        gemini-3.5-flash-lite|gemini-3.1-flash-lite) echo 500 ;;
        gemini-2.5-flash) echo 250 ;;
        gemini-2.5-flash-lite) echo 1000 ;;
        gemini-2.0-flash) echo 200 ;;
        gemini-2.0-flash-lite) echo 200 ;;
        gemma-4-31b-it|gemma-3-27b-it) echo 14400 ;;
        *) echo 0 ;;
    esac
}

# Highest-quality first. 503/404 models are skipped, not counted as used.
candidates_for() {
    case "$1" in
        screen)
            echo "gemini-3.7-flash gemini-3.6-flash gemini-3-flash gemini-3.5-flash-lite gemini-3.1-flash-lite gemini-2.5-flash gemini-2.5-flash-lite gemini-2.0-flash gemini-2.0-flash-lite"
            ;;
        text)
            echo "gemini-3.7-flash gemini-3.6-flash gemini-3-flash gemini-3.5-flash-lite gemini-3.1-flash-lite gemini-2.5-flash gemini-2.5-flash-lite gemini-2.0-flash gemini-2.0-flash-lite gemma-4-31b-it gemma-3-27b-it"
            ;;
        *)
            return 1
            ;;
    esac
}

fresh_state() {
    jq -n --arg date "$today" '{date: $date, counts: {}, missing: [], skipped: {}, apiNames: {}}'
}

load_state() {
    mkdir -p "$(dirname "$state_file")"
    if [[ ! -s "$state_file" ]] || [[ "$(jq -r '.date // empty' "$state_file" 2>/dev/null)" != "$today" ]]; then
        fresh_state
    else
        jq -c '{
            date,
            counts: (.counts // {}),
            missing: (.missing // []),
            skipped: (.skipped // {}),
            apiNames: (.apiNames // {})
        }' "$state_file"
    fi
}

save_state() {
    local data="$1" temporary
    temporary="$(mktemp "${state_file}.XXXXXX")"
    printf '%s\n' "$data" > "$temporary"
    mv -f "$temporary" "$state_file"
}

ensure_lock() {
    mkdir -p "$(dirname "$lock_file")"
    if [[ -z "${LOCK_READY:-}" ]]; then
        exec 9>"$lock_file"
        LOCK_READY=1
    fi
}

lock() { ensure_lock; flock 9; }
unlock() { flock -u 9 2>/dev/null || true; }

is_missing() {
    local state="$1" model="$2"
    jq -e --arg model "$model" '.missing | index($model) != null' <<< "$state" >/dev/null
}

is_skipped() {
    local state="$1" model="$2" now
    now="$(date +%s)"
    jq -e --arg model "$model" --argjson now "$now" '
        ((.skipped[$model] // 0) > $now)
    ' <<< "$state" >/dev/null
}

apply_missing() {
    local state="$1" model="$2"
    model="$(canonical_model "$model")"
    jq -c --arg model "$model" --argjson quota "$(quota_for "$model")" '
        .missing = ((.missing // []) + [$model] | unique)
        | .skipped[$model] = 0
    ' <<< "$state"
}

apply_skip() {
    local state="$1" model="$2" until
    model="$(canonical_model "$model")"
    until="$(( $(date +%s) + skip_seconds ))"
    jq -c --arg model "$model" --argjson until "$until" '
        .skipped[$model] = ([((.skipped[$model] // 0)), $until] | max)
    ' <<< "$state"
}

apply_exhaust() {
    local state="$1" model="$2"
    model="$(canonical_model "$model")"
    jq -c --arg model "$model" --argjson quota "$(quota_for "$model")" '
        .counts[$model] = $quota
        | .skipped[$model] = 0
    ' <<< "$state"
}

apply_api_name() {
    local state="$1" model="$2" api="$3"
    model="$(canonical_model "$model")"
    jq -c --arg model "$model" --arg api "$api" '.apiNames[$model] = $api' <<< "$state"
}

apply_commit() {
    local state="$1" model="$2"
    model="$(canonical_model "$model")"
    jq -c --arg model "$model" '.counts[$model] = ((.counts[$model] // 0) + 1)' <<< "$state"
}

mark_missing() {
    lock
    save_state "$(apply_missing "$(load_state)" "$1")"
    unlock
}

mark_skip() {
    lock
    save_state "$(apply_skip "$(load_state)" "$1")"
    unlock
}

mark_exhausted() {
    local quota
    quota="$(quota_for "$1")"
    (( quota > 0 )) || return 0
    lock
    save_state "$(apply_exhaust "$(load_state)" "$1")"
    unlock
}

commit_model() {
    lock
    save_state "$(apply_commit "$(load_state)" "$1")"
    unlock
}

available_model() {
    local profile="$1" state="$2" model count quota
    for model in $(candidates_for "$profile"); do
        quota="$(quota_for "$model")"
        count="$(jq -r --arg model "$model" '.counts[$model] // 0' <<< "$state")"
        if is_missing "$state" "$model"; then
            continue
        fi
        if is_skipped "$state" "$model"; then
            continue
        fi
        if (( count < quota )); then
            printf '%s\n' "$model"
            return 0
        fi
    done
    return 1
}

# Live generate ping. GET /models can 200 while generateContent returns 503.
health_check() {
    local api_name="$1" code
    [[ -n "${API_KEY:-}" ]] || return 0
    code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
        --connect-timeout 3 --max-time 6 \
        -H "x-goog-api-key: ${API_KEY}" \
        -H "Content-Type: application/json" \
        --data '{"contents":[{"role":"user","parts":[{"text":"ok"}]}],"generationConfig":{"temperature":0,"maxOutputTokens":1}}' \
        "https://generativelanguage.googleapis.com/v1beta/models/${api_name}:generateContent" \
        2>/dev/null || echo 000)"
    case "$code" in
        2*) return 0 ;;
        404) return 4 ;;
        429) return 9 ;;
        *) return 1 ;;
    esac
}

pick_existing() {
    local profile="$1" state model api_name hc saw_live_error
    while true; do
        lock
        state="$(load_state)"
        model="$(available_model "$profile" "$state" || true)"
        unlock
        [[ -n "$model" ]] || return 1

        saw_live_error=0
        for api_name in $(api_names_for "$model"); do
            hc=0
            health_check "$api_name" || hc=$?
            if (( hc == 0 )); then
                lock
                state="$(apply_api_name "$(load_state)" "$model" "$api_name")"
                save_state "$state"
                unlock
                printf '%s\n' "$model"
                return 0
            fi
            if (( hc == 4 )); then
                continue
            fi
            saw_live_error=1
            lock
            state="$(load_state)"
            if (( hc == 9 )); then
                state="$(apply_exhaust "$state" "$model")"
            else
                state="$(apply_skip "$state" "$model")"
            fi
            save_state "$state"
            unlock
            break
        done
        if (( saw_live_error == 0 )); then
            lock
            save_state "$(apply_missing "$(load_state)" "$model")"
            unlock
        fi
    done
}

peek_next() {
    local profile="$1" state
    lock
    state="$(load_state)"
    available_model "$profile" "$state" || true
    unlock
}

next_model() {
    pick_existing "${1:?Missing request profile}"
}

fallback_model() {
    local profile="${1:?Missing request profile}"
    local model="${2:?Missing exhausted model}"
    local reason="${3:-skip}"
    case "$reason" in
        exhaust) mark_exhausted "$model" ;;
        missing) mark_missing "$model" ;;
        *) mark_skip "$model" ;;
    esac
    pick_existing "$profile"
}

status_json() {
    local state
    lock
    state="$(load_state)"
    jq -c \
        --arg text "$(available_model text "$state" || true)" \
        --arg screen "$(available_model screen "$state" || true)" \
        '. + {current: {text: $text, screen: $screen}}' <<< "$state"
    unlock
}

case "${1:-}" in
    next)
        next_model "${2:?Missing request profile}"
        ;;
    peek)
        peek_next "${2:?Missing request profile}"
        ;;
    fallback)
        fallback_model "${2:?Missing request profile}" "${3:?Missing model}" "${4:-skip}"
        ;;
    commit)
        commit_model "${2:?Missing model name}"
        ;;
    exhaust)
        mark_exhausted "${2:?Missing model name}"
        ;;
    missing)
        mark_missing "${2:?Missing model name}"
        ;;
    skip)
        mark_skip "${2:?Missing model name}"
        ;;
    api-name)
        api_name_for "${2:?Missing model name}"
        ;;
    status)
        status_json
        ;;
    *)
        echo "Usage: $0 {next PROFILE|peek PROFILE|fallback PROFILE MODEL [skip|missing|exhaust]|commit MODEL|exhaust MODEL|missing MODEL|skip MODEL|api-name MODEL|status}" >&2
        exit 2
        ;;
esac
