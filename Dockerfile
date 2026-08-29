FROM cgr.dev/chainguard/wolfi-base

LABEL org.opencontainers.image.authors="Schelte Bron <otgw@tclcode.com>"

RUN apk add tzdata
RUN mkdir -p /usr/local/bin; mkdir -p -m a=rwx /data /log
COPY ./otmonitor-x64 /usr/local/bin/otmonitor

EXPOSE 8080

ENTRYPOINT ["otmonitor", "--daemon", "--dbfile=/data/auth.db", "-f/data/otmonitor.conf"]
CMD ["-w8080"]
WORKDIR /log
