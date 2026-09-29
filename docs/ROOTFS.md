# iSH-X rootfs policy

iSH-X does not ship an Alpine or Devuan archive inside the IPA.

The existing iSH-AOK root catalogue infrastructure is retained because it already provides:

1. HTTPS-only manifest validation.
2. Remote catalogue refresh.
3. Offline cached catalogue.
4. Resumable/downloaded archive storage in /AOK/persist/roots.
5. Import into the guest fake filesystem.
6. Root metadata recording of the guest ABI.

iSH-X adds one product constraint: only guestABI=arm64 entries are exposed.

The current rootfs catalogue contains an external ARM64 Alpine 3.24.x option and other ARM64 options. The archive is downloaded only after selection.

This separation keeps the IPA small and lets the rootfs evolve independently of the application binary.
