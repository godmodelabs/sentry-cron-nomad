FROM alpine:3

COPY --chmod=755 bin/* /usr/local/bin/

RUN apk add --no-cache curl jq

USER nobody

ENTRYPOINT ["/usr/local/bin/sentry-cron-nomad.sh"]
