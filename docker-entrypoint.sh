#!/bin/sh
set -eu

is_loopback_host() {
  case "$1" in
    ""|"127.0.0.1"|"localhost"|"::1"|"[::1]")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n'
  fi
}

command_name="${1:-}"
host="${COTOR_APP_HOST:-127.0.0.1}"
previous=""
for arg in "$@"; do
  if [ "$previous" = "--host" ]; then
    host="$arg"
  fi
  case "$arg" in
    --host=*)
      host="${arg#--host=}"
      ;;
  esac
  previous="$arg"
done

if [ "$command_name" = "app-server" ] && ! is_loopback_host "$host" && [ -z "${COTOR_APP_TOKEN:-}" ]; then
  export COTOR_APP_TOKEN="$(random_token)"
  echo "Generated COTOR_APP_TOKEN for non-loopback app-server binding." >&2
fi

exec java -jar /app/cotor.jar "$@"
