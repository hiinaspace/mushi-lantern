#!/usr/bin/env python3
"""Generate grayscale emissive edge masks from foliage or fruit textures.

Examples:
  python tools/generate_edge_emission_mask.py leaf.png leaf_edges.png \
      --mode alpha --width 2
  python tools/generate_edge_emission_mask.py mushroom.png fruit_edges.png \
      --mode color --threshold 0.14 --width 1

Requires Pillow and NumPy (for example, `nix-shell -p python3Packages.pillow
python3Packages.numpy`). White pixels mark emissive edges; black pixels remain
dark. This is an offline texture-preparation tool and does not alter inputs.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image


def erode(mask: np.ndarray, iterations: int, wrap: bool = False) -> np.ndarray:
    """Binary 8-neighbor erosion with transparent pixels beyond the image."""
    result = mask.astype(bool)
    for _ in range(iterations):
        padded = np.pad(result, 1, mode="wrap" if wrap else "constant",
                        **({} if wrap else {"constant_values": False}))
        h, w = result.shape
        result = np.logical_and.reduce(
            [padded[y : y + h, x : x + w] for y in range(3) for x in range(3)]
        )
    return result


def dilate(values: np.ndarray, iterations: int, wrap: bool = False) -> np.ndarray:
    """Max-filter an edge response by the requested number of pixels."""
    result = values.astype(np.float32)
    for _ in range(iterations):
        padded = np.pad(result, 1, mode="wrap" if wrap else "constant",
                        **({} if wrap else {"constant_values": 0.0}))
        h, w = result.shape
        result = np.maximum.reduce(
            [padded[y : y + h, x : x + w] for y in range(3) for x in range(3)]
        )
    return result


def sobel_magnitude(channel: np.ndarray, wrap: bool = False) -> np.ndarray:
    padded = np.pad(channel, 1, mode="wrap" if wrap else "edge")
    h, w = channel.shape
    nw = padded[:-2, :-2]
    n = padded[:-2, 1:-1]
    ne = padded[:-2, 2:]
    wv = padded[1:-1, :-2]
    ev = padded[1:-1, 2:]
    sw = padded[2:, :-2]
    s = padded[2:, 1:-1]
    se = padded[2:, 2:]
    gx = ((ne + 2 * ev + se) - (nw + 2 * wv + sw)) * 0.25
    gy = ((sw + 2 * s + se) - (nw + 2 * n + ne)) * 0.25
    return np.hypot(gx, gy).astype(np.float32)


def make_mask(image: Image.Image, mode: str, threshold: float, width: int,
              alpha_threshold: int, wrap: bool = False) -> np.ndarray:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255.0
    if mode == "alpha":
        alpha = rgba[:, :, 3]
        silhouette = alpha >= alpha_threshold / 255.0
        edge = silhouette & ~erode(silhouette, width, wrap)
        # Preserve antialiasing at the outermost texel without making the mask
        # depend on the source RGB values.
        intensity = np.where(edge, np.maximum(alpha, 0.55), 0.0)
    else:
        rgb = rgba[:, :, :3]
        if mode == "brightness":
            channel = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
            magnitude = sobel_magnitude(channel, wrap)
        else:
            magnitude = np.maximum.reduce([sobel_magnitude(rgb[:, :, c], wrap) for c in range(3)])
        # Threshold is an absolute normalized contrast, not an image-specific
        # percentile, so repeated use yields stable edge strength.
        response = np.where(magnitude >= threshold, np.clip(magnitude, 0.0, 1.0), 0.0)
        intensity = dilate(response, width - 1, wrap)
        # Ignore transparent texels in color/brightness modes too.
        intensity *= rgba[:, :, 3]
    return np.clip(intensity * 255.0, 0, 255).astype(np.uint8)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="source texture")
    parser.add_argument("output", type=Path, help="grayscale PNG output")
    parser.add_argument("--mode", choices=("alpha", "color", "brightness"), default="alpha",
                        help="silhouette alpha, RGB contrast, or luminance edges")
    parser.add_argument("--threshold", type=float, default=0.12,
                        help="absolute edge-strength threshold in [0,1] for color/brightness")
    parser.add_argument("--width", type=int, default=1,
                        help="edge thickness in pixels (alpha border width; color dilation width)")
    parser.add_argument("--alpha-threshold", type=int, default=8,
                        help="alpha byte value considered part of silhouette (0..255)")
    parser.add_argument("--wrap", action="store_true",
                        help="treat texture borders as repeating for seam-safe tiled inputs")
    args = parser.parse_args()
    if not 0.0 <= args.threshold <= 1.0:
        parser.error("--threshold must be between 0 and 1")
    if args.width < 1:
        parser.error("--width must be at least 1")
    if not 0 <= args.alpha_threshold <= 255:
        parser.error("--alpha-threshold must be between 0 and 255")
    with Image.open(args.input) as source:
        mask = make_mask(source, args.mode, args.threshold, args.width,
                         args.alpha_threshold, args.wrap)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(mask, mode="L").save(args.output)
    print(f"{args.output}: {mask.shape[1]}x{mask.shape[0]} grayscale, mode={args.mode}, "
          f"width={args.width}, nonzero={(mask > 0).sum()}/{mask.size}")


if __name__ == "__main__":
    main()
