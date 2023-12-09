FROM cgr.dev/chainguard/wolfi-base

RUN mkdir /app /data
COPY ./otmonitor-x64 /app/otmonitor

CMD ["/app/otmonitor", "--daemon", "-w8080", "-f/data/otmonitor.conf"]
