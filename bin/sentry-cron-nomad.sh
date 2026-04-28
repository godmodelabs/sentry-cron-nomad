#!/usr/bin/env sh
[ "${DEBUG}" = "true" ] &&
    set -x
CRON=${1}
TIMEZONE=${2}
[ -z "${HOST_ENVIRONMENT}" ] && echo "WARNING: HOST_ENVIRONMENT is empty for ${NOMAD_JOB_ID} (${NOMAD_TASK_NAME}); Sentry will route check-ins to the default 'production' environment." >&2
[ -z "${NOMAD_ALLOC_ID}" ] && echo "WARNING: NOMAD_ALLOC_ID is empty for ${NOMAD_JOB_ID} (${NOMAD_TASK_NAME})." >&2
[ -z "${SENTRY_CRONS}" ] && echo "WARNING: SENTRY_CRONS is empty for ${NOMAD_JOB_ID} (${NOMAD_TASK_NAME})." >&2
CHECK_IN_ID="${NOMAD_ALLOC_ID}"
case "${NOMAD_TASK_NAME}" in
    sentry-cron-start)
        # Configure cron in Sentry and tell Sentry about the start
        ERROR=$(curl --silent --show-error -X POST "${SENTRY_CRONS}" \
            --header 'Content-Type: application/json' \
            --data-raw '{"monitor_config":{"schedule":{"type":"crontab","value":"'"${CRON}"'"},"timezone":"'"${TIMEZONE}"'","failure_issue_threshold":1,"recovery_threshold":1},"environment":"'"${HOST_ENVIRONMENT}"'","check_in_id":"'"${CHECK_IN_ID}"'","status":"in_progress"}')
        if [ "${ERROR}" != '' ]; then
            env >&2
            echo "CRON=${CRON}" >&2
            echo "TIMEZONE=${TIMEZONE}" >&2
            echo "CHECK_IN_ID=${CHECK_IN_ID}" >&2
            echo "Data:" >&2
            echo '{"monitor_config":{"schedule":{"type":"crontab","value":"'"${CRON}"'"},"timezone":"'"${TIMEZONE}"'","failure_issue_threshold":1,"recovery_threshold":1},"environment":"'"${HOST_ENVIRONMENT}"'","check_in_id":"'"${CHECK_IN_ID}"'","status":"in_progress"}' >&2
            echo "Error: ${ERROR}" >&2
        fi
        ;;
    sentry-cron-stop)
        # Get fail state of main task and tell sentry about it
        if ALLOCATION=$(curl --silent http://nomad:4646/v1/allocation/"${NOMAD_ALLOC_ID}"); then
            # shellcheck disable=SC2016
            FAILED_COUNT=$(echo "${ALLOCATION}" | jq '. as $allocation | .AllocatedResources.TaskLifecycles | to_entries[] | select( .value == null) | [.key] | map(["TaskStates", ., "Failed"]) as $paths | $allocation | getpath($paths | flatten) | select(. == true)' | wc -l)
            if [ "${FAILED_COUNT}" -eq 0 ]; then
                [ "${DEBUG}" = "true" ] &&
                    echo "FAILED_COUNT for main tasks of ${NOMAD_JOB_ID} is ${FAILED_COUNT}, sending status 'ok'." >&2
                curl --silent "${SENTRY_CRONS}?environment=${HOST_ENVIRONMENT}&check_in_id=${CHECK_IN_ID}&status=ok"
            else
                [ "${DEBUG}" = "true" ] &&
                    echo "FAILED_COUNT for main tasks of ${NOMAD_JOB_ID} is ${FAILED_COUNT}, sending status 'error'." >&2
                curl --silent "${SENTRY_CRONS}?environment=${HOST_ENVIRONMENT}&check_in_id=${CHECK_IN_ID}&status=error"
            fi
        else
            echo "curl for main task of ${NOMAD_JOB_ID} failed, received '${ALLOCATION}', sending status 'ok'." >&2
            curl --silent "${SENTRY_CRONS}?environment=${HOST_ENVIRONMENT}&check_in_id=${CHECK_IN_ID}&status=ok"
        fi
        ;;
    *)
        echo "NOMAD_TASK_NAMEs named '${NOMAD_TASK_NAME}' are not handled yet here." >&2
        ;;
esac
exit 0
