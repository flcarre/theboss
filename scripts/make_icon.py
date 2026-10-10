import pathlib
import subprocess
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Sources" / "TheBoss" / "Assets"
OUT = ROOT / "build"


def art():
    size = 128
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ink, base, raised, crust = (42, 24, 64, 255), (43, 37, 71, 255), (58, 50, 96, 255), (245, 185, 66, 255)
    inset = 6
    for y in range(inset, size - inset):
        for x in range(inset, size - inset):
            corner = min(x - inset, size - inset - 1 - x) + min(y - inset, size - inset - 1 - y)
            if corner < 10:
                continue
            edge = min(x - inset, size - inset - 1 - x, y - inset, size - inset - 1 - y)
            if edge < 2:
                canvas.putpixel((x, y), ink)
            elif edge < 5:
                canvas.putpixel((x, y), crust)
            elif edge < 6:
                canvas.putpixel((x, y), ink)
            else:
                canvas.putpixel((x, y), raised if (x // 8 + y // 8) % 2 else base)
    robot = Image.open(ASSETS / "characters/robot_claude/rotations/south.png").convert("RGBA").crop((14, 10, 102, 114))
    boss = Image.open(ASSETS / "characters/boss/rotations/south.png").convert("RGBA").crop((30, 14, 100, 116))
    canvas.alpha_composite(robot, (40, 16))
    canvas.alpha_composite(boss, (6, 22))
    return canvas


def main():
    OUT.mkdir(exist_ok=True)
    image = art()
    big = image.resize((1024, 1024), Image.NEAREST)
    big.save(ASSETS / "AppIcon.png")
    iconset = OUT / "AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    for points in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            pixels = points * scale
            big.resize((pixels, pixels), Image.NEAREST).save(iconset / f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png")
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT / "AppIcon.icns")], check=True)


main()
