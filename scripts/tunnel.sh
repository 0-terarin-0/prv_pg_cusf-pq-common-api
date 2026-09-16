#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

export HOST="${HOST:-127.0.0.1}"
export PORT="${PORT:-8000}"
export CACHE_DIR="${CACHE_DIR:-$root/cache/gfs}"
export RUST_LOG="${RUST_LOG:-info}"

origin="http://${HOST}:${PORT}"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared is not installed. On macOS: brew install cloudflared" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${api_pid:-}" ]] && kill -0 "$api_pid" 2>/dev/null; then
    kill "$api_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Building release binary"
cargo build --release

bin="$root/target/release/prv_pg_cusf-pq-common-api"
echo "Starting predictor API on ${origin}"
"$bin" &
api_pid=$!

for _ in $(seq 1 120); do
  if curl -sS -o /dev/null --connect-timeout 1 "${origin}/tawhiri?launch_latitude=0"; then
    break
  fi
  if ! kill -0 "$api_pid" 2>/dev/null; then
    echo "API process exited before it started listening" >&2
    exit 1
  fi
  sleep 0.5
done

if [[ -n "${TUNNEL_TOKEN:-}" ]]; then
  echo "Starting named Cloudflare Tunnel from TUNNEL_TOKEN"
  cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN"
  exit $?
fi

if [[ "${1:-}" == "--named" ]]; then
  echo "Starting named Cloudflare Tunnel from cloudflared.yml"
  cloudflared tunnel --no-autoupdate --config "$root/cloudflared.yml" run
  exit $?
fi

echo "Starting Quick Tunnel to ${origin} (trycloudflare.com URL will print below)"
cloudflared tunnel --no-autoupdate --url "$origin"
