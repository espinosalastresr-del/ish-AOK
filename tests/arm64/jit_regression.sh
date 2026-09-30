#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-build-ishx-arm64-jit}"
ISH="${ISH_BIN:-$BUILD_DIR/ish}"
TEST_DIR="${TEST_DIR:-tests/arm64}"
BIN_DIR="${BIN_DIR:-$BUILD_DIR/arm64-tests}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-30}"

if [[ ! -x "$ISH" ]]; then
    echo "missing CLI: $ISH" >&2
    exit 2
fi

mkdir -p "$BIN_DIR"

declare -A EXPECTED=(
    [arm64_hello]=42
    [arm64_branch_only]=5
    [arm64_branch_only2]=0
    [arm64_prologue]=0
    [arm64_atomics]=0
    [arm64_logical]=0
    [arm64_dpreg]=0
    [arm64_dpextra]=0
    [arm64_fp]=0
    [arm64_vshift]=0
    [arm64_ldpsw]=0
    [arm64_ld1]=0
    [arm64_signal]=0
    [arm64_crypto]=0
)

compile_one() {
    local src="$1"
    local name
    name="$(basename "$src" .s)"
    clang -target aarch64-linux-gnu -fuse-ld=lld         -nostdlib -static -Wl,-e,_start         -o "$BIN_DIR/$name" "$src"
}

echo "== Build ARM64 guest test binaries =="
for src in "$TEST_DIR"/*.s; do
    name="$(basename "$src" .s)"
    [[ -v "EXPECTED[$name]" ]] || continue
    echo "compile $name"
    compile_one "$src"
done

run_one() {
    local mode="$1"
    local name="$2"
    local expected="$3"
    local bin="$BIN_DIR/$name"
    local output rc

    set +e
    if [[ "$mode" == "jit" ]]; then
        output="$(env -u ISH_ARM64_FORCE_INTERP timeout "$TIMEOUT_SECONDS" "$ISH" -r / "$bin" 2>&1)"
    else
        output="$(ISH_ARM64_FORCE_INTERP=1 timeout "$TIMEOUT_SECONDS" "$ISH" -r / "$bin" 2>&1)"
    fi
    rc=$?
    set -e

    printf '%s\n' "$output"

    if [[ "$rc" -ne "$expected" ]]; then
        echo "FAIL $mode/$name: expected exit $expected, got $rc" >&2
        return 1
    fi
    echo "PASS $mode/$name: exit $rc"
}

echo "== Interpreter baseline =="
for name in "${!EXPECTED[@]}"; do
    run_one interp "$name" "${EXPECTED[$name]}"
done

echo "== ARM64 gadget JIT =="
for name in "${!EXPECTED[@]}"; do
    run_one jit "$name" "${EXPECTED[$name]}"
done

echo "== Differential result =="
echo "All ARM64 tests matched their documented exit codes under both the interpreter and the native AArch64 gadget JIT."
