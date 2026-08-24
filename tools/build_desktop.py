#!/usr/bin/env python3
"""
Builds LeadSniper.app, signs it, has Apple notarise it, and wraps it in a DMG.

Deliberately the same shape as SunoGet's build script, including the two things
that script learned the hard way:

  · notarise the .app *and* the .dmg separately. A ticket stapled to the disk
    image does not travel with an app copied out of it.
  · refuse to publish an unnotarised build. Shipping one puts the "Apple could
    not verify this app" wall in front of every download, and a build that half
    succeeded is worse than one that failed.

Usage:  python3 tools/build_desktop.py
"""
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "macapp"
BUILD = ROOT / ".build"
DIST = ROOT / "site" / "dist"

APP_NAME = "LeadSniper.app"
APP_VERSION = "1.4"
BUNDLE_ID = "com.leadsniper.app"
NOTARY_PROFILE = os.environ.get("LEADSNIPER_NOTARY_PROFILE", "sunoget-notary")

# Every source except the test suites and their fixtures.
EXCLUDED = {"engine_tests", "Fixtures"}


def sources() -> list[Path]:
    files = sorted(p for p in SRC.glob("*.swift") if p.stem not in EXCLUDED)
    if not any(p.name == "main.swift" for p in files):
        raise SystemExit("no main.swift in macapp/")
    return files


def sh(*args, **kwargs):
    return subprocess.run(args, check=False, capture_output=True, text=True, **kwargs)


# ── the icon ────────────────────────────────────────────────────────────────

