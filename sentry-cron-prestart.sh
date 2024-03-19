#!/bin/sh
# Configure cron in Sentry and tell Sentry about the start
CRON=${1}
TIMEZONE=${2}
TEMP=$(printf '%s' "${NOMAD_JOB_ID}" | md5sum )
CHECK_IN_ID=${TEMP%  -}
# echo "Start of main task of ${NOMAD_JOB_ID}: Cron: ${CRON}(${TIMEZONE}), Check-in ID ${CHECK_IN_ID}" >&2
curl --silent --show-error -X POST "${SENTRY_CRONS}" \
  --header 'Content-Type: application/json' \
  --data-raw '{"monitor_config":{"schedule":{"type":"crontab","value":"'"${CRON}"'","timezone":"'"${TIMEZONE}"'"}},"failure_issue_threshold":1,"recovery_threshold":1,"environment":"'"${APP_ENV}"'","check_in_id":"'"${CHECK_IN_ID}"'","status":"in_progress"}'
exit 0
