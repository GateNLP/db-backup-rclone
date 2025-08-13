FROM alpine:3.22 AS base
ARG TARGETARCH
# Install rclone and create a temporary dir for the backup files
ARG VERSION_RCLONE=current
RUN wget https://downloads.rclone.org/${VERSION_RCLONE#current}/rclone-${VERSION_RCLONE}-linux-${TARGETARCH/aarch/arm}.zip -O rclone.zip && \
    unzip -j rclone.zip 'rclone*/rclone' -d /usr/local/bin && \
    rm rclone.zip && \
    addgroup -g 1001 dbbackup && \
    adduser -u 1001 -G dbbackup -D dbbackup && \
    install -d -o 1001 -g 1001 -m 1777 /scratch

RUN --mount=type=cache,target=/etc/apk/cache apk add --update-cache rage envsubst

# Tell rclone not to attempt to read/write a config file by default - all
# configuration will be coming from environment variables
ENV RCLONE_CONFIG=/dev/null
# Assume RCLONE_CONFIG_STORE_* for configuration by default
ENV REMOTE_NAME=store
WORKDIR /scratch

COPY common.sh /common.sh

FROM base AS postgresql

RUN --mount=type=cache,target=/etc/apk/cache apk add postgresql17-client

COPY postgresql/backup.sh /backup.sh

USER 1001:1001

ENTRYPOINT ["/backup.sh"]

FROM base AS mariadb

RUN --mount=type=cache,target=/etc/apk/cache apk add mariadb-client

COPY mariadb/backup.sh /backup.sh

USER 1001:1001

ENTRYPOINT ["/backup.sh"]
