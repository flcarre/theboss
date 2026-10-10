import pathlib

from PIL import Image

OUT = pathlib.Path(__file__).resolve().parent.parent / "public" / "assets" / "tiles"
TILE = 64
COLS = 18
ROWS = 8
MASK = 0xFFFFFFFF


def noise(x: int, y: int, seed: int) -> int:
    h = (x * 374761393 + y * 668265263 + seed * 2147483647) & MASK
    h = ((h ^ (h >> 13)) * 1274126177) & MASK
    return (h ^ (h >> 16)) & 0xFFFF


def shade(hex_color: int, factor: float) -> int:
    r = int(((hex_color >> 16) & 0xFF) * factor)
    g = int(((hex_color >> 8) & 0xFF) * factor)
    b = int((hex_color & 0xFF) * factor)
    return (r << 16) | (g << 8) | b


def rgb(hex_color: int):
    return ((hex_color >> 16) & 0xFF, (hex_color >> 8) & 0xFF, hex_color & 0xFF, 255)


def carpet(variant: int) -> Image.Image:
    image = Image.new("RGBA", (TILE, TILE))
    for y in range(TILE):
        for x in range(TILE):
            tile = ((x // 32) + (y // 32) + variant) % 2
            base = 0x5B6B8C if tile == 0 else 0x55647F
            n = noise(x + variant * 64, y, 11) % 100
            color = base
            if n < 18:
                color = shade(base, 0.88)
            if n > 92:
                color = 0x6E7FA3
            if tile == 0 and (x + y) % 8 == 0:
                color = shade(base, 0.92)
            if x % 32 == 0 or y % 32 == 0:
                color = 0x46536C
            image.putpixel((x, y), rgb(color))
    return image


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = [carpet(v) for v in range(4)]
    floor = Image.new("RGBA", (COLS * TILE, ROWS * TILE))
    for c in range(COLS):
        for r in range(ROWS):
            variant = (c * 73 + r * 151 + c * r * 7) % 97 % 4
            floor.paste(tiles[variant], (c * TILE, (ROWS - 1 - r) * TILE))
    floor.save(OUT / "carpet_openspace.png", optimize=True)
    pattern = Image.new("RGBA", (TILE * 2, TILE * 2))
    for index, variant in enumerate([0, 2, 3, 1]):
        pattern.paste(tiles[variant], ((index % 2) * TILE, (index // 2) * TILE))
    pattern.save(OUT / "carpet.png", optimize=True)


if __name__ == "__main__":
    main()
