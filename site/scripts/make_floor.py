import random
from PIL import Image, ImageDraw

SIZE = 128
PLANK = 16
TONES = ["#B5703A", "#AE6A35", "#BC7740", "#A86532"]
GAP = "#6E3A1C"


def rgba(hex_color, alpha=255):
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def wood(path, seed=7):
    rand = random.Random(seed)
    base = Image.new("RGBA", (SIZE, SIZE))
    overlay = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    shade = ImageDraw.Draw(overlay)
    lengths = [64, 48, 80, 56]
    for row in range(SIZE // PLANK):
        y = row * PLANK
        x = -((row % 2) * 48 + (row % 3) * 16)
        i = row
        while x < SIZE:
            length = lengths[i % len(lengths)]
            for dx in (0, SIZE):
                left = x + dx if x < 0 else x
                draw.rectangle([left, y, left + length - 1, y + PLANK - 1], fill=rgba(TONES[(i * 7 + row) % len(TONES)]))
                shade.rectangle([left, y, left + length - 1, y + 1], fill=(255, 226, 170, 40))
                shade.rectangle([left, y + PLANK - 3, left + length - 1, y + PLANK - 2], fill=(70, 30, 10, 46))
                for _ in range(3):
                    gy = y + 4 + rand.randrange(8)
                    gx = left + 4 + rand.randrange(max(8, length - 24))
                    shade.rectangle([gx, gy, gx + 6 + rand.randrange(14), gy], fill=(90, 40, 14, 72))
                draw.rectangle([left + length - 1, y, left + length - 1, y + PLANK - 1], fill=rgba(GAP))
                if x >= 0:
                    break
            x += length
            i += 1
        draw.rectangle([0, y + PLANK - 1, SIZE - 1, y + PLANK - 1], fill=rgba(GAP))
    Image.alpha_composite(base, overlay).save(path)


if __name__ == "__main__":
    wood("public/assets/tiles/wood.png")
