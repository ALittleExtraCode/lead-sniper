#!/usr/bin/env python3
"""
Stamps the site with what was actually built, and checks it.

The page reads dist/latest.json at runtime so the version can never drift, but
the fallbacks written into the HTML can, and a page that says 1.0 for the two
seconds before the fetch lands is a page that says the wrong thing. This writes
them, and then verifies the whole thing hangs together.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"


def main() -> int:
    manifest = SITE / "dist" / "latest.json"
    dmg = SITE / "dist" / "LeadSniper.dmg"
    page = SITE / "index.html"

    problems = []
    for needed in (manifest, dmg, page):
        if not needed.is_file():
            problems.append(f"missing {needed.relative_to(ROOT)}")
    if problems:
        print("\n".join("  ✗  " + p for p in problems))
        return 1

    latest = json.loads(manifest.read_text())
    real = hashlib.sha256(dmg.read_bytes()).hexdigest()
    size = f"{dmg.stat().st_size / 1_048_576:.1f} MB"

    # The manifest has to describe the file sitting next to it.
    if latest.get("sha256") != real:
        print(f"  ✗  latest.json sha does not match the DMG")
        print(f"       says {latest.get('sha256')}")
        print(f"       is   {real}")
        return 1

    html = page.read_text()
    html = re.sub(r'(<span data-version>)[^<]*(</span>)', rf'\g<1>{latest["version"]}\g<2>', html)
    html = re.sub(r'(<span data-size>)[^<]*(</span>)', rf'\g<1>{size}\g<2>', html)
    html = re.sub(r'(<span data-sha>)[^<]*(</span>)', rf'\g<1>{real}\g<2>', html)
    page.write_text(html)

    # Every local reference has to resolve, or the page ships with a broken image.
    local = set(re.findall(r'(?:src|href)="(/[^"]+)"', html))
    missing = []
    for ref in local:
        if not (SITE / ref.lstrip("/")).exists():
            missing.append(ref)
    if missing:
        print("  ✗  broken local links: " + ", ".join(sorted(missing)))
        return 1

    print(f"  ✓  stamped v{latest['version']}, {size}")
    print(f"  ✓  sha matches the DMG: {real[:16]}…")
    print(f"  ✓  {len(local)} local links all resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
