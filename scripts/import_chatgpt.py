import json
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
REQUESTS = ROOT / "design" / "chatgpt" / "requests.json"
INBOX = ROOT / "design" / "chatgpt" / "generated"


def native(image, width, height, transparent):
    image = image.convert("RGBA")
    if transparent:
        box = image.getchannel("A").point(lambda a: 255 if a > 128 else 0).getbbox()
        if box:
            image = image.crop(box)
        image.thumbnail((width, height), Image.NEAREST)
    else:
        image = image.resize((width, height), Image.NEAREST)
    alpha = image.getchannel("A").point(lambda a: 255 if a > 128 else 0)
    rgb = image.convert("RGB").quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    rgb.putalpha(alpha)
    return rgb


def main():
    only = set(sys.argv[1:])
    requests = json.loads(REQUESTS.read_text())
    for asset in requests["assets"]:
        if only and asset["file"] not in only:
            continue
        source = INBOX / asset["file"]
        if not source.exists():
            print("missing", source.relative_to(ROOT))
            continue
        width, height = (int(v) for v in asset["native_size"].split("x"))
        result = native(Image.open(source), width, height, asset["background"] == "transparent")
        target = ROOT / asset["target"]
        target.parent.mkdir(parents=True, exist_ok=True)
        result.save(target)
        print("ok", target.relative_to(ROOT), result.size)


main()
