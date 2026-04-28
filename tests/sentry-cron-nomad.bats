#!/usr/bin/env bats
# Tests for bin/sentry-cron-nomad.sh
#
# The CI coverage hook (set -T + DEBUG trap on */bin/*.sh via BASH_SOURCE)
# only fires under bash, so every test invokes the script via `bash "$SCRIPT"`
# rather than letting the POSIX-sh shebang pick BusyBox ash.

bats_require_minimum_version 1.5.0

SCRIPT="${BATS_TEST_DIRNAME}/../bin/sentry-cron-nomad.sh"

setup() {
    TMPDIR_TEST=$(mktemp -d)
    export TMPDIR_TEST
    export CURL_LOG="${TMPDIR_TEST}/curl.log"

    # curl stub: records each invocation's method/headers/body/URL to $CURL_LOG,
    # and chooses output based on the URL + a handful of env toggles.
    cat > "${TMPDIR_TEST}/curl" <<'STUB'
#!/usr/bin/env bash
set -u
log=${CURL_LOG:-/tmp/curl.log}
method="GET"
url=""
echo "---CALL---" >> "$log"
while [ $# -gt 0 ]; do
    case "$1" in
        --silent|--show-error) ;;
        -X) shift; method="$1"; echo "METHOD: $1" >> "$log" ;;
        --header|-H) shift; echo "HEADER: $1" >> "$log" ;;
        --data-raw|--data|-d) shift; echo "BODY: $1" >> "$log" ;;
        http://*|https://*) url="$1"; echo "URL: $1" >> "$log" ;;
        *) echo "ARG: $1" >> "$log" ;;
    esac
    shift
done
echo "FINAL_METHOD: $method" >> "$log"

case "$url" in
    http://nomad:4646/*)
        [ "${CURL_NOMAD_FAIL:-0}" = "1" ] && exit 7
        [ -n "${NOMAD_FIXTURE:-}" ] && cat "$NOMAD_FIXTURE"
        ;;
    *)
        [ -n "${CURL_SENTRY_STDOUT:-}" ] && printf '%s' "$CURL_SENTRY_STDOUT"
        ;;
esac
exit 0
STUB
    chmod +x "${TMPDIR_TEST}/curl"
    export PATH="${TMPDIR_TEST}:${PATH}"

    # Baseline env so unrelated tests don't trip the "empty" warnings.
    export HOST_ENVIRONMENT="tst"
    export NOMAD_ALLOC_ID="alloc-abc123"
    export NOMAD_JOB_ID="my-job"
    export SENTRY_CRONS="https://sentry.example.com/api/0/monitors/my-slug/checkins/?sentry_key=KEY"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

# --- helpers ---------------------------------------------------------------

write_fixture() {
    # write_fixture <json>
    printf '%s' "$1" > "$TMPDIR_TEST/alloc.json"
    export NOMAD_FIXTURE="$TMPDIR_TEST/alloc.json"
}

fixture_main_ok() {
    write_fixture '{
        "AllocatedResources": {
            "TaskLifecycles": {
                "main": null,
                "sentry-cron-start": {"Hook": "prestart"},
                "sentry-cron-stop":  {"Hook": "poststop"}
            }
        },
        "TaskStates": {
            "main":              {"Failed": false},
            "sentry-cron-start": {"Failed": false},
            "sentry-cron-stop":  {"Failed": false}
        }
    }'
}

fixture_main_failed() {
    write_fixture '{
        "AllocatedResources": {
            "TaskLifecycles": {
                "main": null,
                "sentry-cron-start": {"Hook": "prestart"}
            }
        },
        "TaskStates": {
            "main":              {"Failed": true},
            "sentry-cron-start": {"Failed": false}
        }
    }'
}

fixture_prestart_failed_main_ok() {
    # Non-main task failed; should NOT flip status to error.
    write_fixture '{
        "AllocatedResources": {
            "TaskLifecycles": {
                "main": null,
                "sentry-cron-start": {"Hook": "prestart"}
            }
        },
        "TaskStates": {
            "main":              {"Failed": false},
            "sentry-cron-start": {"Failed": true}
        }
    }'
}

fixture_multi_main_one_failed() {
    write_fixture '{
        "AllocatedResources": {
            "TaskLifecycles": {
                "main-a": null,
                "main-b": null,
                "sidecar": {"Hook": "prestart"}
            }
        },
        "TaskStates": {
            "main-a":  {"Failed": false},
            "main-b":  {"Failed": true},
            "sidecar": {"Failed": false}
        }
    }'
}

