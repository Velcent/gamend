# The load generator: k6 plus this harness, parked in the same region as the
# bench app so the numbers are the server's and not the internet's.
#
# It runs nothing on boot. Runs are launched one at a time over SSH, which
# keeps the output streaming back to whoever started it:
#
#   fly ssh console -a gamend-k6 -C "k6 run -e BASE_URL=http://gamend-bench.internal:4000 /scripts/scenarios/me.js"
#
# Summaries land in /results and come back with `fly ssh sftp get`.
FROM grafana/k6:latest

USER root

# node is not in the k6 image; report.mjs needs it to render a run in place
# rather than making every look at the numbers a download first.
RUN apk add --no-cache nodejs bash

COPY . /scripts
RUN mkdir -p /results && chmod -R a+rx /scripts

WORKDIR /scripts
ENV RESULTS_DIR=/results

# k6's own entrypoint is the k6 binary; the machine has to stay up between
# runs instead, so SSH has something to attach to.
ENTRYPOINT []
CMD ["sleep", "infinity"]
