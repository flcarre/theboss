import json
import pathlib
import shutil

from PIL import Image

SITE = pathlib.Path(__file__).resolve().parent.parent
GAME = SITE.parent / "Sources" / "TheBoss" / "Assets"
OUT = SITE / "public" / "assets"
GAME_ROBOTS = ["claude", "codex", "cursor", "gemini", "copilot"]
SITE_ONLY_ROBOTS: list[str] = []


def frames(folder: pathlib.Path):
    return sorted(folder.glob("*.png"), key=lambda p: int(p.stem))


def write_sheet(name: str, folder: pathlib.Path, meta: dict):
    images = [Image.open(f).convert("RGBA") for f in frames(folder)]
    size = max(max(i.size) for i in images)
    sheet = Image.new("RGBA", (size * len(images), size))
    for index, image in enumerate(images):
        sheet.paste(image, (index * size + (size - image.width) // 2, size - image.height))
    sheet.save(OUT / "sheets" / f"{name}.png", optimize=True)
    boxes = [sheet.crop((i * size, 0, (i + 1) * size, size)).getbbox() for i in range(len(images))]
    meta[name] = {"size": size, "frames": len(images), "top": min(b[1] for b in boxes), "foot": max(b[3] for b in boxes)}


def copy_rotations(folder: str):
    target = OUT / "characters" / folder / "rotations"
    target.mkdir(parents=True, exist_ok=True)
    for png in (GAME / "characters" / folder / "rotations").glob("*.png"):
        shutil.copy2(png, target / png.name)


def still_meta(folder: str):
    image = Image.open(OUT / "characters" / folder / "rotations" / "south.png")
    box = image.getbbox()
    return {"top": box[1], "foot": box[3]}


def main():
    (OUT / "sheets").mkdir(parents=True, exist_ok=True)
    for sub in ["objects", "walls"]:
        target = OUT / sub
        target.mkdir(parents=True, exist_ok=True)
        for png in (GAME / sub).glob("*.png"):
            shutil.copy2(png, target / png.name)
    (OUT / "icons").mkdir(parents=True, exist_ok=True)
    for png in (GAME / "icons").glob("*.png"):
        image = Image.open(png).convert("RGBA")
        image.crop(image.getbbox()).save(OUT / "icons" / png.name)
    shutil.copy2(GAME / "AppIcon.png", OUT / "AppIcon.png")

    meta: dict = {}
    copy_rotations("boss")
    for kind in ["walk", "whip"]:
        for direction in ["south", "north", "east", "west"]:
            write_sheet(f"boss_{kind}_{direction}", GAME / "characters" / "boss" / kind / direction, meta)
    for robot in GAME_ROBOTS:
        copy_rotations(f"robot_{robot}")
        for kind in ["typing", "alert"]:
            write_sheet(f"robot_{robot}_{kind}_south", GAME / "characters" / f"robot_{robot}" / kind / "south", meta)

    (OUT / "thumbs").mkdir(parents=True, exist_ok=True)
    for folder in ["boss"] + [f"robot_{r}" for r in GAME_ROBOTS + SITE_ONLY_ROBOTS]:
        image = Image.open(OUT / "characters" / folder / "rotations" / "south.png").convert("RGBA")
        image.crop(image.getbbox()).save(OUT / "thumbs" / f"{folder}.png")

    stills = {"boss": still_meta("boss")}
    for robot in GAME_ROBOTS + SITE_ONLY_ROBOTS:
        stills[robot] = still_meta(f"robot_{robot}")

    objects = {}
    for png in sorted((OUT / "objects").glob("*.png")):
        image = Image.open(png)
        objects[png.stem] = {"w": image.width, "h": image.height, "bottom": image.getbbox()[3]}

    print(json.dumps({"sheets": meta, "stills": stills, "objects": objects}, indent=1))


if __name__ == "__main__":
    main()
