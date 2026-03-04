#!/usr/bin/env python3
"""
Preprocesses raw art drops into runtime-ready transparent UI assets.

Reasoning:
- The source images are mostly RGB PNGs with a flat pearl backdrop.
- Rendering them directly in squares/bars creates visible rectangular boxes.
- We remove only the background connected to image borders, then trim/scale.
  This keeps internal light details intact while making the assets composable.
"""

from __future__ import annotations

from collections import deque
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ASSETS_DIR = ROOT / "assets"
GENERATED_DIR = ASSETS_DIR / "generated"
PIECES_DIR = GENERATED_DIR / "pieces"
UI_DIR = GENERATED_DIR / "ui"
SHESHBESH_DIR = GENERATED_DIR / "sheshbesh"

PIECE_BG_TOLERANCE = 6
PIECE_ALPHA_BLUR_RADIUS = 0.35
BOARD_CANVAS_SIZE = 1024
BOARD_PLAYABLE_INSET = 120
BOARD_PLAYABLE_SIZE = BOARD_CANVAS_SIZE - (BOARD_PLAYABLE_INSET * 2)
BACKGAMMON_BOARD_SIZE = 1024

SOURCE_PIECES = {
    "wP.png": ("wP.png-removebg-preview.png", "wP.png.png"),
    "wR.png": ("wR.png-removebg-preview.png", "wR.png.png"),
    "wN.png": ("wK.png-removebg-preview.png", "wK.png.png"),
    "wB.png": ("wB.png-removebg-preview.png", "wB.png.png"),
    "wQ.png": ("wQ.png-removebg-preview.png", "wQ.png.png"),
    "wK.png": ("wKing.png-removebg-preview.png", "wKing.png.png"),
    "bP.png": ("bP.png-removebg-preview.png", "bP.png.png"),
    "bR.png": ("bR.png-removebg-preview.png", "bR.png.png"),
    "bN.png": ("bK.png-removebg-preview.png", "bK.png.png"),
    "bB.png": ("bB.png-removebg-preview.png", "bB.png.png"),
    "bQ.png": ("bQ.png-removebg-preview.png", "bQ.png.png"),
    "bK.png": ("bKing.png-removebg-preview.png", "bKing.png.png"),
}

SOURCE_COINS = {
    "white_coin.png": ("wCoin.png-removebg-preview.png", "wCoin.png.png"),
    "black_coin.png": ("bCoin.png-removebg-preview.png", "bCoin.png.png"),
    "red_coin.png": (
        "rCoin.png-removebg-preview.png",
        "rCoin.png.png",
        "ChatGPT Image Mar 4, 2026, 08_21_36 PM.png",
    ),
}

SOURCE_DICE = {
    "dice_1.png": ("D1.png-removebg-preview.png", "D1.png.png"),
    "dice_2.png": ("D2.png-removebg-preview.png", "D2.png.png"),
    "dice_3.png": ("D3.png-removebg-preview.png", "D3.png.png"),
    "dice_4.png": ("D4.png-removebg-preview.png", "D4.png.png"),
    "dice_5.png": ("D5.png-removebg-preview.png", "D5.png.png"),
    "dice_6.png": ("D6.png-removebg-preview.png", "D6.png.png"),
}

SOURCE_RED_CHESS_PIECES = {
    "rP.png": (
        "rP.png-removebg-preview.png",
        "rP.png.png",
        "ChatGPT Image Mar 4, 2026, 08_14_44 PM.png",
    ),
    "rR.png": (
        "rR.png-removebg-preview.png",
        "rR.png.png",
        "ChatGPT Image Mar 4, 2026, 08_16_10 PM.png",
    ),
    "rN.png": ("rK.png-removebg-preview.png", "rK.png.png"),
    "rB.png": ("rB.png-removebg-preview.png", "rB.png.png"),
    "rQ.png": (
        "rQ.png-removebg-preview.png",
        "rQ.png.png",
        "ChatGPT Image Mar 4, 2026, 08_21_34 PM.png",
    ),
    "rK.png": (
        "rKing.png-removebg-preview.png",
        "rKing.png.png",
        "ChatGPT Image Mar 4, 2026, 08_18_12 PM.png",
    ),
}

SOURCE_BACKGAMMON_BOARDS = {
    "backgammon_board_classic.png": ("Backgammonboard.png.png",),
}

