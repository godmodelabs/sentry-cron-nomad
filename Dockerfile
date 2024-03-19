FROM alpine:latest

ADD --chmod=755 sentry-cron-poststop.sh /
ADD --chmod=755 sentry-cron-prestart.sh /

RUN apk add --no-cache curl jq

CMD ["/sentry-cron-poststop.sh"]
