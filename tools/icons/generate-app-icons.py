#!/usr/bin/env python3
"""Generate all app icon PNGs from the supplied rounded-square source image.

Usage (from the repository root):
    python3 tools/icons/generate-app-icons.py /tmp/icon-source-A.jpg

Requires Python 3 and Pillow 11.3.0. If no source path is supplied, the
script uses /tmp/icon-source-A.jpg. Only the app-icon image outputs are
written; Xcode asset catalogs and source files are not modified.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter
import PIL


ROOT = Path(__file__).resolve().parents[2]
APP_DIR = ROOT / "apple" / "OpenTranslate" / "Shared (App)"
APP_ICON_DIR = APP_DIR / "Assets.xcassets" / "AppIcon.appiconset"
LARGE_ICON_PATH = APP_DIR / "Assets.xcassets" / "LargeIcon.imageset" / "128.png"
RESOURCE_ICON_PATH = APP_DIR / "Resources" / "Icon.png"
BLACK_THRESHOLD = 16
MAC_ART_SIZE = 824
MAC_CANVAS_SIZE = 1024


def connected_silhouette(rgb: Image.Image) -> Image.Image:
    """Keep the non-black component connected to the icon's center.

    JPEG compression can create isolated dark-background speckles. Restricting
    the mask to the center-connected component prevents those speckles from
    becoming seeds in either the crop bounds or corner diffusion.
    """
    width, height = rgb.size
    brightest = ImageChops.lighter(
        ImageChops.lighter(rgb.getchannel("R"), rgb.getchannel("G")),
        rgb.getchannel("B"),
    ).tobytes()
    candidates = bytearray(value > BLACK_THRESHOLD for value in brightest)
    seed = (height // 2) * width + width // 2
    if not candidates[seed]:
        raise ValueError("The source image center is not inside the icon")

    connected = bytearray(width * height)
    connected[seed] = 1
    queue = [seed]
    cursor = 0
    while cursor < len(queue):
        index = queue[cursor]
        cursor += 1
        x = index % width
        y = index // width
        for dy in (-1, 0, 1):
            ny = y + dy
            if ny < 0 or ny >= height:
                continue
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                nx = x + dx
                if 0 <= nx < width:
                    neighbor = ny * width + nx
                    if candidates[neighbor] and not connected[neighbor]:
                        connected[neighbor] = 1
                        queue.append(neighbor)

    return Image.frombytes(
        "L", (width, height), bytes(255 if value else 0 for value in connected)
    )


def find_icon_crop(source: Image.Image) -> Image.Image:
    """Crop away the near-black backdrop and normalize the crop to a square."""
    rgb = source.convert("RGB")
    silhouette = connected_silhouette(rgb)
    bounds = silhouette.getbbox()
    if bounds is None:
        raise ValueError("Source image contains no non-black icon pixels")

    left, top, right, bottom = bounds
    side = max(right - left, bottom - top)
    center_x = (left + right) / 2
    center_y = (top + bottom) / 2
    crop_left = round(center_x - side / 2)
    crop_top = round(center_y - side / 2)
    crop_left = min(max(crop_left, 0), rgb.width - side)
    crop_top = min(max(crop_top, 0), rgb.height - side)
    return rgb.crop((crop_left, crop_top, crop_left + side, crop_top + side))


def diffuse_black_corners(crop: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Extend adjacent icon colors through the rounded-square's black corners.

    Pixels above BLACK_THRESHOLD seed a simultaneous 8-neighbor mean
    diffusion. Each outside pixel is filled once from already-filled neighbors,
    preserving the original icon pixels while smoothly extrapolating its edge.
    """
    width, height = crop.size
    if width != height:
        raise ValueError(f"Expected square crop, got {crop.size}")

    pixels = bytearray(crop.tobytes())
    silhouette = connected_silhouette(crop)
    silhouette_pixels = silhouette.tobytes()
    known = bytearray(value != 0 for value in silhouette_pixels)
    silhouette = known.copy()

    def adjacent_indices(index: int):
        x = index % width
        y = index // width
        for dy in (-1, 0, 1):
            ny = y + dy
            if ny < 0 or ny >= height:
                continue
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                nx = x + dx
                if 0 <= nx < width:
                    yield ny * width + nx

    frontier: set[int] = set()
    for index, is_known in enumerate(known):
        if is_known:
            frontier.update(
                neighbor
                for neighbor in adjacent_indices(index)
                if not known[neighbor]
            )

    filled = sum(known)
    total = width * height
    while frontier:
        current_frontier = frontier
        next_frontier: set[int] = set()
        for index in frontier:
            sums = [0, 0, 0]
            neighbor_count = 0
            for neighbor in adjacent_indices(index):
                if known[neighbor]:
                    offset = neighbor * 3
                    sums[0] += pixels[offset]
                    sums[1] += pixels[offset + 1]
                    sums[2] += pixels[offset + 2]
                    neighbor_count += 1
                elif neighbor not in current_frontier:
                    next_frontier.add(neighbor)

            if neighbor_count:
                offset = index * 3
                pixels[offset] = (sums[0] + neighbor_count // 2) // neighbor_count
                pixels[offset + 1] = (sums[1] + neighbor_count // 2) // neighbor_count
                pixels[offset + 2] = (sums[2] + neighbor_count // 2) // neighbor_count

        for index in frontier:
            known[index] = 1
        filled += len(frontier)
        frontier = next_frontier

    if filled != total:
        raise ValueError(f"Could not diffuse all crop pixels ({filled}/{total})")

    extended = Image.frombytes("RGB", crop.size, bytes(pixels))
    alpha = Image.frombytes(
        "L", crop.size, silhouette_pixels
    ).filter(ImageFilter.GaussianBlur(radius=0.65))
    return extended, alpha


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "source",
        nargs="?",
        type=Path,
        default=Path("/tmp/icon-source-A.jpg"),
        help="1254x1254 rounded-square source image (default: /tmp/icon-source-A.jpg)",
    )
    args = parser.parse_args()

    if PIL.__version__ != "11.3.0":
        raise SystemExit(
            f"Pillow 11.3.0 is required; found Pillow {PIL.__version__}"
        )
    if not args.source.is_file():
        raise SystemExit(f"Source image not found: {args.source}")

    with Image.open(args.source) as source_file:
        crop = find_icon_crop(source_file)
    extended_rgb, alpha = diffuse_black_corners(crop)

    APP_ICON_DIR.mkdir(parents=True, exist_ok=True)
    large_icon = Image.merge("RGBA", (*extended_rgb.split(), alpha))

    # iOS uses a full-bleed, opaque square. Diffusion removes the source's
    # black backdrop from the four rounded corners without leaving empty pixels.
    ios_icon = extended_rgb.resize(
        (1024, 1024), Image.Resampling.LANCZOS
    ).convert("RGB")
    ios_icon.save(APP_ICON_DIR / "universal-icon-1024@1x.png", format="PNG")

    # macOS keeps the rounded silhouette and adds a 100 px transparent border
    # around an 824 px icon on the 1024 px master canvas.
    mac_master = Image.new("RGBA", (MAC_CANVAS_SIZE, MAC_CANVAS_SIZE), (0, 0, 0, 0))
    mac_art = large_icon.resize((MAC_ART_SIZE, MAC_ART_SIZE), Image.Resampling.LANCZOS)
    mac_master.alpha_composite(mac_art, (100, 100))
    mac_sizes = (
        ("mac-icon-16@1x.png", 16),
        ("mac-icon-16@2x.png", 32),
        ("mac-icon-32@1x.png", 32),
        ("mac-icon-32@2x.png", 64),
        ("mac-icon-128@1x.png", 128),
        ("mac-icon-128@2x.png", 256),
        ("mac-icon-256@1x.png", 256),
        ("mac-icon-256@2x.png", 512),
        ("mac-icon-512@1x.png", 512),
        ("mac-icon-512@2x.png", 1024),
    )
    for filename, size in mac_sizes:
        mac_master.resize((size, size), Image.Resampling.LANCZOS).save(
            APP_ICON_DIR / filename, format="PNG"
        )

    # The two standalone 128 px resources retain the rounded transparent edge,
    # but do not use macOS's additional 100 px transparent inset.
    large_icon.resize((128, 128), Image.Resampling.LANCZOS).save(
        LARGE_ICON_PATH, format="PNG"
    )
    large_icon.resize((128, 128), Image.Resampling.LANCZOS).save(
        RESOURCE_ICON_PATH, format="PNG"
    )

    print(f"Generated app icons from {args.source}")
    print(f"Source crop: {crop.width}x{crop.height}")
    print(f"Outputs: 13 PNG files under {APP_DIR}")


if __name__ == "__main__":
    main()
