#!/usr/bin/env python3
"""Static contract checks for the iSH-X iosctl public bridge."""
import re
from pathlib import Path

bridge = Path("app/ISHXNativeBridge.m").read_text(encoding="utf-8")
glue = Path("kernel/iosctl_glue.c").read_text(encoding="utf-8")
plist = Path("app/Info.plist").read_text(encoding="utf-8")

commands = {
    "status": r'isEqualToString:@"status"',
    "location": r'isEqualToString:@"location"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"get"\)\s*==\s*0',
    "motion": r'isEqualToString:@"motion"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"accelerometer"\)\s*==\s*0',
    "clipboard": r'isEqualToString:@"clipboard"',
    "battery": r'isEqualToString:@"battery"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"get"\)\s*==\s*0',
    "notifications": r'isEqualToString:@"notifications"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"status"\)\s*==\s*0',
    "contacts": r'isEqualToString:@"contacts"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"list"\)\s*==\s*0',
    "calendar": r'isEqualToString:@"calendar"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"list"\)\s*==\s*0',
    "reminders": r'isEqualToString:@"reminders"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"list"\)\s*==\s*0',
    "bluetooth": r'isEqualToString:@"bluetooth"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"scan"\)\s*==\s*0',
    "camera": r'isEqualToString:@"camera"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"photo"\)\s*==\s*0',
    "microphone": r'isEqualToString:@"microphone"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"record"\)\s*==\s*0',
    "photos": r'isEqualToString:@"photos"\]\s*&&\s*argc\s*>\s*2\s*&&\s*strcmp\(argv\[2\],\s*"save"\)\s*==\s*0',
}

for name, pattern in commands.items():
    assert re.search(pattern, bridge), f"missing iosctl bridge contract: {name}"

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
    "native_iosctl_main",
    "ishx_native_bridge_run",
    "native_write(1, out, strlen(out))",
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
assert "guest path must be absolute" in bridge
assert "seconds must be a number from 1 to 300" in bridge
assert "strtod(argv[4]" in bridge
assert 'isEqualToString:@"clipboard"]&&' in bridge
assert "argc!=4" in bridge
assert "argc!=5" in bridge
print("iosctl contract: PASS")
