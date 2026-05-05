#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.codexflow/local-run"

AGENT_PID_FILE="$RUNTIME_DIR/agent.pid"
WEB_PID_FILE="$RUNTIME_DIR/web.pid"
AGENT_LOG="$RUNTIME_DIR/agent.log"
WEB_LOG="$RUNTIME_DIR/web.log"
AGENT_BIN="$RUNTIME_DIR/codexflow-agent"

DEFAULT_AGENT_PORT="${CODEXFLOW_AGENT_PORT:-4318}"
AGENT_LISTEN_ADDR="${CODEXFLOW_LISTEN_ADDR:-0.0.0.0:$DEFAULT_AGENT_PORT}"
AGENT_HOST="${AGENT_LISTEN_ADDR%:*}"
AGENT_PORT="${AGENT_LISTEN_ADDR##*:}"
WEB_HOST="${CODEXFLOW_WEB_HOST:-0.0.0.0}"
WEB_PORT="${CODEXFLOW_WEB_PORT:-8080}"
WEB_DIR="$ROOT_DIR/flutter/codexflow/build/web"

usage() {
  cat <<EOF
Usage: $0 [start|stop|restart|status|logs]

Commands:
  start     后台启动 Go Agent 和 Flutter Web 前端
  stop      停止脚本启动的后台进程
  restart   先停止再启动
  status    查看后台进程状态
  logs      追踪 Agent 和 Web 日志

Environment:
  CODEXFLOW_LISTEN_ADDR   Agent 监听地址，默认 0.0.0.0:4318
  CODEXFLOW_WEB_HOST      Web 监听 host，默认 0.0.0.0
  CODEXFLOW_WEB_PORT      Web 监听端口，默认 8080
  CODEXFLOW_PUBLIC_HOST   手动指定回显给手机访问的主机 IP
EOF
}

ensure_runtime_dir() {
  mkdir -p "$RUNTIME_DIR"
}

is_pid_running() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

port_in_use() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

detect_public_host() {
  if [[ -n "${CODEXFLOW_PUBLIC_HOST:-}" ]]; then
    printf '%s\n' "$CODEXFLOW_PUBLIC_HOST"
    return
  fi

  if command -v ipconfig >/dev/null 2>&1; then
    local iface ip
    for iface in en0 en1; do
      ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
      if [[ -n "$ip" ]]; then
        printf '%s\n' "$ip"
        return
      fi
    done
  fi

  if command -v hostname >/dev/null 2>&1; then
    local ip
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    if [[ -n "$ip" ]]; then
      printf '%s\n' "$ip"
      return
    fi
  fi

  printf '127.0.0.1\n'
}

wait_for_url() {
  local name="$1"
  local url="$2"
  local log_file="$3"

  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  local i
  for i in {1..20}; do
    if curl -fsS --max-time 1 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  echo "WARN: $name 暂时没有响应：$url"
  echo "      查看日志：$log_file"
}

start_agent() {
  ensure_runtime_dir

  if is_pid_running "$AGENT_PID_FILE"; then
    echo "Agent 已在后台运行，PID $(cat "$AGENT_PID_FILE")"
    return
  fi

  if port_in_use "$AGENT_PORT"; then
    echo "ERROR: Agent 端口 $AGENT_PORT 已被占用。"
    echo "       如需停止旧进程，请先确认它不是其他服务。"
    exit 1
  fi

  if ! command -v go >/dev/null 2>&1; then
    echo "ERROR: 未找到 go 命令，无法启动 Agent。"
    exit 1
  fi

  echo "构建 Go Agent..."
  (cd "$ROOT_DIR" && go build -o "$AGENT_BIN" ./cmd/codexflow-agent)

  echo "启动 Go Agent: $AGENT_LISTEN_ADDR"
  (
    cd "$ROOT_DIR"
    export CODEXFLOW_LISTEN_ADDR="$AGENT_LISTEN_ADDR"
    nohup "$AGENT_BIN" >"$AGENT_LOG" 2>&1 </dev/null &
    echo "$!" >"$AGENT_PID_FILE"
  )

  sleep 0.5
  if ! is_pid_running "$AGENT_PID_FILE"; then
    echo "ERROR: Agent 启动失败，最近日志如下："
    tail -n 40 "$AGENT_LOG" || true
    rm -f "$AGENT_PID_FILE"
    exit 1
  fi

  wait_for_url "Agent" "http://127.0.0.1:$AGENT_PORT/healthz" "$AGENT_LOG"
}

