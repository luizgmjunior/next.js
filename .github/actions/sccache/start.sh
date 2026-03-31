#!/usr/bin/env bash
set -euo pipefail

# --- Normalize TURBO_API and TURBO_TOKEN ---
# Runner .bashrc may set these (self-hosted cache server). If not,
# fall back to Vercel's public API and the secret passed as an input.

if [ -z "${TURBO_API:-}" ]; then
  export TURBO_API="https://api.vercel.com"
  echo "TURBO_API=${TURBO_API}" >> "$GITHUB_ENV"
  echo "TURBO_API not set, defaulting to ${TURBO_API}"
fi

if [ -z "${TURBO_TOKEN:-}" ]; then
  if [ -n "${INPUT_TURBO_TOKEN:-}" ]; then
    export TURBO_TOKEN="${INPUT_TURBO_TOKEN}"
    echo "TURBO_TOKEN=${TURBO_TOKEN}" >> "$GITHUB_ENV"
    echo "TURBO_TOKEN not set, using fallback from input"
  else
    echo "WARNING: no TURBO_TOKEN available (not in env or input)"
  fi
fi

echo "Cache endpoint: ${TURBO_API}"

# --- Kill stale processes from cancelled builds ---
# Self-hosted runners persist between jobs. A cancelled build may leave
# zombie sccache/cargo/rustc processes that interfere with the next run.
sccache --stop-server 2>/dev/null || true
pkill -9 -x cargo 2>/dev/null || true
pkill -9 -x rustc 2>/dev/null || true

# --- Install sccache (from cache or build from source) ---

SCCACHE_REPO="https://github.com/vercel/sccache"
SCCACHE_COMMIT=$(git ls-remote "$SCCACHE_REPO" HEAD | cut -f1)
TARGET=$(rustc -vV | grep '^host:' | cut -d' ' -f2)
CACHE_KEY="sccache-${SCCACHE_COMMIT}-${TARGET}"
SCCACHE_BIN="$HOME/.cargo/bin/sccache"
SCRIPTS="${GITHUB_WORKSPACE}/scripts"

echo "Checking turbo cache for sccache binary (key: ${CACHE_KEY:0:16}...)"
if node --input-type=module -e "
  import * as cache from '${SCRIPTS}/turbo-cache.mjs';
  const ok = await cache.getToFile('${CACHE_KEY}', '${SCCACHE_BIN}');
  if (!ok) { console.log('sccache cache miss'); process.exit(1); }
" 2>/dev/null; then
  chmod +x "$SCCACHE_BIN"
  echo "sccache restored from cache"
  sccache --version
else
  echo "Building sccache from source..."
  cargo install --force --git "$SCCACHE_REPO" sccache --locked

  # Cache the built binary for next time
  node --input-type=module -e "
    import * as cache from '${SCRIPTS}/turbo-cache.mjs';
    await cache.put('${CACHE_KEY}', '${SCCACHE_BIN}');
    console.log('sccache binary cached');
  " 2>&1 || echo "WARNING: failed to cache sccache binary"
fi

# --- Set env vars for the sccache server AND subsequent steps ---
# export: makes them available to sccache --start-server below
# GITHUB_ENV: makes them available to subsequent workflow steps

BASE_DIR="${INPUT_BASE_DIR:-${GITHUB_WORKSPACE}}"

set_env() {
  export "$1=$2"
  echo "$1=$2" >> "$GITHUB_ENV"
}

set_env RUSTC_WRAPPER sccache
set_env SCCACHE_BASE_DIR "${BASE_DIR}"
set_env CARGO_INCREMENTAL 0
set_env SCCACHE_IDLE_TIMEOUT 0

# Multi-level cache: fast local disk L0 + Vercel Artifacts remote L1
set_env SCCACHE_MULTILEVEL_CHAIN "disk,vercel_artifacts"
set_env SCCACHE_DIR "${RUNNER_TEMP}/sccache"

# Vercel Artifacts backend (native in vercel/sccache fork)
set_env SCCACHE_VERCEL_ARTIFACTS_ENDPOINT "${TURBO_API}"
set_env SCCACHE_VERCEL_ARTIFACTS_TOKEN "${TURBO_TOKEN}"
set_env SCCACHE_VERCEL_ARTIFACTS_TEAM_SLUG "${TURBO_TEAM}"

# Allow caching of all crate types (proc-macros, cdylibs, bins)
set_env SCCACHE_RUST_CRATE_TYPE_ALLOW_HASH v1

# --- Start sccache server ---

sccache --start-server 2>&1 || echo "sccache server may already be running"
sccache --show-stats 2>&1 | grep "Cache location"
