#!/bin/sh
# Get fail state of main task and tell sentry about it
TEMP=$(printf '%s' "${NOMAD_JOB_ID}" | md5sum )
CHECK_IN_ID=${TEMP%  -}
FAILED=$(curl --silent http://nomad:4646/v1/allocation/${NOMAD_ALLOC_ID} \
            | jq '.TaskStates."'"${NOMAD_JOB_PARENT_ID}"'".Failed')
if [ "X${FAILED}" == 'Xfalse' ]
then
    # echo "Failed for main task of ${NOMAD_JOB_ID} is ${FAILED}, sending status 'ok'." >&2
    curl --silent "${SENTRY_CRONS}?environment=${APP_ENV}&check_in_id=${CHECK_IN_ID}&status=ok"
else
    # echo "Failed for main task of ${NOMAD_JOB_ID} is ${FAILED}, sending status 'error'." >&2
    curl --silent "${SENTRY_CRONS}?environment=${APP_ENV}&check_in_id=${CHECK_IN_ID}&status=error"
fi
exit 0
