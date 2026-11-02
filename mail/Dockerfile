# Mail container for the n8n workshop (kingo service `mail`).
# The only place with the mailbox password; talks to n8n only through Postgres.
# Alpine 3.24: isync (mbsync) 1.5.1, notmuch 0.40, goimapnotify 2.5.4, Python 3.14, psycopg 3.3.
# Built with podman, like the rest of kingo (docker works too). The image name is fully qualified,
# so podman never has to ask which registry a short name means.
FROM docker.io/library/alpine:3.24

# py3-psycopg does not pull in libpq, which it loads only at run time; the import fails the build
# instead of the first start.
RUN apk add --no-cache isync notmuch goimapnotify python3 py3-psycopg libpq tini ca-certificates tzdata \
 && python3 -c 'import psycopg' \
 && adduser -D -H -u 1000 -h /data mailbox \
 && mkdir -p /data /opt/case \
 && chown mailbox:mailbox /data

COPY mailcontainer /opt/mail/mailcontainer
COPY mailctl /usr/local/bin/mailctl
RUN chmod 755 /usr/local/bin/mailctl

# A fresh named volume takes the owner of /data from the image, so the service can write it.
ENV PYTHONPATH=/opt/mail PYTHONUNBUFFERED=1 MAIL_DATA=/data MAIL_CASE=/opt/case HOME=/data
USER mailbox
WORKDIR /data
VOLUME /data

# tini passes SIGTERM on; the service finishes the mail it is sending, then stops.
# Give it longer than the SMTP timeout (30 s): stop_grace_period 60s in compose.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["mailctl", "run"]
