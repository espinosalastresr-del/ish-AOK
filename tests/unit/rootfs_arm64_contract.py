#!/usr/bin/env python3
"""Static ARM64 rootfs contract checks for iSH-X."""
import json
from pathlib import Path

roots = Path("app/Roots.m").read_text(encoding="utf-8")
manifest_path = Path("deps/rootfs-manifest/manifest.json")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

assert "iSH-X never embeds a root filesystem in the IPA" in roots
assert 'isEqualToString:@"arm64"' in roots
assert "IsArm64ELFAtPath" in roots
assert "readDataOfLength:20" in roots
assert "b[4] == 2" in roots
assert "b[18] == 0xb7" in roots
assert "the imported root declares a non-ARM64 guest ABI" in roots

entries = [x for x in manifest if isinstance(x, dict)]
arm64 = [x for x in entries if x.get("guestABI") == "arm64"]
assert arm64, "rootfs manifest has no ARM64 entry"

for entry in arm64:
    assert isinstance(entry.get("downloadURL"), str)
    assert entry["downloadURL"].startswith("https://")
    assert entry.get("guestABI") == "arm64"

print(f"rootfs ARM64 contract: PASS ({len(arm64)} ARM64 catalog entries)")
