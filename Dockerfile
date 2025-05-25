FROM alpine:3

COPY --chmod=755 sentry-cron-nomad.sh /

RUN apk add --no-cache curl jq

USER nobody

ENTRYPOINT ["/sentry-cron-nomad.sh"]
