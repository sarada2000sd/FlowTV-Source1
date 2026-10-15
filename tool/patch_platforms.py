#!/usr/bin/env python3
"""Patch the Flutter-generated Android runner with the FlowTV PiP bridge."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def patch_android() -> None:
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not manifest.exists():
        raise SystemExit(f"Android manifest not found: {manifest}")
    text = manifest.read_text(encoding="utf-8")
    if 'android.permission.INTERNET' not in text:
        text, count = re.subn(
            r'(<manifest\b[^>]*>)',
            r'\1\n    <uses-permission android:name="android.permission.INTERNET" />',
            text,
            count=1,
        )
        if count == 0:
            raise SystemExit("Could not add Android INTERNET permission.")
    if 'android:usesCleartextTraffic="true"' not in text:
        text, count = re.subn(
            r'(<application\b[^>]*)(>)',
            r'\1 android:usesCleartextTraffic="true"\2',
            text,
            count=1,
        )
        if count == 0:
            raise SystemExit("Could not enable HTTP stream compatibility in the application tag.")
    if 'android:supportsPictureInPicture="true"' not in text:
        pattern = re.compile(r'(<activity\b(?:(?!/>).)*?android:name="\.MainActivity"(?:(?!/>).)*?)(/?>)', re.S)
        match = pattern.search(text)
        if not match:
            # Flutter template formatting differs by version; find the main activity block.
            pattern = re.compile(r'(<activity\b[^>]*android:name="[^"]*MainActivity"[^>]*)(>)', re.S)
            match = pattern.search(text)
        if match:
            attrs = match.group(1)
            attrs += '\n            android:supportsPictureInPicture="true"\n            android:resizeableActivity="true"'
            text = text[:match.start(1)] + attrs + text[match.end(1):]
        else:
            raise SystemExit("Could not find MainActivity tag to enable Picture-in-Picture.")
    text = re.sub(r'android:label="[^"]*"', 'android:label="FlowTV"', text, count=1)
    manifest.write_text(text, encoding="utf-8")

    activities = list((ROOT / "android/app/src/main/kotlin").rglob("MainActivity.kt"))
    if not activities:
        raise SystemExit("Generated Kotlin MainActivity.kt was not found.")
    main = activities[0]
    package_line = "package com.flowtv.flowtv"
    source = f'''{package_line}

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {{
    private val channelName = "flowtv/pip"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {{
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler {{ call, result ->
            when (call.method) {{
                "enterPip" -> {{
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        !packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {{
                        result.success(false)
                    }} else {{
                        try {{
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .build()
                            result.success(enterPictureInPictureMode(params))
                        }} catch (_: Exception) {{
                            result.success(false)
                        }}
                    }}
                }}
                else -> result.notImplemented()
            }}
        }}
    }}
}}
'''
    main.write_text(source, encoding="utf-8")

def patch_windows() -> None:
    cmake = ROOT / "windows/CMakeLists.txt"
    if cmake.exists():
        ctext = cmake.read_text(encoding="utf-8")
        ctext = ctext.replace('set(BINARY_NAME \"flowtv\")', 'set(BINARY_NAME \"FlowTV\")')
        cmake.write_text(ctext, encoding="utf-8")
    main = ROOT / "windows/runner/main.cpp"
    if main.exists():
        text = main.read_text(encoding="utf-8")
        text = text.replace('L"flowtv"', 'L"FlowTV"').replace('L"flowtv.exe"', 'L"FlowTV.exe"')
        main.write_text(text, encoding="utf-8")

if __name__ == "__main__":
    targets = set(sys.argv[1:] or ["android", "windows"])
    if "android" in targets:
        patch_android()
    if "windows" in targets:
        patch_windows()
    print("FlowTV platform customizations applied:", ", ".join(sorted(targets)))