OPTIONAL_TIME_BAR_VARIANTS = {
    "HorizontalRedBar.png.png": ("time_bar_horizontal_red.png", (1200, 260)),
    "VerticalGoldBar.png.png": ("time_bar_vertical_gold.png", (260, 1200)),
}


def _sample_average_color(image: Image.Image) -> tuple[int, int, int]:
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    sample_points = [
        (0, 0),
        (width - 1, 0),
        (0, height - 1),
        (width - 1, height - 1),
        (width // 2, 0),
        (width // 2, height - 1),
        (0, height // 2),
        (width - 1, height // 2),
    ]
    total_r = 0
    total_g = 0
    total_b = 0
    for x, y in sample_points:
        r, g, b = pixels[x, y]
        total_r += r
        total_g += g
        total_b += b
    count = len(sample_points)
    return (total_r // count, total_g // count, total_b // count)


def _remove_edge_connected_background(
    image: Image.Image,
    tolerance: int,
    blur_radius: float = 0.75,
) -> Image.Image:
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    bg_r, bg_g, bg_b = _sample_average_color(rgb)
    visited = bytearray(width * height)

    def idx(x: int, y: int) -> int:
        return (y * width) + x

    def in_threshold(x: int, y: int) -> bool:
        r, g, b = pixels[x, y]
        return (
            abs(r - bg_r) <= tolerance
            and abs(g - bg_g) <= tolerance
            and abs(b - bg_b) <= tolerance
        )

    queue: deque[tuple[int, int]] = deque()

    def enqueue(x: int, y: int) -> None:
        flat = idx(x, y)
        if visited[flat]:
            return
        if not in_threshold(x, y):
            return
        visited[flat] = 1
        queue.append((x, y))

    for x in range(width):
        enqueue(x, 0)
        enqueue(x, height - 1)
    for y in range(height):
        enqueue(0, y)
        enqueue(width - 1, y)

    while queue:
        x, y = queue.popleft()
        if x > 0:
            enqueue(x - 1, y)
        if x + 1 < width:
            enqueue(x + 1, y)
        if y > 0:
            enqueue(x, y - 1)
        if y + 1 < height:
            enqueue(x, y + 1)

    alpha = Image.new("L", (width, height), 255)
    alpha_pixels = alpha.load()
    for y in range(height):
        row_offset = y * width
        for x in range(width):
            alpha_pixels[x, y] = 0 if visited[row_offset + x] else 255

    # Slight blur softens cutout edges to avoid jagged outlines after scaling.
    if blur_radius > 0:
        alpha = alpha.filter(ImageFilter.GaussianBlur(radius=blur_radius))

    rgba = rgb.convert("RGBA")
    rgba.putalpha(alpha)
    return rgba


def _trim_transparency(image: Image.Image, alpha_floor: int = 8) -> Image.Image:
    alpha = image.split()[-1]
    bbox = alpha.point(lambda v: 255 if v > alpha_floor else 0).getbbox()
    if bbox is None:
        return image
    return image.crop(bbox)


def _keep_largest_alpha_component(
    image: Image.Image,
    alpha_floor: int = 12,
) -> Image.Image:
    alpha = image.split()[-1]
    width, height = alpha.size
    alpha_pixels = alpha.load()
    visited = bytearray(width * height)

    def idx(x: int, y: int) -> int:
        return (y * width) + x

    largest_component: list[tuple[int, int]] = []

    for y in range(height):
        for x in range(width):
            flat = idx(x, y)
            if visited[flat] or alpha_pixels[x, y] <= alpha_floor:
                continue

            queue: deque[tuple[int, int]] = deque([(x, y)])
            visited[flat] = 1
            component: list[tuple[int, int]] = []

            while queue:
                cx, cy = queue.popleft()
                component.append((cx, cy))
                if cx > 0:
                    left = idx(cx - 1, cy)
                    if not visited[left] and alpha_pixels[cx - 1, cy] > alpha_floor:
                        visited[left] = 1
                        queue.append((cx - 1, cy))
                if cx + 1 < width:
                    right = idx(cx + 1, cy)
                    if not visited[right] and alpha_pixels[cx + 1, cy] > alpha_floor:
                        visited[right] = 1
                        queue.append((cx + 1, cy))
                if cy > 0:
                    up = idx(cx, cy - 1)
                    if not visited[up] and alpha_pixels[cx, cy - 1] > alpha_floor:
                        visited[up] = 1
                        queue.append((cx, cy - 1))
                if cy + 1 < height:
                    down = idx(cx, cy + 1)
                    if not visited[down] and alpha_pixels[cx, cy + 1] > alpha_floor:
                        visited[down] = 1
                        queue.append((cx, cy + 1))

            if len(component) > len(largest_component):
                largest_component = component

    if not largest_component:
        return image

    keep_mask = Image.new("L", (width, height), 0)
    keep_pixels = keep_mask.load()
    for x, y in largest_component:
        keep_pixels[x, y] = alpha_pixels[x, y]

    # Keep anti-aliased edges close to the main body for smooth rendering.
    keep_mask = keep_mask.filter(ImageFilter.GaussianBlur(radius=0.6))

    rgba = image.convert("RGBA")
    rgba.putalpha(keep_mask)
    return rgba


def _resize_to_fit(image: Image.Image, max_width: int, max_height: int) -> Image.Image:
    width, height = image.size
    if width <= max_width and height <= max_height:
        return image
    scale = min(max_width / width, max_height / height)
    new_size = (
        max(1, int(width * scale)),
        max(1, int(height * scale)),
    )
    return image.resize(new_size, Image.Resampling.LANCZOS)


def _compose_piece_canvas(
    piece: Image.Image,
    canvas_size: int = 512,
    fill_ratio: float = 0.88,
    bottom_padding_ratio: float = 0.06,
) -> Image.Image:
    max_extent = int(canvas_size * fill_ratio)
    resized = _resize_to_fit(piece, max_extent, max_extent)
    canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    x = (canvas_size - resized.width) // 2
    y = canvas_size - int(canvas_size * bottom_padding_ratio) - resized.height
    if y < 0:
        y = (canvas_size - resized.height) // 2
    canvas.alpha_composite(resized, (x, y))
    return canvas


def _save_png(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def _detect_black_bbox(
    image: Image.Image,
    threshold: int = 12,
    alpha_threshold: int = 20,
) -> tuple[int, int, int, int]:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    min_x = width
    min_y = height
    max_x = -1
    max_y = -1

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a < alpha_threshold:
                continue
            if r < threshold and g < threshold and b < threshold:
                if x < min_x:
                    min_x = x
                if y < min_y:
                    min_y = y
                if x > max_x:
                    max_x = x
                if y > max_y:
                    max_y = y

    if max_x < min_x or max_y < min_y:
        raise ValueError("Could not detect black-board area for alignment.")

    return (min_x, min_y, max_x, max_y)


def _normalize_board_frame(board_image: Image.Image) -> Image.Image:
    try:
        x0, y0, x1, y1 = _detect_black_bbox(board_image, threshold=12)
    except ValueError:
        alpha_bbox = board_image.split()[-1].getbbox()
        if alpha_bbox is None:
            raise
        x0, y0, x1_exclusive, y1_exclusive = alpha_bbox
        x1 = x1_exclusive - 1
        y1 = y1_exclusive - 1

    black_width = x1 - x0 + 1
    black_height = y1 - y0 + 1

    if black_width <= 0 or black_height <= 0:
        raise ValueError("Invalid board black-area bounds.")

    scale_x = BOARD_PLAYABLE_SIZE / black_width
    scale_y = BOARD_PLAYABLE_SIZE / black_height
    resized = board_image.resize(
        (
            max(1, int(round(board_image.width * scale_x))),
            max(1, int(round(board_image.height * scale_y))),
        ),
        Image.Resampling.LANCZOS,
    )

    # Keep the detected playable area at a deterministic inset for exact runtime mapping.
    offset_x = int(round(BOARD_PLAYABLE_INSET - (x0 * scale_x)))
    offset_y = int(round(BOARD_PLAYABLE_INSET - (y0 * scale_y)))

    canvas = Image.new(
        "RGBA",
        (BOARD_CANVAS_SIZE, BOARD_CANVAS_SIZE),
        (0, 0, 0, 0),
    )
    canvas.paste(resized, (offset_x, offset_y), resized)
    return canvas


def _process_piece(source_name: str, output_name: str) -> None:
    source_path = ASSETS_DIR / source_name
    output_path = PIECES_DIR / output_name
    image = Image.open(source_path)
    cutout = _remove_edge_connected_background(
        image,
        tolerance=PIECE_BG_TOLERANCE,
        blur_radius=PIECE_ALPHA_BLUR_RADIUS,
    )
    main_shape = _keep_largest_alpha_component(cutout, alpha_floor=12)
    trimmed = _trim_transparency(main_shape)
    square_piece = _compose_piece_canvas(trimmed)
    _save_png(output_path, square_piece)
    print(f"piece: {source_name} -> {output_path.relative_to(ROOT)}")


def _process_red_chess_piece(source_name: str, output_name: str) -> None:
    source_path = ASSETS_DIR / source_name
    output_path = PIECES_DIR / output_name
    image = Image.open(source_path)
    cutout = _remove_edge_connected_background(
        image,
        tolerance=16,
        blur_radius=0.35,
    )
    main_shape = _keep_largest_alpha_component(cutout, alpha_floor=10)
    trimmed = _trim_transparency(main_shape)
    square_piece = _compose_piece_canvas(trimmed)
    _save_png(output_path, square_piece)
    print(f"piece: {source_name} -> {output_path.relative_to(ROOT)}")


def _process_coin(source_name: str, output_name: str) -> None:
    source_path = ASSETS_DIR / source_name
    output_path = SHESHBESH_DIR / output_name
    image = Image.open(source_path).convert("RGBA")
    alpha = image.split()[-1]
    alpha_min, alpha_max = alpha.getextrema()

    if alpha_min < alpha_max:
        # Respect authored transparency when present (ruby coin source uses
        # transparent background). This avoids re-cutting and introducing
        # opaque fringe artifacts.
        main_shape = _keep_largest_alpha_component(image, alpha_floor=1)
    else:
        cutout = _remove_edge_connected_background(
            image,
            tolerance=18,
            blur_radius=0.35,
        )
        main_shape = _keep_largest_alpha_component(cutout, alpha_floor=10)
    trimmed = _trim_transparency(main_shape)
    square_piece = _compose_piece_canvas(
        trimmed,
        canvas_size=512,
        fill_ratio=0.82,
        bottom_padding_ratio=0.02,
    )
    _save_png(output_path, square_piece)
    print(f"coin:  {source_name} -> {output_path.relative_to(ROOT)}")


def _process_dice_face(source_name: str, output_name: str) -> None:
    source_path = ASSETS_DIR / source_name
    output_path = SHESHBESH_DIR / output_name
    image = Image.open(source_path).convert("RGBA")
    alpha = image.split()[-1]
    alpha_min, alpha_max = alpha.getextrema()

    if alpha_min < alpha_max:
        # Some source faces (notably D1) include usable alpha but also
        # translucent fringe noise. Use a strong alpha gate and keep only the
        # largest connected component so the final die has clean edges.
        gated_alpha = alpha.point(lambda v: 255 if v > 120 else 0)
        masked = image.copy()
        masked.putalpha(gated_alpha)
        main_shape = _keep_largest_alpha_component(masked, alpha_floor=1)
    else:
        cutout = _remove_edge_connected_background(
            image,
            tolerance=18,
            blur_radius=0.3,
        )
        main_shape = _keep_largest_alpha_component(cutout, alpha_floor=8)
    trimmed = _trim_transparency(main_shape)
    square = _compose_piece_canvas(
        trimmed,
        canvas_size=384,
        fill_ratio=0.9,
        bottom_padding_ratio=0.02,
    )
    _save_png(output_path, square)
    print(f"dice:  {source_name} -> {output_path.relative_to(ROOT)}")


def _normalize_backgammon_board(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    width, height = rgba.size
    if width == height:
        return rgba.resize(
            (BACKGAMMON_BOARD_SIZE, BACKGAMMON_BOARD_SIZE),
            Image.Resampling.LANCZOS,
        )

    # Normalize all skin boards to a square gameplay canvas so point overlays
    # stay aligned regardless of source art aspect ratio.
    if width > height:
        offset = (width - height) // 2
        cropped = rgba.crop((offset, 0, offset + height, height))
    else:
        offset = (height - width) // 2
        cropped = rgba.crop((0, offset, width, offset + width))

    return cropped.resize(
        (BACKGAMMON_BOARD_SIZE, BACKGAMMON_BOARD_SIZE),
        Image.Resampling.LANCZOS,
    )


def _process_backgammon_board(source_name: str, output_name: str) -> None:
    source_path = ASSETS_DIR / source_name
    output_path = SHESHBESH_DIR / output_name
    image = Image.open(source_path)
    normalized = _normalize_backgammon_board(image)
    _save_png(output_path, normalized)
    print(f"bgui:  {source_name} -> {output_path.relative_to(ROOT)}")


def _process_board_image() -> None:
    source_path = ASSETS_DIR / "boardPearl.png.png"
    output_path = UI_DIR / "board.png"
    image = Image.open(source_path)
    cutout = _remove_edge_connected_background(image, tolerance=26)
    trimmed = _trim_transparency(cutout)
    normalized = _normalize_board_frame(trimmed)
    _save_png(output_path, normalized)
    print(f"ui:    boardPearl.png.png -> {output_path.relative_to(ROOT)}")


def _process_ui_image(
    source_name: str,
    output_name: str,
    *,
    tolerance: int,
    max_size: tuple[int, int],
    trim: bool = True,
) -> None:
    source_path = ASSETS_DIR / source_name
    output_path = UI_DIR / output_name
    image = Image.open(source_path)
    cutout = _remove_edge_connected_background(image, tolerance=tolerance)
    processed = _trim_transparency(cutout) if trim else cutout
    resized = _resize_to_fit(processed, max_size[0], max_size[1])
    _save_png(output_path, resized)
    print(f"ui:    {source_name} -> {output_path.relative_to(ROOT)}")


def _ensure_sources_exist(paths: Iterable[Path]) -> None:
    missing = [path for path in paths if not path.exists()]
    if missing:
        missing_list = "\n".join(f"- {path.relative_to(ROOT)}" for path in missing)
        raise FileNotFoundError(f"Missing required source assets:\n{missing_list}")


def _resolve_source_name(*, label: str, candidates: Iterable[str]) -> str:
    for source_name in candidates:
        if (ASSETS_DIR / source_name).exists():
            return source_name

    candidate_list = "\n".join(f"- assets/{name}" for name in candidates)
    raise FileNotFoundError(
        f"Missing source asset for {label}. Tried:\n{candidate_list}"
    )


def main() -> None:
    required_paths = [
        ASSETS_DIR / "boardPearl.png.png",
        ASSETS_DIR / "HorizontalTimeBar.png.png",
        ASSETS_DIR / "VerticalTimeBar.png.png",
        ASSETS_DIR / "PearlBG.png.png",
    ]
    _ensure_sources_exist(required_paths)

    for output_name, candidates in SOURCE_PIECES.items():
        source_name = _resolve_source_name(label=output_name, candidates=candidates)
        _process_piece(source_name, output_name)

    for output_name, candidates in SOURCE_RED_CHESS_PIECES.items():
        source_name = _resolve_source_name(label=output_name, candidates=candidates)
        _process_red_chess_piece(source_name, output_name)

    for output_name, candidates in SOURCE_COINS.items():
        source_name = _resolve_source_name(label=output_name, candidates=candidates)
        _process_coin(source_name, output_name)

    for output_name, candidates in SOURCE_DICE.items():
        source_name = _resolve_source_name(label=output_name, candidates=candidates)
        _process_dice_face(source_name, output_name)

    for output_name, candidates in SOURCE_BACKGAMMON_BOARDS.items():
        source_name = _resolve_source_name(label=output_name, candidates=candidates)
        _process_backgammon_board(source_name, output_name)

    _process_board_image()
    _process_ui_image(
        "HorizontalTimeBar.png.png",
        "time_bar_horizontal.png",
        tolerance=24,
        max_size=(1200, 260),
    )
    _process_ui_image(
        "VerticalTimeBar.png.png",
        "time_bar_vertical.png",
        tolerance=24,
        max_size=(260, 1200),
    )
    for source_name, (output_name, max_size) in OPTIONAL_TIME_BAR_VARIANTS.items():
        source_path = ASSETS_DIR / source_name
        if not source_path.exists():
            print(f"skip:  optional {source_name} not found")
            continue
        _process_ui_image(
            source_name,
            output_name,
            tolerance=24,
            max_size=max_size,
        )
    _process_ui_image(
        "PearlBG.png.png",
        "background.png",
        tolerance=24,
        max_size=(1600, 1200),
        trim=False,
    )

    print("done: generated visual assets under assets/generated/")
    print(
        "board playable rect: "
        f"inset={BOARD_PLAYABLE_INSET}px, size={BOARD_PLAYABLE_SIZE}px"
    )


if __name__ == "__main__":
    main()
