#!/usr/bin/env bash
set -euo pipefail

# Defense in depth: never publish a PR, tag, or feature-branch dispatch.
if [[ "${GITHUB_REF:-}" != refs/heads/main ]] ||
   [[ "${GITHUB_EVENT_NAME:-}" != push && "${GITHUB_EVENT_NAME:-}" != workflow_dispatch ]]; then
  echo "::error::Only main pushes and main workflow dispatches may publish."
  exit 1
fi

for name in GITHUB_REPOSITORY GITHUB_SHA GITHUB_RUN_NUMBER GITHUB_RUN_ATTEMPT IMAGE_DIR; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::Required environment variable $name is missing or empty."
    exit 1
  fi
done
if ! version=$(sed -n 's/^ARG CADDY_VERSION=v//p' Dockerfile); then
  echo "::error::Cannot read CADDY_VERSION from Dockerfile."
  exit 1
fi
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::Dockerfile must contain exactly one ARG CADDY_VERSION=vMAJOR.MINOR.PATCH."
  exit 1
fi
for name in GITHUB_RUN_NUMBER GITHUB_RUN_ATTEMPT; do
  if [[ ! "${!name}" =~ ^[1-9][0-9]*$ ]]; then
    echo "::error::$name must be a positive integer."
    exit 1
  fi
done
image="ghcr.io/${GITHUB_REPOSITORY,,}"
build="$image:$version-r$GITHUB_RUN_NUMBER-a$GITHUB_RUN_ATTEMPT"

# Downloads are scoped to this run AND attempt. Check both before any push.
# Re-run all jobs: a partial rerun must not mix in a previous attempt's image.
for arch in amd64 arm64; do
  if [[ ! -s "$IMAGE_DIR/image-$arch.tar" ]]; then
    echo "::error::Missing $arch image for this attempt. Use Re-run all jobs."
    exit 1
  fi
done

for arch in amd64 arm64; do
  docker load -i "$IMAGE_DIR/image-$arch.tar"
  docker tag caddy-cloudflare-redis:ci "$build-$arch"
  docker push "$build-$arch"
done
docker buildx imagetools create -t "$build" "$build-amd64" "$build-arm64"

# Fetch fresh state, not the checkout's possibly stale origin/main.
# An API/network failure fails closed under set -e.
head=$(git ls-remote --exit-code "https://github.com/$GITHUB_REPOSITORY.git" refs/heads/main)
head=${head%%$'\t'*}
if [[ "$head" != "$GITHUB_SHA" ]]; then
  echo "::notice::Published $build; skipping latest because this revision is not current main."
  exit 0
fi
docker buildx imagetools create -t "$image:latest" "$build"
echo "Published $build and promoted it to latest."
