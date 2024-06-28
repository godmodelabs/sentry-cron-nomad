FROM alpine:3

ADD --chmod=755 sentry-cron-nomad.sh /

RUN apk add --no-cache curl jq

RUN addgroup -S nonroot \
    && adduser -S nonroot -G nonroot
USER nonroot

ENTRYPOINT ["/sentry-cron-nomad.sh"]
