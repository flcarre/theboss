import json
import pathlib
import sys
import urllib.request

from PIL import Image, ImageOps

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "design" / "pixellab.json"
OUT = ROOT / "Sources" / "TheBoss" / "Assets"


def fetch(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and "--force" not in sys.argv:
        return
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 TheBoss"})
    with urllib.request.urlopen(request) as response:
        dest.write_bytes(response.read())
    print("ok", dest.relative_to(ROOT))


def main():
    manifest = json.loads(MANIFEST.read_text())
    for name, character in manifest["characters"].items():
        base = character["base"]
        for direction in character.get("rotations", []):
            fetch(f"{base}/rotations/{direction}.png", OUT / "characters" / name / "rotations" / f"{direction}.png")
        for animation, directions in character.get("animations", {}).items():
            for direction, spec in directions.items():
                for index in range(spec["frames"]):
                    url = f"{base}/animations/{spec['id']}/{direction}/{index}.png"
                    fetch(url, OUT / "characters" / name / animation / direction / f"{index}.png")
        for target, source in character.get("mirrored", {}).items():
            source_dir = OUT / "characters" / name / source
            target_dir = OUT / "characters" / name / target
            target_dir.mkdir(parents=True, exist_ok=True)
            for frame in sorted(source_dir.glob("*.png")):
                destination = target_dir / frame.name
                if not destination.exists() or "--force" in sys.argv:
                    ImageOps.mirror(Image.open(frame)).save(destination)
    for name, url in manifest.get("objects", {}).items():
        fetch(url, OUT / "objects" / f"{name}.png")
    for name, url in manifest.get("icons", {}).items():
        fetch(url, OUT / "icons" / f"{name}.png")


main()
