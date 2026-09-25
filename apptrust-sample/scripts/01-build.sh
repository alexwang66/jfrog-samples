#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Step 1: Build the Docker image, push to the DEV repo with build-info, and
# publish build-info to Artifactory so the AppTrust version can source from it.
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export APPTRUST_IGNORE_VERSION_STATE=1
source "${SCRIPT_DIR}/config.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

require docker
require jf

retry() {
  local attempts="$1" delay="$2"
  shift 2
  local attempt=1
  until "$@"; do
    if (( attempt >= attempts )); then
      return 1
    fi
    warn "Command failed (attempt ${attempt}/${attempts}); retrying in ${delay}s"
    sleep "${delay}"
    ((attempt++))
  done
}

[[ -n "${REGISTRY_HOST}" ]] || die "REGISTRY_HOST could not be resolved from jf config"

[[ "${APP_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
  || die "APP_VERSION must use numeric SemVer (for example, 2.3.0)"

while :; do
  IMAGE_TAG="${APP_VERSION}"
  BUILD_NUMBER="${APP_VERSION}"
  REMOTE_MANIFEST="${DOCKER_REPO_DEV}/${IMAGE_NAME}/${IMAGE_TAG}/manifest.json"
  REMOTE_MANIFEST_COUNT="$(jf rt search "${REMOTE_MANIFEST}" \
    --server-id "${JF_SERVER_ID}" --count)"
  if [[ "${REMOTE_MANIFEST_COUNT}" == "0" ]]; then
    break
  fi
  IFS=. read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<< "${APP_VERSION}"
  APP_VERSION="${VERSION_MAJOR}.${VERSION_MINOR}.$((VERSION_PATCH + 1))"
  warn "Image tag already exists; trying ${APP_VERSION}"
done

export APP_VERSION IMAGE_TAG BUILD_NUMBER
printf '%s\n' "${APP_VERSION}" > "${VERSION_STATE_FILE}"
ok "Using application version ${APP_VERSION}; saved for the remaining steps"

IMAGE_REF="${REGISTRY_HOST}/${DOCKER_REPO_DEV}/${IMAGE_NAME}:${IMAGE_TAG}"

if [[ -z "${DOCKER_PLATFORM:-}" ]]; then
  DOCKER_ARCH="$(docker info --format '{{.Architecture}}')"
  case "${DOCKER_ARCH}" in
    aarch64|arm64) DOCKER_PLATFORM="linux/arm64" ;;
    x86_64|amd64) DOCKER_PLATFORM="linux/amd64" ;;
    *) die "Unsupported Docker architecture '${DOCKER_ARCH}'; set DOCKER_PLATFORM explicitly" ;;
  esac
fi

say "Building Docker image ${IMAGE_REF} for ${DOCKER_PLATFORM}"
docker build \
  --platform "${DOCKER_PLATFORM}" \
  --label "org.opencontainers.image.title=${IMAGE_NAME}" \
  --label "org.opencontainers.image.version=${APP_VERSION}" \
  --label "org.opencontainers.image.source=https://github.com/jfrog/apptrust-sample" \
  -t "${IMAGE_REF}" \
  "${REPO_ROOT}"
ok "Image built"

say "Logging in to ${REGISTRY_HOST}"
retry 3 5 jf docker login "${REGISTRY_HOST}" --server-id "${JF_SERVER_ID}"

say "Pushing image"
PUSH_LOG="$(mktemp)"
IMAGE_FILE="${PUSH_LOG}.image"
trap 'rm -f "${PUSH_LOG}" "${IMAGE_FILE}"' EXIT
retry 3 5 bash -o pipefail -c 'docker push "$1" 2>&1 | tee "$2"' _ "${IMAGE_REF}" "${PUSH_LOG}"

MANIFEST_DIGEST="$(sed -n 's/.*digest: \(sha256:[0-9a-f]\{64\}\).*/\1/p' "${PUSH_LOG}" | tail -n 1)"
[[ -n "${MANIFEST_DIGEST}" ]] || die "Could not determine the pushed manifest digest"
printf '%s@%s\n' "${IMAGE_REF}" "${MANIFEST_DIGEST}" \
  > "${IMAGE_FILE}"

say "Recording the pushed image in build-info"
retry 3 5 jf rt build-docker-create "${DOCKER_REPO_DEV}" \
  --image-file "${IMAGE_FILE}" \
  --server-id "${JF_SERVER_ID}" \
  --project "${JF_PROJECT}" \
  --build-name "${BUILD_NAME}" \
  --build-number "${BUILD_NUMBER}"
ok "Image pushed to ${DOCKER_REPO_DEV}"

say "Collecting VCS metadata for build-info"
jf rt build-add-git "${BUILD_NAME}" "${BUILD_NUMBER}" \
  --server-id "${JF_SERVER_ID}" \
  --project "${JF_PROJECT}" \
  "${REPO_ROOT}" 2>/dev/null \
  || warn "Skipping build-add-git (not a git repo or git metadata unavailable)"

say "Publishing build-info ${BUILD_NAME}/${BUILD_NUMBER}"
jf rt build-publish "${BUILD_NAME}" "${BUILD_NUMBER}" \
  --server-id "${JF_SERVER_ID}" \
  --project "${JF_PROJECT}"
ok "Build info published"

ok "Build complete. Next: scripts/02-create-version.sh"