fixture_multi_main_all_ok() {
    write_fixture '{
        "AllocatedResources": {
            "TaskLifecycles": {
                "main-a": null,
                "main-b": null
            }
        },
        "TaskStates": {
            "main-a": {"Failed": false},
            "main-b": {"Failed": false}
        }
    }'
}

# --- sentry-cron-start -----------------------------------------------------

@test "sentry-cron-start: POSTs to SENTRY_CRONS with Content-Type application/json and no query params" {
    export NOMAD_TASK_NAME="sentry-cron-start"
    run --separate-stderr bash "$SCRIPT" '*/5 * * * *' 'Europe/Berlin'
    [ "$status" -eq 0 ]

    grep -qxF "URL: $SENTRY_CRONS" "$CURL_LOG"
    grep -qxF "METHOD: POST" "$CURL_LOG"
    grep -qxF "HEADER: Content-Type: application/json" "$CURL_LOG"
}

@test "sentry-cron-start: body carries monitor_config, environment, check_in_id, status=in_progress" {
    export NOMAD_TASK_NAME="sentry-cron-start"
    run --separate-stderr bash "$SCRIPT" '*/5 * * * *' 'Europe/Berlin'
    [ "$status" -eq 0 ]

    body=$(grep '^BODY: ' "$CURL_LOG" | sed 's/^BODY: //')
    [ -n "$body" ]
    echo "$body" | grep -qF '"monitor_config"'
    echo "$body" | grep -qF '"schedule":{"type":"crontab","value":"*/5 * * * *"}'
    echo "$body" | grep -qF '"timezone":"Europe/Berlin"'
    echo "$body" | grep -qF '"failure_issue_threshold":1'
    echo "$body" | grep -qF '"recovery_threshold":1'
    echo "$body" | grep -qF '"environment":"tst"'
    echo "$body" | grep -qF '"status":"in_progress"'
}

@test "sentry-cron-start: check_in_id is the raw NOMAD_ALLOC_ID" {
    export NOMAD_TASK_NAME="sentry-cron-start"
    export NOMAD_ALLOC_ID="01234567-89ab-cdef-0123-456789abcdef"

    run --separate-stderr bash "$SCRIPT" '* * * * *' 'UTC'
    [ "$status" -eq 0 ]

    body=$(grep '^BODY: ' "$CURL_LOG" | sed 's/^BODY: //')
    echo "$body" | grep -qF '"check_in_id":"01234567-89ab-cdef-0123-456789abcdef"'
}

@test "sentry-cron-start: empty curl stdout does not trigger debug dump" {
    export NOMAD_TASK_NAME="sentry-cron-start"
    run --separate-stderr bash "$SCRIPT" '* * * * *' 'UTC'
    [ "$status" -eq 0 ]
    ! echo "$stderr" | grep -q '^Error:'
    ! echo "$stderr" | grep -q '^Data:'
}

@test "sentry-cron-start: non-empty curl stdout triggers debug dump to stderr" {
    export NOMAD_TASK_NAME="sentry-cron-start"
    export CURL_SENTRY_STDOUT='something went wrong'
    run --separate-stderr bash "$SCRIPT" '* * * * *' 'UTC'
    [ "$status" -eq 0 ]

    echo "$stderr" | grep -qF 'Error: something went wrong'
    echo "$stderr" | grep -qF 'Data:'
    echo "$stderr" | grep -qF 'CRON=* * * * *'
    echo "$stderr" | grep -qF 'TIMEZONE=UTC'
    echo "$stderr" | grep -qxF "CHECK_IN_ID=${NOMAD_ALLOC_ID}"
    # env dump is included; HOST_ENVIRONMENT is in there
    echo "$stderr" | grep -qF 'HOST_ENVIRONMENT=tst'
}

# --- sentry-cron-stop ------------------------------------------------------

@test "sentry-cron-stop: zero failed main tasks => status=ok" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    fixture_main_ok
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]

    grep -qE '^URL: https://sentry\.example\.com/.*status=ok($|&)' "$CURL_LOG"
    ! grep -qE '^URL: https://sentry\.example\.com/.*status=error' "$CURL_LOG"
}

