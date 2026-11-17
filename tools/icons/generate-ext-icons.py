#!/usr/bin/env python3
"""Generate alpha-masked Safari extension icons from icon-source-A.jpg."""

from pathlib import Path

from PIL import Image, ImageDraw
import PIL


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path("/tmp/icon-source-A.jpg")
SIZES = (16, 32, 48, 96, 128)
PIL_VERSION = "11.3.0"
SOURCE_DIMENSIONS = (1254, 1254)
FOREGROUND_THRESHOLD = 20
CORNER_RADIUS_RATIO = 0.24
MASK_SUPERSAMPLE = 4

OUTPUT_DIRS = (
    REPO_ROOT / "extension/public/icon",
    REPO_ROOT / "apple/OpenTranslate/Shared (Extension)/Resources/icon",
)


def foreground_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    """Find the icon's non-black bounds, ignoring low-level JPEG ringing."""
    pixels = image.load()
    min_x, min_y = image.width, image.height
    max_x = max_y = -1

    for y in range(image.height):
        for x in range(image.width):
            if max(pixels[x, y]) <= FOREGROUND_THRESHOLD:
                continue
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x)
            max_y = max(max_y, y)

    if max_x < min_x or max_y < min_y:
        raise ValueError("Could not find the icon foreground in the source image")

    # PIL crop boxes use exclusive right and bottom coordinates.
    return min_x, min_y, max_x + 1, max_y + 1


def rounded_square_mask(size: tuple[int, int]) -> Image.Image:
    width, height = size
    scale = MASK_SUPERSAMPLE
    mask = Image.new("L", (width * scale, height * scale), 0)
    radius = round(min(width, height) * CORNER_RADIUS_RATIO * scale)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, width * scale - 1, height * scale - 1),
        radius=radius,
        fill=255,
    )
    return mask.resize(size, Image.Resampling.LANCZOS)


def main() -> None:
    if PIL.__version__ != PIL_VERSION:
        raise RuntimeError(f"Pillow {PIL_VERSION} is required; found {PIL.__version__}")
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Source image not found: {SOURCE}")

    with Image.open(SOURCE) as opened:
        source = opened.convert("RGB")

    if source.size != SOURCE_DIMENSIONS:
        raise ValueError(f"Expected source dimensions {SOURCE_DIMENSIONS}; found {source.size}")

    crop_box = foreground_bounds(source)
    icon = source.crop(crop_box)
    icon.putalpha(rounded_square_mask(icon.size))

    for output_dir in OUTPUT_DIRS:
        output_dir.mkdir(parents=True, exist_ok=True)
        for size in SIZES:
            # Resizing premultiplied RGBA avoids dark halos at transparent edges.
            output = icon.convert("RGBa").resize(
                (size, size), Image.Resampling.LANCZOS
            ).convert("RGBA")
            output_path = output_dir / f"{size}.png"
            output.save(output_path, format="PNG", optimize=True)

            with Image.open(output_path) as written:
                if written.size != (size, size):
                    raise AssertionError(f"Wrong dimensions in {output_path}: {written.size}")
                if written.mode != "RGBA":
                    raise AssertionError(f"Missing alpha channel in {output_path}: {written.mode}")
                alpha_min, alpha_max = written.getchannel("A").getextrema()
                if alpha_min != 0 or alpha_max != 255:
                    raise AssertionError(
                        f"Unexpected alpha range in {output_path}: {(alpha_min, alpha_max)}"
                    )
            print(f"{output_path.relative_to(REPO_ROOT)}: {size}x{size}, RGBA alpha={alpha_min}..{alpha_max}")


if __name__ == "__main__":
    main()
