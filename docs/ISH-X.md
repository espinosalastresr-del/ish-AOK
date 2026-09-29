# iSH-X

iSH-X is the ARM64-only product profile built from the iSH-AOK working baseline.

## Baseline

- Upstream: emkey1/ish-AOK
- User fork: espinosalastresr-del/ish-AOK
- Development branch: ish-x
- Baseline branch: working
- Execution engine: gadget JIT
- Guest ABI: aarch64/ARM64 only
- Linux distribution: external/importable ARM64 rootfs
- Native host bridge: iosctl -> Objective-C public Apple frameworks
- Large binary data: GuestFileBridge, not large IPC messages

## JIT policy

The gadget JIT is mandatory and is the fallback that makes iSH-X independent of StikDebug.

StikDebug/StikJIT is optional. A URL launch, application presence, or UI response is not considered JIT readiness. A future host handshake may advertise readiness to the coordinator; until that happens the backend remains gadget.

## Rootfs policy

Root filesystems are not copied into the IPA. The Roots catalogue is filtered to guestABI=arm64 and uses the existing HTTPS download/cache/import path. Archives are stored under /AOK/persist/roots and imported into the guest fakefs.

The in-app manifest remains a small catalogue snapshot so the root picker can still operate when the device is offline after installation. The archive itself is external.

## iosctl

The native program is registered as /AOK/native/iosctl and is reachable as iosctl when the native path is present in the guest PATH.

Implemented public-framework operations:

- iosctl status
- iosctl location get
- iosctl motion accelerometer
- iosctl clipboard get
- iosctl clipboard set ...
- iosctl camera photo <guest-path>
- iosctl microphone record <guest-path> <seconds>
- iosctl photos save <guest-path>
- iosctl bluetooth scan
- iosctl contacts list
- iosctl calendar list
- iosctl reminders list
- iosctl notifications status
- iosctl battery get

Camera, microphone and Photos transfers use ISHGuestFileBridge, so the guest never needs direct access to an iOS filesystem path.

## Security boundary

iosctl does not expose XNU syscalls, kernel interfaces, private Apple APIs, /dev/video0, /dev/hci0, arbitrary host paths, or arbitrary native symbol invocation. Every capability is an explicit command mapped to a public framework and its iOS permission model.

## CI

.github/workflows/ish-x.yml builds the ARM64 guest profile, runs native Linux tests, and builds the unsigned ARM64 iOS target.

The normal AOK working workflow remains available for upstream compatibility and regression comparison.