@test "sentry-cron-stop: a failed main task => status=error" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    fixture_main_failed
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]

    grep -qE '^URL: https://sentry\.example\.com/.*status=error($|&)' "$CURL_LOG"
    ! grep -qE '^URL: https://sentry\.example\.com/.*status=ok' "$CURL_LOG"
}

@test "sentry-cron-stop: failed non-main (prestart) task is ignored => status=ok" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    fixture_prestart_failed_main_ok
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]

    grep -qE '^URL: https://sentry\.example\.com/.*status=ok' "$CURL_LOG"
    ! grep -qE '^URL: https://sentry\.example\.com/.*status=error' "$CURL_LOG"
}

@test "sentry-cron-stop: multiple main tasks, one failed => status=error" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    fixture_multi_main_one_failed
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -qE '^URL: https://sentry\.example\.com/.*status=error' "$CURL_LOG"
}

@test "sentry-cron-stop: multiple main tasks, all ok => status=ok" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    fixture_multi_main_all_ok
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -qE '^URL: https://sentry\.example\.com/.*status=ok' "$CURL_LOG"
}

@test "sentry-cron-stop: sentry URL carries environment and check_in_id as query params" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    fixture_main_ok
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]

    sentry_url=$(grep '^URL: https://sentry' "$CURL_LOG" | sed 's/^URL: //')
    [ -n "$sentry_url" ]
    echo "$sentry_url" | grep -qF "environment=tst"
    echo "$sentry_url" | grep -qF "check_in_id=$NOMAD_ALLOC_ID"
}

@test "sentry-cron-stop: Nomad API failure falls back to status=ok and logs to stderr" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    export CURL_NOMAD_FAIL=1
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]

    grep -qE '^URL: https://sentry\.example\.com/.*status=ok' "$CURL_LOG"
    echo "$stderr" | grep -qF "curl for main task of my-job failed"
}

@test "sentry-cron-stop: DEBUG=true logs FAILED_COUNT line (ok path)" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    export DEBUG=true
    fixture_main_ok
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$stderr" | grep -qF "FAILED_COUNT for main tasks of my-job is 0, sending status 'ok'."
}

@test "sentry-cron-stop: DEBUG=true logs FAILED_COUNT line (error path)" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    export DEBUG=true
    fixture_main_failed
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$stderr" | grep -qF "FAILED_COUNT for main tasks of my-job is 1, sending status 'error'."
}

# --- empty-env warnings ----------------------------------------------------

@test "warns when HOST_ENVIRONMENT is empty" {
    export NOMAD_TASK_NAME="sentry-cron-start"
    unset HOST_ENVIRONMENT
    run --separate-stderr bash "$SCRIPT" '* * * * *' 'UTC'
    [ "$status" -eq 0 ]
    echo "$stderr" | grep -qF "WARNING: HOST_ENVIRONMENT is empty"
}

@test "warns when NOMAD_ALLOC_ID is empty" {
    export NOMAD_TASK_NAME="sentry-cron-start"
    unset NOMAD_ALLOC_ID
    run --separate-stderr bash "$SCRIPT" '* * * * *' 'UTC'
    [ "$status" -eq 0 ]
    echo "$stderr" | grep -qF "WARNING: NOMAD_ALLOC_ID is empty"
}

@test "warns when SENTRY_CRONS is empty" {
    export NOMAD_TASK_NAME="sentry-cron-start"
    unset SENTRY_CRONS
    run --separate-stderr bash "$SCRIPT" '* * * * *' 'UTC'
    [ "$status" -eq 0 ]
    echo "$stderr" | grep -qF "WARNING: SENTRY_CRONS is empty"
}

# --- dispatch & exit-code invariants ---------------------------------------

@test "unknown NOMAD_TASK_NAME warns, exits 0, and does not call curl" {
    export NOMAD_TASK_NAME="main"
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$stderr" | grep -qF "'main' are not handled"
    # Stub only writes "---CALL---" when curl is invoked; log must stay empty.
    [ ! -s "$CURL_LOG" ]
}

@test "exit status is 0 even when Nomad call fails" {
    export NOMAD_TASK_NAME="sentry-cron-stop"
    export CURL_NOMAD_FAIL=1
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "exit status is 0 when sentry call returns an error body (start path)" {
    export NOMAD_TASK_NAME="sentry-cron-start"
    export CURL_SENTRY_STDOUT='{"detail":"bad"}'
    run --separate-stderr bash "$SCRIPT" '* * * * *' 'UTC'
    [ "$status" -eq 0 ]
}
