FROM scratch

ARG MINIO_VERSION
ARG MINIO_COMMIT

LABEL org.opencontainers.image.title="MinIO CI fixture" \
      org.opencontainers.image.description="Ephemeral MinIO server for dbatools integration tests" \
      org.opencontainers.image.source="https://github.com/minio/minio" \
      org.opencontainers.image.version="${MINIO_VERSION}" \
      org.opencontainers.image.revision="${MINIO_COMMIT}" \
      org.opencontainers.image.licenses="AGPL-3.0-only"

ENV HOME=/root \
    TMPDIR=/tmp

WORKDIR /root
WORKDIR /tmp
WORKDIR /data

COPY minio /usr/bin/minio
COPY LICENSE NOTICE CREDITS /usr/share/licenses/minio/

VOLUME ["/data"]
EXPOSE 9000 9001
ENTRYPOINT ["/usr/bin/minio"]
