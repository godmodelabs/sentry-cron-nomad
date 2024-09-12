#!/bin/sh
CRON=${1}
TIMEZONE=${2}
# Generate Sentry Cron Checkin-ID from Nomad Job ID as Sentry does not like special characters in it 
TEMP=$(printf '%s' "${NOMAD_ALLOC_ID}" | md5sum )
CHECK_IN_ID=${TEMP%  -}
case "${NOMAD_TASK_NAME}" in
    sentry-cron-start)
        # Configure cron in Sentry and tell Sentry about the start
        ERROR=$(curl --silent --show-error -X POST "${SENTRY_CRONS}" \
        --header 'Content-Type: application/json' \
        --data-raw '{"monitor_config":{"schedule":{"type":"crontab","value":"'"${CRON}"'"},"timezone":"'"${TIMEZONE}"'","failure_issue_threshold":1,"recovery_threshold":1},"environment":"'"${HOST_ENVIRONMENT}"'","check_in_id":"'"${CHECK_IN_ID}"'","status":"in_progress"}' )
        if [ ! "X${ERROR}" = 'X' ]
        then
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
        if ALLOCATION=$(curl --silent http://nomad:4646/v1/allocation/"${NOMAD_ALLOC_ID}" );
        then
            FAILED=$(echo "${ALLOCATION}" | jq '.TaskStates."'"${NOMAD_JOB_PARENT_ID}"'".Failed' )
            if [ "X${FAILED}" = 'Xfalse' ]
            then
                # echo "Failed for main task of ${NOMAD_JOB_ID} is ${FAILED}, sending status 'ok'." >&2
                curl --silent "${SENTRY_CRONS}?environment=${HOST_ENVIRONMENT}&check_in_id=${CHECK_IN_ID}&status=ok"
            else
                # echo "Failed for main task of ${NOMAD_JOB_ID} is ${FAILED}, sending status 'error'." >&2
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
