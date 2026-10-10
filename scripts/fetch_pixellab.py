import json
import pathlib
import sys
import urllib.request

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
    for name, url in manifest.get("objects", {}).items():
        fetch(url, OUT / "objects" / f"{name}.png")


main()
