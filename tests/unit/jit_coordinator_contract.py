#!/usr/bin/env python3
"""Static contract checks for the iSH-X JIT backend coordinator."""
from pathlib import Path

source = Path("jit/ishx_jit_coordinator.c").read_text(encoding="utf-8")
header = Path("jit/ishx_jit_coordinator.h").read_text(encoding="utf-8")

assert "ISHX_JIT_BACKEND_GADGET" in source
assert "ISHX_JIT_BACKEND_STIKDEBUG" in source
assert "gadget_ready = true" in source
assert "stikdebug_available = false" in source
assert "authenticated host-side acquisition/handshake" in source
assert "ISHX_STIKDEBUG_READY" not in source
assert "stikdebug_available = true" not in source
assert "atomic_store_explicit(&backend, ISHX_JIT_BACKEND_STIKDEBUG" not in source

assert "enum ishx_jit_backend" in header
assert "ISHX_JIT_BACKEND_GADGET = 0" in header
assert "ISHX_JIT_BACKEND_STIKDEBUG = 1" in header
assert "struct ishx_jit_state" in header

print("JIT coordinator contract: PASS")
