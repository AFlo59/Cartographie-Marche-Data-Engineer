#!/bin/sh
set -eu

run_with_oauth_token() {
  if ! command -v gcloud >/dev/null 2>&1; then
    echo "gcloud is required to refresh OAuth token" >&2
    exit 1
  fi

  export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
  exec "$@"
}

if [ "${1:-}" = "terraform" ] || [ "${1:-}" = "tofu" ]; then
  exec "$@"
fi

if [ "${1:-}" = "terraform-oauth" ]; then
  shift
  run_with_oauth_token terraform "$@"
fi

if [ "${1:-}" = "tofu-oauth" ]; then
  shift
  run_with_oauth_token tofu "$@"
fi

if [ "${1:-}" = "fmt" ]; then
  shift
  exec terraform fmt -recursive "$@"
fi

if [ "${1:-}" = "validate" ]; then
  shift
  # Run init without args (init doesn't accept validate-specific flags like -json, -no-color)
  terraform init -backend=false
  # Pass args only to validate
  exec terraform validate "$@"
fi

exec "$@"
