#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$PROJECT_ROOT/macos/Packaging/CotorDesktopLauncher.sh.template"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "launcher template not found: $TEMPLATE"
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

HOME="$WORK_DIR/home"
mkdir -p "$HOME"

COTOR_DESKTOP_LAUNCHER_SOURCE_ONLY=1 source "$TEMPLATE"

BACKEND_RUNTIME_JAR="$WORK_DIR/runtime/cotor-backend-runtime-old.jar"
mkdir -p "$(dirname "$BACKEND_RUNTIME_JAR")" "$RUNTIME_DIR"
touch "$BACKEND_RUNTIME_JAR"

SERVER_PORT="55123"
SERVER_TOKEN="token-123"
PID_FILE="$WORK_DIR/app-server.pid"
PORT_FILE="$WORK_DIR/app-server.port"
TOKEN_FILE="$WORK_DIR/app-server.token"
MANAGED_BACKEND_PID="111"
MANAGED_BACKEND_STARTED=1
echo "222" > "$PID_FILE"

restart_calls=0
start_managed_backend() {
  local show_failure_alert="${1:-1}"
  if [[ "$show_failure_alert" != "0" ]]; then
    echo "restart should suppress user-facing alerts"
    exit 1
  fi
  if [[ "$SERVER_PORT" != "55123" || "$SERVER_TOKEN" != "token-123" ]]; then
    echo "restart did not preserve backend port/token"
    exit 1
  fi
  restart_calls=$((restart_calls + 1))
}

restart_managed_backend

if [[ "$restart_calls" != "1" ]]; then
  echo "restart_managed_backend did not call start_managed_backend once"
  exit 1
fi
if [[ -e "$PID_FILE" || -e "$BACKEND_RUNTIME_JAR" ]]; then
  echo "restart_managed_backend did not clear stale pid/runtime jar"
  exit 1
fi

INSTANCE_METADATA_FILE="$WORK_DIR/app-server.instance.json"
SERVER_PORT="55123"
SERVER_URL="http://127.0.0.1:55123"
SERVER_TOKEN="token-123"
PID_FILE="$WORK_DIR/app-server.pid"
PORT_FILE="$WORK_DIR/app-server.port"
TOKEN_FILE="$WORK_DIR/app-server.token"
MANAGED_BACKEND_PID="555"
MANAGED_BACKEND_STARTED=1
restart_calls=0
cat >"$INSTANCE_METADATA_FILE" <<'JSON'
{"pid":444,"host":"127.0.0.1","port":55123,"appHome":"/tmp/cotor-test","startedAt":1}
JSON
echo "555" > "$PID_FILE"
is_pid_alive() {
  [[ "$1" == "444" ]]
}
is_backend_healthy() {
  [[ "$1" == "http://127.0.0.1:55123" ]]
}
start_managed_backend() {
  restart_calls=$((restart_calls + 1))
}

restart_managed_backend

if [[ "$restart_calls" != "0" ||
  "$MANAGED_BACKEND_PID" != "444" ||
  "$(cat "$PID_FILE")" != "444" ||
  "$(cat "$PORT_FILE")" != "55123" ]]; then
  echo "restart_managed_backend did not reattach to healthy existing backend"
  exit 1
fi

BACKEND_RUNTIME_DIR="$WORK_DIR/runtime/backend"
mkdir -p "$BACKEND_RUNTIME_DIR"
BACKEND_RUNTIME_JAR="$BACKEND_RUNTIME_DIR/cotor-backend-runtime-current.jar"
STALE_RUNTIME_JAR="$BACKEND_RUNTIME_DIR/cotor-backend-runtime-stale.jar"
STALE_APP_SERVER_JAR="$BACKEND_RUNTIME_DIR/cotor-app-server-stale.jar"
touch "$BACKEND_RUNTIME_JAR" "$STALE_RUNTIME_JAR" "$STALE_APP_SERVER_JAR"

cleanup_stale_backend_runtime_jars

if [[ ! -e "$BACKEND_RUNTIME_JAR" ]]; then
  echo "cleanup_stale_backend_runtime_jars removed current runtime jar"
  exit 1
fi
if [[ -e "$STALE_RUNTIME_JAR" || -e "$STALE_APP_SERVER_JAR" ]]; then
  echo "cleanup_stale_backend_runtime_jars did not remove stale runtime jars"
  exit 1
fi

SCRIPT_DIR="/Applications/Cotor Desktop.app/Contents/MacOS"
BINARY_PATH="$SCRIPT_DIR/CotorDesktopBinary"
terminated_instances=""
ps() {
  if [[ "$*" == "-axo pid=,args=" ]]; then
    printf '%s\n' \
      "123 $BINARY_PATH" \
      "124 /bin/bash $SCRIPT_DIR/CotorDesktopLauncher" \
      "126 /bin/bash /private/tmp/old/Cotor Desktop.app/Contents/MacOS/CotorDesktopLauncher" \
      "127 /private/tmp/old/Cotor Desktop.app/Contents/MacOS/CotorDesktopBinary" \
      "125 /usr/bin/other-process"
    return 0
  fi
  command ps "$@"
}
kill() {
  terminated_instances="$terminated_instances ${*: -1}"
  return 0
}
is_pid_alive() {
  return 1
}
sleep() {
  return 0
}

terminate_existing_desktop_instances

if [[ "$terminated_instances" != *"123"* ||
  "$terminated_instances" != *"124"* ||
  "$terminated_instances" == *"126"* ||
  "$terminated_instances" == *"127"* ||
  "$terminated_instances" == *"125"* ]]; then
  echo "terminate_existing_desktop_instances did not target only same-bundle desktop instances"
  exit 1
fi

MANAGED_BACKEND_PID="111"
MANAGED_BACKEND_STARTED=1
echo "222" > "$PID_FILE"
killed_pid=""
cleared=0
after_kill=0

is_pid_alive() {
  [[ "$1" == "222" && "$after_kill" == "0" ]]
}

request_backend_shutdown() {
  return 1
}

kill() {
  killed_pid="${*: -1}"
  after_kill=1
  return 0
}

sleep() {
  return 0
}

clear_backend_runtime_files() {
  cleared=1
}

stop_managed_backend

if [[ "$killed_pid" != "222" || "$cleared" != "1" ]]; then
  echo "stop_managed_backend did not fall back to pid file for monitor-restarted backend"
  exit 1
fi

MANAGED_BACKEND_STARTED=1
MANAGED_BACKEND_PID="333"
SERVER_PORT="55123"
SERVER_URL="http://127.0.0.1:55123"
restart_calls=0
monitor_app_checks=0
is_pid_alive() {
  if [[ "$1" == "999" ]]; then
    monitor_app_checks=$((monitor_app_checks + 1))
    [[ "$monitor_app_checks" == "1" ]]
    return
  fi
  [[ "$1" == "333" ]]
}
is_port_listening() {
  return 0
}
is_backend_healthy() {
  return 1
}
restart_managed_backend() {
  restart_calls=$((restart_calls + 1))
  MANAGED_BACKEND_STARTED=0
}
sleep() {
  return 0
}

monitor_managed_backend "999"

if [[ "$restart_calls" != "1" ]]; then
  echo "monitor_managed_backend did not restart a listening but unhealthy backend"
  exit 1
fi

echo "desktop launcher runtime tests passed"
