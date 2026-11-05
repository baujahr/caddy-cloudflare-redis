#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
version=$(sed -n 's/^ARG CADDY_VERSION=v//p' Dockerfile)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin" "$temp/images"
export IMAGE_DIR="$temp/images" CALLS="$temp/calls"
export GITHUB_REPOSITORY=Baujahr/caddy-cloudflare-redis
export GITHUB_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export GITHUB_REF=refs/heads/main GITHUB_EVENT_NAME=push
export GITHUB_RUN_NUMBER=12 GITHUB_RUN_ATTEMPT=1
export REMOTE_HEAD="$GITHUB_SHA" FAIL_REMOTE=0 FAIL_PUSH=0 FAIL_MANIFEST=0
export PATH="$temp/bin:$PATH"

# External commands are fakes: these tests never contact GHCR or change tags.
cat > "$temp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "docker $*" >> "$CALLS"
if [[ "$1" == push && "$FAIL_PUSH" == 1 ]]; then exit 1; fi
if [[ "$*" == "buildx imagetools create"* && "$FAIL_MANIFEST" == 1 ]]; then exit 1; fi
MOCK
cat > "$temp/bin/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "git $*" >> "$CALLS"
[[ "$FAIL_REMOTE" == 0 ]] || exit 1
printf '%s\trefs/heads/main\n' "$REMOTE_HEAD"
MOCK
chmod +x "$temp/bin/docker" "$temp/bin/git"
printf 'amd64 fixture\n' > "$IMAGE_DIR/image-amd64.tar"
printf 'arm64 fixture\n' > "$IMAGE_DIR/image-arm64.tar"

run_ok() {
  : > "$CALLS"
  bash .github/scripts/publish.sh > "$temp/output" 2>&1 || {
    cat "$temp/output"
    exit 1
  }
}
run_fail() {
  : > "$CALLS"
  if bash .github/scripts/publish.sh > "$temp/output" 2>&1; then
    echo "Expected publication to fail"
    exit 1
  fi
}
assert_absent() {
  if grep -q "$1" "$CALLS"; then
    echo "Unexpected command matching $1"
    cat "$CALLS"
    exit 1
  fi
}
no_latest() { assert_absent ':latest'; }

run_ok
grep -Fq "$version-r12-a1-amd64" "$CALLS"
grep -Fq "$version-r12-a1-arm64" "$CALLS"
grep -q ':latest' "$CALLS"
[[ $(grep -c '^docker push ' "$CALLS") == 2 ]]
# Freshness check must be after the build manifest and before promotion.
[[ $(tail -n 2 "$CALLS" | head -n 1) == "git ls-remote "* ]]
echo "PASS current main publishes both architectures and promotes latest"

GITHUB_RUN_ATTEMPT=2 run_ok
grep -Fq "$version-r12-a2-amd64" "$CALLS"
assert_absent 'r12-a1'
echo "PASS rerun uses distinct attempt tags"

REMOTE_HEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb run_ok
no_latest
grep -q 'imagetools create -t .*r12-a1 ' "$CALLS"
echo "PASS historical revision publishes unique tag without moving latest"

GITHUB_EVENT_NAME=workflow_dispatch run_ok
grep -q ':latest' "$CALLS"
echo "PASS main manual dispatch can publish"

for event in pull_request pull_request_target release; do
  GITHUB_EVENT_NAME="$event" run_fail
  [[ ! -s "$CALLS" ]]
done
GITHUB_REF=refs/heads/feature GITHUB_EVENT_NAME=workflow_dispatch run_fail
[[ ! -s "$CALLS" ]]
GITHUB_REF=refs/tags/v1 run_fail
[[ ! -s "$CALLS" ]]
echo "PASS PRs, tags and feature-branch dispatches cannot publish"

mv "$IMAGE_DIR/image-arm64.tar" "$temp/arm64.tar"
run_fail
[[ ! -s "$CALLS" ]]
grep -q 'Re-run all jobs' "$temp/output"
mv "$temp/arm64.tar" "$IMAGE_DIR/image-arm64.tar"
echo "PASS partial attempt fails before any push"

FAIL_REMOTE=1 run_fail
no_latest
echo "PASS remote lookup failure cannot promote latest"

FAIL_PUSH=1 run_fail
no_latest
assert_absent 'imagetools create'
echo "PASS architecture push failure prevents manifest publication"

FAIL_MANIFEST=1 run_fail
no_latest
assert_absent '^git '
echo "PASS build manifest failure prevents promotion"
