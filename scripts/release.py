#!/usr/bin/env python3
"""Build a local preview or an explicitly configured Developer ID release.

No credentials are stored here. No upload occurs without --notarize and an
existing notarytool keychain profile. Output never overwrites a prior package.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
MAC = ROOT / "apps/macos"


def capture(args):
    return subprocess.run(args, cwd=MAC, text=True, capture_output=True, check=True).stdout.strip()


def run(args, log):
    with log.open("a") as stream:
        subprocess.run(args, cwd=MAC, stdout=stream, stderr=subprocess.STDOUT, check=True,
                       env={**os.environ, "GIT_CONFIG_COUNT": "0"})


def preflight(args):
    missing = [name + " is unavailable" for name in ["xcodegen", "xcodebuild", "xcrun", "codesign", "ditto"] if shutil.which(name) is None]
    if os.uname().machine != "arm64":
        missing.append("An Apple silicon build host is required")
    if not args.preview:
        if not args.team or not re.fullmatch(r"[A-Z0-9]{10}", args.team):
            missing.append("Provide a valid --team identifier")
        if not args.identity or not args.identity.startswith("Developer ID Application:"):
            missing.append("Provide --identity with a Developer ID Application certificate")
        else:
            identities = capture(["security", "find-identity", "-v", "-p", "codesigning"])
            if f'"{args.identity}"' not in identities or f"({args.team})" not in args.identity:
                missing.append("The selected Developer ID identity is not valid in the current keychain or does not match the team")
    if args.notarize and (args.preview or not args.notary_profile):
        missing.append("Notarization requires signed mode and an existing --notary-profile")
    return missing


def verify(app, args):
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    extension = app / "Contents/PlugIns/CloakToolsFinder.appex"
    with (extension / "Contents/Info.plist").open("rb") as stream:
        ext_info = plistlib.load(stream)
    assert info["CFBundleVersion"] == ext_info["CFBundleVersion"], "Extension build differs"
    assert info["CFBundleShortVersionString"] == ext_info["CFBundleShortVersionString"], "Extension version differs"
    assert capture(["lipo", "-archs", str(app / "Contents/MacOS/CloakTools")]) == "arm64", "Unexpected architecture"
    if not args.preview:
        group = args.team + ".com.cloakyard.cloaktools"
        for bundle in [app, extension]:
            process = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)], capture_output=True, check=True)
            entitlements = plistlib.loads(process.stdout)
            assert entitlements.get("com.apple.developer.team-identifier") == args.team, "Team entitlement differs"
            assert group in entitlements.get("com.apple.security.application-groups", []), "Shared group is missing"
            signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(bundle)], capture_output=True, text=True, check=True).stderr
            assert "runtime" in signature and f"TeamIdentifier={args.team}" in signature, "Expected Developer ID hardened runtime signature"
            assert not entitlements.get("com.apple.security.get-task-allow", False), "Debug entitlement in release"
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", action="store_true", help="Build an ad-hoc local preview, never a public release")
    parser.add_argument("--preflight", action="store_true", help="Only report prerequisites")
    parser.add_argument("--team")
    parser.add_argument("--identity")
    parser.add_argument("--notarize", action="store_true", help="Submit the signed app to Apple, wait and staple")
    parser.add_argument("--notary-profile", help="Existing notarytool keychain profile; never a password or API key")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    missing = preflight(args)
    if missing:
        print(json.dumps({"status": "blocked", "missing": missing}, indent=2)); return 2
    if args.preflight:
        print(json.dumps({"status": "ready", "mode": "local-preview" if args.preview else "developer-id"}, indent=2)); return 0
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output = (args.output or MAC / "build/Packages" / stamp).resolve()
    output.mkdir(parents=True, exist_ok=False)
    log = output / "build.txt"
    # XcodeGen's explicit plist/entitlement settings are relative to the spec root.
    # Generate beside the spec, as build-native.sh does. Run build jobs serially.
    project = MAC
    derived = MAC / "build" / ("PreviewRelease" if args.preview else "SignedRelease")
    spec = "project.yml" if args.preview else "project-release.yml"
    run(["xcodegen", "generate", "--spec", spec, "--project", str(project)], log)
    command = ["xcodebuild", "-project", str(project / "CloakTools.xcodeproj"), "-scheme", "CloakTools",
               "-configuration", "Release", "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", str(derived), "build", "CLOAKTOOLS_SOURCE_ROOT=" + str(MAC)]
    if not args.preview:
        command += ["CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=" + args.team, "CODE_SIGN_IDENTITY=" + args.identity]
    run(command, log)
    app = derived / "Build/Products/Release/CloakTools.app"
    info = verify(app, args)
    version = info["CFBundleShortVersionString"]
    package = output / f"CloakTools-{version}{'-local-preview' if args.preview else ''}.zip"
    run(["ditto", "-c", "-k", "--keepParent", str(app), str(package)], log)
    if args.notarize:
        result = json.loads(capture(["xcrun", "notarytool", "submit", str(package), "--keychain-profile", args.notary_profile, "--wait", "--output-format", "json"]))
        (output / "notarization.json").write_text(json.dumps(result, indent=2) + "\n")
        if result.get("status") != "Accepted":
            raise RuntimeError("Apple did not accept this submission. Inspect notarization.json; no release is ready.")
        run(["xcrun", "stapler", "staple", str(app)], log)
        run(["xcrun", "stapler", "validate", str(app)], log)
        run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], log)
        package.unlink()  # This invocation's own archive, replaced with the stapled app.
        run(["ditto", "-c", "-k", "--keepParent", str(app), str(package)], log)
    checksum = hashlib.sha256(package.read_bytes()).hexdigest()
    (output / "SHA256SUMS").write_text(f"{checksum}  {package.name}\n")
    manifest = {"version": version, "build": info["CFBundleVersion"], "minimumOS": info["LSMinimumSystemVersion"],
                "architecture": "arm64", "signedWithDeveloperID": not args.preview, "notarized": bool(args.notarize),
                "archive": package.name, "bytes": package.stat().st_size, "sha256": checksum,
                "updatePolicy": "Sparkle; manual checks by default, automatic checks/downloads opt-in", "publicRelease": False}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (output / "README.txt").write_text("CloakTools " + version + "\n\n" +
        ("LOCAL DEVELOPMENT PREVIEW. Ad-hoc signed and not notarized. This is not a public installer.\n" if args.preview else
         "Developer ID build. Check manifest.json for notarization status. Publication and release QA are separate.\n") +
        "Unzip to review the app. Quit an older copy before moving it to Applications.\n"
        "Restore any CloakTools web/mail defaults before removing the app.\n"
        "Use Check for Updates; automatic checks/downloads are optional in About settings.\n")
    print(json.dumps({"status": "packaged", "directory": str(output), **manifest}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, subprocess.CalledProcessError, AssertionError, RuntimeError) as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        sys.exit(1)