build_web_if_needed() {
  if [[ -f "$WEB_DIR/index.html" ]]; then
    return 0
  fi

  if ! command -v flutter >/dev/null 2>&1; then
    echo "WARN: 未找到 Flutter，且 $WEB_DIR/index.html 不存在，跳过 Web 前端启动。"
    echo "      安装 Flutter 后重新运行本脚本，或先在 flutter/codexflow 下执行 flutter build web --release。"
    return 1
  fi

  echo "构建 Flutter Web..."
  (cd "$ROOT_DIR/flutter/codexflow" && flutter build web --release)
}

start_web() {
  ensure_runtime_dir

  if is_pid_running "$WEB_PID_FILE"; then
    echo "Web 前端已在后台运行，PID $(cat "$WEB_PID_FILE")"
    return
  fi

  if ! build_web_if_needed; then
    return
  fi

  if port_in_use "$WEB_PORT"; then
    echo "ERROR: Web 端口 $WEB_PORT 已被占用。"
    echo "       可以改用 CODEXFLOW_WEB_PORT=8081 $0 start"
    exit 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: 未找到 python3，无法启动 Web 静态服务。"
    exit 1
  fi

  echo "启动 Flutter Web: $WEB_HOST:$WEB_PORT"
  nohup python3 -m http.server --bind "$WEB_HOST" --directory "$WEB_DIR" "$WEB_PORT" >"$WEB_LOG" 2>&1 </dev/null &
  echo "$!" >"$WEB_PID_FILE"

  sleep 0.5
  if ! is_pid_running "$WEB_PID_FILE"; then
    echo "ERROR: Web 前端启动失败，最近日志如下："
    tail -n 40 "$WEB_LOG" || true
    rm -f "$WEB_PID_FILE"
    exit 1
  fi

  wait_for_url "Web" "http://127.0.0.1:$WEB_PORT/" "$WEB_LOG"
}

print_addresses() {
  local public_host
  public_host="$(detect_public_host)"

  cat <<EOF

已启动 CodexFlow 本地服务：
EOF

  if [[ "$AGENT_HOST" == "127.0.0.1" || "$AGENT_HOST" == "localhost" ]]; then
    cat <<EOF
  Agent 健康检查: http://127.0.0.1:$AGENT_PORT/healthz
  App 设置里填写: 当前 Agent 只监听本机，请改用 CODEXFLOW_LISTEN_ADDR=0.0.0.0:$AGENT_PORT $0 start
EOF
  else
    cat <<EOF
  Agent 健康检查: http://$public_host:$AGENT_PORT/healthz
  App 设置里填写: http://$public_host:$AGENT_PORT
EOF
  fi

  if is_pid_running "$WEB_PID_FILE"; then
    cat <<EOF
  Web 前端地址:   http://$public_host:$WEB_PORT
EOF
  else
    cat <<EOF
  Web 前端地址:   未启动，见上方提示或日志
EOF
  fi

  cat <<EOF

停止后台服务：
  ./scripts/codexflow-local.sh stop

日志位置：
  Agent: $AGENT_LOG
  Web:   $WEB_LOG
EOF
}

stop_one() {
  local name="$1"
  local pid_file="$2"

  if ! [[ -f "$pid_file" ]]; then
    echo "${name} 未发现 PID 文件。"
    return
  fi

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -z "$pid" ]]; then
    rm -f "$pid_file"
    echo "${name} PID 文件为空，已清理。"
    return
  fi

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    rm -f "$pid_file"
    echo "${name} 已不在运行，已清理 PID 文件。"
    return
  fi

  echo "停止 ${name}，PID ${pid}..."
  kill "$pid" >/dev/null 2>&1 || true

  local i
  for i in {1..20}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      rm -f "$pid_file"
      echo "${name} 已停止。"
      return
    fi
    sleep 0.2
  done

  echo "${name} 未在超时时间内退出，执行强制停止。"
  kill -9 "$pid" >/dev/null 2>&1 || true
  rm -f "$pid_file"
}

start_all() {
  start_agent
  start_web
  print_addresses
}

stop_all() {
  stop_one "Web 前端" "$WEB_PID_FILE"
  stop_one "Go Agent" "$AGENT_PID_FILE"
}

status_all() {
  if is_pid_running "$AGENT_PID_FILE"; then
    echo "Agent: 运行中，PID $(cat "$AGENT_PID_FILE")"
  else
    echo "Agent: 未运行"
  fi

  if is_pid_running "$WEB_PID_FILE"; then
    echo "Web:   运行中，PID $(cat "$WEB_PID_FILE")"
  else
    echo "Web:   未运行"
  fi
}

logs_all() {
  ensure_runtime_dir
  touch "$AGENT_LOG" "$WEB_LOG"
  tail -f "$AGENT_LOG" "$WEB_LOG"
}

case "${1:-start}" in
  start)
    start_all
    ;;
  stop)
    stop_all
    ;;
  restart)
    stop_all
    start_all
    ;;
  status)
    status_all
    ;;
  logs)
    logs_all
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
