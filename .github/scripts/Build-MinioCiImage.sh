#!/usr/bin/env bash
set -euo pipefail

minio_version="RELEASE.2025-10-15T17-29-55Z"
minio_commit="9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a"
minio_repository="https://github.com/minio/minio.git"
minio_image="dbatools/minio-ci:${minio_version}"
required_go_version="go1.24.8"
repository_root="$(git rev-parse --show-toplevel)"
build_root="$(mktemp -d "${RUNNER_TEMP:?RUNNER_TEMP must be set}/dbatools-minio.XXXXXX")"
source_root="${build_root}/source"
image_root="${build_root}/image"

git clone \
    --branch "${minio_version}" \
    --depth 1 \
    --single-branch \
    "${minio_repository}" \
    "${source_root}"

actual_commit="$(git -C "${source_root}" rev-parse HEAD)"
if [[ "${actual_commit}" != "${minio_commit}" ]]; then
    echo "Expected MinIO commit ${minio_commit}, received ${actual_commit}." >&2
    exit 1
fi

actual_tag="$(git -C "${source_root}" describe --tags --exact-match)"
if [[ "${actual_tag}" != "${minio_version}" ]]; then
    echo "Expected MinIO tag ${minio_version}, received ${actual_tag}." >&2
    exit 1
fi

read -r _ _ actual_go_version _ <<< "$(go version)"
if [[ "${actual_go_version}" != "${required_go_version}" ]]; then
    echo "Expected ${required_go_version}, received ${actual_go_version}." >&2
    exit 1
fi

export GOTOOLCHAIN=local

pushd "${source_root}" > /dev/null
go mod verify
MINIO_RELEASE=RELEASE make build
popd > /dev/null

# Assert minio --version reports the pinned release before packaging it.
minio_version_output="$("${source_root}/minio" --version)"
if [[ "${minio_version_output}" != *"${minio_version}"* ]]; then
    echo "Built MinIO did not report ${minio_version}: ${minio_version_output}" >&2
    exit 1
fi

mkdir -p "${image_root}"
cp "${source_root}/minio" "${image_root}/minio"
for notice_file in LICENSE NOTICE CREDITS; do
    cp "${source_root}/${notice_file}" "${image_root}/${notice_file}"
done

docker build \
    --pull=false \
    --tag "${minio_image}" \
    --build-arg "MINIO_VERSION=${minio_version}" \
    --build-arg "MINIO_COMMIT=${minio_commit}" \
    --file "${repository_root}/.github/docker/minio/Dockerfile" \
    "${image_root}"

docker image inspect "${minio_image}" > /dev/null
echo "Built ${minio_image} from ${minio_commit}."
