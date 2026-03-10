#!/bin/sh
set -eu

if [ "${1:-}" = "terraform" ] || [ "${1:-}" = "tofu" ]; then
  exec "$@"
fi

if [ "${1:-}" = "fmt" ]; then
  shift
  exec terraform fmt -recursive "$@"
fi

if [ "${1:-}" = "validate" ]; then
  shift
  terraform init -backend=false "$@"
  exec terraform validate
fi

exec "$@"
