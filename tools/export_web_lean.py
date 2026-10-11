"""Export a lean Godot Web PCK, preserving the original desktop audio manifest."""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "src/core/audio_manifest.gd"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("godot", help="Godot executable name or absolute path")
    args = parser.parse_args()
    target = ROOT / "build/web/index.html"
    target.parent.mkdir(parents=True, exist_ok=True)
    original = MANIFEST.read_bytes()
    try:
        subprocess.run([sys.executable, str(ROOT / "tools/gen_manifest.py"), "--web"],
                       cwd=ROOT, check=True)
        subprocess.run([args.godot, "--headless", "--path", str(ROOT), "--import"],
                       cwd=ROOT, check=True)
        subprocess.run([args.godot, "--headless", "--path", str(ROOT),
                        "--export-release", "Web", str(target)], cwd=ROOT, check=True)
    finally:
        MANIFEST.write_bytes(original)
        print("[web-export] Restored native AudioManifest unchanged", flush=True)
    print(f"[web-export] lean PCK: {(ROOT / 'build/web/index.pck').stat().st_size:,} bytes", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