def build_icon(dest: Path) -> bool:
    """Draws the mark rather than loading one.

    There is no logo asset to start from, and a generated icon that is a few
    plain shapes in the app's own palette beats the blank applet tile. A ring
    with a gap and a single dot: a radar sweep that has found one thing, which
    is what the product does.
    """
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("  !  Pillow not installed; keeping the default applet icon")
        return False

    S = 1024
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)

    # The rounded tile, in a vertical wash from the app's two accent ends.
    inset, radius = 96, 224
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(tile)
    top, end = (0x22, 0xd3, 0xee), (0x43, 0x38, 0xca)
    for y in range(S):
        t = y / (S - 1)
        td.line([(0, y), (S, y)],
                fill=tuple(int(top[i] + (end[i] - top[i]) * t) for i in range(3)) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([inset, inset, S - inset, S - inset],
                                           radius=radius, fill=255)
    canvas.paste(tile, (0, 0), mask)

    # Two rings with a gap at the top right, so it reads as sweeping rather
    # than as a target.
    cx = cy = S // 2
    white = (255, 255, 255, 235)
    for r, w in ((250, 30), (150, 24)):
        d.arc([cx - r, cy - r, cx + r, cy + r], start=310, end=250, fill=white, width=w)

    # The one thing found, sitting on the outer ring's gap.
    d.ellipse([cx + 150, cy - 200, cx + 226, cy - 124], fill=(255, 255, 255, 255))
    # And the centre.
    d.ellipse([cx - 34, cy - 34, cx + 34, cy + 34], fill=white)

    iconset = BUILD / "LeadSniper.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)
    for size in (16, 32, 128, 256, 512):
        canvas.resize((size, size), Image.LANCZOS).save(iconset / f"icon_{size}x{size}.png")
        canvas.resize((size * 2, size * 2), Image.LANCZOS).save(iconset / f"icon_{size}x{size}@2x.png")
    sh("iconutil", "-c", "icns", str(iconset), "-o", str(dest))
    shutil.rmtree(iconset)
    return dest.is_file()


# ── signing and notarising ──────────────────────────────────────────────────

def developer_id_identity():
    out = sh("security", "find-identity", "-v", "-p", "codesigning").stdout
    for line in out.splitlines():
        if "Developer ID Application" in line and '"' in line:
            return line.split('"')[1]
    return None


def notary_args():
    """Keychain profile, or the environment, whichever is there."""
    trio = [os.environ.get(k) for k in
            ("LEADSNIPER_APPLE_ID", "LEADSNIPER_TEAM_ID", "LEADSNIPER_APP_PASSWORD")]
    if all(trio):
        return ["--apple-id", trio[0], "--team-id", trio[1], "--password", trio[2]]
    return ["--keychain-profile", NOTARY_PROFILE]


def has_notary_credentials() -> bool:
    """Whether notarisation can run.

    Three attempts backing off, and only notarytool's own words for an absent
    profile count as one. This check reaches Apple, so a service-side blip looks
    identical to a missing credential from outside -- and reporting the second
    when it is the first sends someone off to re-create a credential that was
    never gone. That mistake cost a release in the SunoGet build.
    """
    last = ""
    for attempt, wait in enumerate((5, 20, 0)):
        r = sh("xcrun", "notarytool", "history", *notary_args())
        if r.returncode == 0:
            if attempt:
                print(f"  …  notarytool answered on attempt {attempt + 1}")
            return True
        last = (r.stderr or "") + (r.stdout or "")
        if wait:
            time.sleep(wait)

    if "No Keychain password item" in last:
        print(f"  !  the notarytool credential {NOTARY_PROFILE!r} is not in the keychain.")
        print("     Put it back with:")
        print(f'       xcrun notarytool store-credentials "{NOTARY_PROFILE}" \\')
        print("           --apple-id <apple-id> --team-id <team> --password <app-specific-password>")
    else:
        print("  !  the credential looks present but Apple did not answer:")
        print("\n".join("       " + l for l in last.strip().splitlines()[:3]))
        print("     This is usually temporary. Run the build again before assuming anything.")
    return False


def sign(target: Path, identity: str, entitlements: Path | None = None) -> bool:
    args = ["codesign", "--force", "--timestamp", "--options", "runtime",
            "--sign", identity]
    if entitlements:
        args += ["--entitlements", str(entitlements)]
    r = sh(*args, str(target))
    if r.returncode != 0:
        print(f"  ✗  could not sign {target.name}: {r.stderr.strip()[:200]}")
        return False
    return True


def notarise(target: Path, label: str) -> bool:
    """Submits, waits, and staples the ticket onto the original.

    A bundle cannot be submitted directly -- notarytool takes .zip, .pkg or
    .dmg only -- so an .app goes up inside a zip and the ticket is stapled back
    onto the bundle afterwards. Stapling the zip would achieve nothing: the zip
    is thrown away and the app is what gets copied to /Applications.
    """
    submitted = target
    scratch = None
    if target.suffix == ".app":
        scratch = BUILD / "notarise.zip"
        if scratch.exists():
            scratch.unlink()
        z = sh("ditto", "-c", "-k", "--keepParent", str(target), str(scratch))
        if z.returncode != 0:
            print(f"  ✗  could not archive the {label}: {z.stderr.strip()[:200]}")
            return False
        submitted = scratch

    print(f"  …  submitting the {label} to Apple (usually 1-5 minutes)")
    r = subprocess.run(["xcrun", "notarytool", "submit", str(submitted),
                        *notary_args(), "--wait"],
                       capture_output=True, text=True)
    if scratch and scratch.exists():
        scratch.unlink()
    print("\n".join("     " + l for l in r.stdout.strip().splitlines()[-6:]))
    if "status: Accepted" not in r.stdout:
        print(f"  ✗  the {label} was not accepted")
        return False
    staple = sh("xcrun", "stapler", "staple", str(target))
    if staple.returncode != 0:
        print(f"  ✗  could not staple the {label}: {staple.stdout.strip()[:200]}")
        return False
    print(f"  ✓  {label} notarised and stapled")
    return True


# ── the app ─────────────────────────────────────────────────────────────────

def build_app() -> Path | None:
    BUILD.mkdir(parents=True, exist_ok=True)
    app = BUILD / APP_NAME
    if app.exists():
        shutil.rmtree(app)
    macos = app / "Contents" / "MacOS"
    res = app / "Contents" / "Resources"
    macos.mkdir(parents=True)
    res.mkdir(parents=True)

    binary = macos / "LeadSniper"
    files = [str(p) for p in sources()]
    print(f"  …  compiling {len(files)} sources")
    # Universal, so it runs on Intel as well as Apple Silicon.
    r = sh("swiftc", "-O", "-target", "arm64-apple-macos12", "-o", str(binary) + ".arm64", *files)
    if r.returncode != 0:
        print("  ✗  arm64 build failed:")
        print("\n".join("      " + l for l in r.stderr.splitlines() if "error:" in l)[:2000])
        return None
    r = sh("swiftc", "-O", "-target", "x86_64-apple-macos12", "-o", str(binary) + ".x86_64", *files)
    if r.returncode != 0:
        print("  ✗  x86_64 build failed:")
        print("\n".join("      " + l for l in r.stderr.splitlines() if "error:" in l)[:2000])
        return None
    sh("lipo", "-create", str(binary) + ".arm64", str(binary) + ".x86_64", "-output", str(binary))
    Path(str(binary) + ".arm64").unlink()
    Path(str(binary) + ".x86_64").unlink()
    binary.chmod(0o755)
    print("  ✓  universal binary")

    has_icon = build_icon(res / "AppIcon.icns")

    info = {
        "CFBundleName": "LeadSniper",
        "CFBundleDisplayName": "LeadSniper",
        "CFBundleExecutable": "LeadSniper",
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleShortVersionString": APP_VERSION,
        "CFBundleVersion": APP_VERSION,
        "CFBundlePackageType": "APPL",
        "LSMinimumSystemVersion": "12.0",
        "NSHighResolutionCapable": True,
        "NSHumanReadableCopyright": "LeadSniper",
        "LSApplicationCategoryType": "public.app-category.business",
    }
    if has_icon:
        info["CFBundleIconFile"] = "AppIcon"
    (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps(info))

    # The app reads public feeds and opens links. Nothing else.
    ents = BUILD / "leadsniper.entitlements"
    ents.write_bytes(plistlib.dumps({
        "com.apple.security.cs.allow-jit": False,
        "com.apple.security.network.client": True,
    }))

    identity = developer_id_identity()
    if not identity:
        print("  !  no Developer ID found; signing ad-hoc")
        sh("codesign", "--force", "--sign", "-", str(app))
        return app
    if not sign(app, identity, ents):
        return None
    print(f"  ✓  signed with {identity}")
    return app


def build_dmg(app: Path) -> Path | None:
    stage = BUILD / "stage"
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    shutil.copytree(app, stage / APP_NAME, symlinks=True)
    (stage / "Applications").symlink_to("/Applications")

    dmg = BUILD / "LeadSniper.dmg"
    if dmg.exists():
        dmg.unlink()
    r = sh("hdiutil", "create", "-volname", "LeadSniper", "-srcfolder", str(stage),
           "-ov", "-format", "UDZO", str(dmg))
    if r.returncode != 0:
        print(f"  ✗  could not build the disk image: {r.stderr.strip()[:200]}")
        return None
    identity = developer_id_identity()
    if identity and not sign(dmg, identity):
        return None
    print("  ✓  disk image built and signed")
    return dmg


def human(size: int) -> str:
    return f"{size / 1_048_576:.1f} MB"


def main() -> int:
    print(f"\nLeadSniper {APP_VERSION}\n")

    app = build_app()
    if app is None:
        return 1

    identity = developer_id_identity()
    can_notarise = bool(identity) and has_notary_credentials()

    if can_notarise and not notarise(app, "app"):
        return 1

    dmg = build_dmg(app)
    if dmg is None:
        return 1

    if can_notarise:
        if not notarise(dmg, "disk image"):
            return 1
    elif identity:
        print("\n  ✗  Refusing to publish: signed with a Developer ID but not")
        print("     notarised. Shipping it puts the \"Apple could not verify this")
        print("     app\" wall in front of every download.")
        print(f"\n     The build is at {dmg} if you want it for yourself.")
        return 1

    DIST.mkdir(parents=True, exist_ok=True)
    published = DIST / "LeadSniper.dmg"
    shutil.copy2(dmg, published)

    digest = sh("shasum", "-a", "256", str(published)).stdout.split()[0]
    (DIST / "latest.json").write_text(json.dumps({
        "version": APP_VERSION,
        "url": "https://leadsniper.com/dist/LeadSniper.dmg",
        "sha256": digest,
    }, indent=2) + "\n")

    print(f"\n  LeadSniper.dmg   {human(published.stat().st_size)}   sha256 {digest}")
    print(f"  ✓  published to {published}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
