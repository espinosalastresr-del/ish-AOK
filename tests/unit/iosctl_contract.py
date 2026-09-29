#!/usr/bin/env python3
"""Static contract checks for the iSH-X iosctl public bridge.

These checks intentionally do not claim device/runtime validation. They make
the source-level contract fail closed if a command, permission framework, or
guest-file transfer seam is accidentally removed.
"""
from pathlib import Path

bridge = Path("app/ISHXNativeBridge.m").read_text(encoding="utf-8")
glue = Path("kernel/iosctl_glue.c").read_text(encoding="utf-8")
plist = Path("app/Info.plist").read_text(encoding="utf-8")

commands = [
    ('status', 'isEqualToString:@"status"'),
    ('location', 'location"&&argc>2&&strcmp(argv[2],"get")'),
    ('motion', 'motion"&&argc>2&&strcmp(argv[2],"accelerometer")'),
    ('clipboard', 'isEqualToString:@"clipboard"'),
    ('battery', 'battery"&&argc>2&&strcmp(argv[2],"get")'),
    ('notifications', 'notifications"&&argc>2&&strcmp(argv[2],"status")'),
    ('contacts', 'contacts"&&argc>2&&strcmp(argv[2],"list")'),
    ('calendar', 'calendar"&&argc>2&&strcmp(argv[2],"list")'),
    ('reminders', 'reminders"&&argc>2&&strcmp(argv[2],"list")'),
    ('bluetooth', 'bluetooth"&&argc>2&&strcmp(argv[2],"scan")'),
    ('camera', 'camera"&&argc>2&&strcmp(argv[2],"photo")'),
    ('microphone', 'microphone"&&argc>2&&strcmp(argv[2],"record")'),
    ('photos', 'photos"&&argc>2&&strcmp(argv[2],"save")'),
]

for name, marker in commands:
    assert marker in bridge, f"missing iosctl bridge contract: {name}"

for header in (
    "<AVFoundation/AVFoundation.h>",
    "<Contacts/Contacts.h>",
    "<CoreBluetooth/CoreBluetooth.h>",
    "<CoreLocation/CoreLocation.h>",
    "<CoreMotion/CoreMotion.h>",
    "<EventKit/EventKit.h>",
    "<Photos/Photos.h>",
    "<UIKit/UIKit.h>",
    "<UserNotifications/UserNotifications.h>",
):
    assert header in bridge, f"missing public framework import: {header}"

for marker in (
    "ISHGuestFileBridge",
    "writeData:del.data",
    "writeData:data",
    "extractToTempFileAtGuestPath",
):
    assert marker in bridge, f"missing guest file bridge seam: {marker}"

for marker in (
    'native_iosctl_main',
    'ishx_native_bridge_run',
    'native_write(1, out, strlen(out))',
):
    assert marker in glue, f"missing iosctl guest/native seam: {marker}"

for key in (
    "NSCameraUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSBluetoothAlwaysUsageDescription",
    "NSContactsUsageDescription",
    "NSCalendarsFullAccessUsageDescription",
    "NSRemindersFullAccessUsageDescription",
    "NSPhotoLibraryAddUsageDescription",
):
    assert f"<key>{key}</key>" in plist, f"missing Info.plist permission key: {key}"

assert "response too large" in bridge
assert "Never truncate a JSON response" in bridge
print("iosctl contract: PASS")
