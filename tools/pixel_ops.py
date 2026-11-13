"""Shared pixel-art steps for turning high-res renders into game sprites
(used by tools/pixelize.py and tools/mixamo_move.py)."""
import numpy as np
from PIL import Image, ImageEnhance


def downscale(img: Image.Image, px: int, sat: float = 1.35, contrast: float = 1.12,
              bright: float = 1.0) -> np.ndarray:
    """Majority vote per block: each SxS block of the render becomes one crisp game pixel."""
    a = np.asarray(img.convert("RGBA"))
    s = a.shape[0] // px
    h, w = px, px
    blk = a[:h * s, :w * s].reshape(h, s, w, s, 4).transpose(0, 2, 1, 3, 4).reshape(h * w, s * s, 4)
    alpha = blk[:, :, 3] > 127
    keys = (blk[:, :, 0].astype(np.int64) << 16) | (blk[:, :, 1].astype(np.int64) << 8) | blk[:, :, 2]
    keys = np.where(alpha, keys, -1)
    eq = (keys[:, :, None] == keys[:, None, :]) & alpha[:, None, :]
    counts = eq.sum(-1)
    counts = np.where(alpha, counts, -1)
    best = counts.argmax(1)
    col = blk[np.arange(h * w), best, :3]
    opaque = alpha.sum(1) * 2 >= s * s
    out = np.zeros((h * w, 4), np.uint8)
    rgb = Image.fromarray(col.reshape(h, w, 3).astype(np.uint8), "RGB")
    rgb = ImageEnhance.Color(rgb).enhance(sat)
    rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    out[:, :3] = np.asarray(rgb).reshape(h * w, 3)
    out[:, 3] = np.where(opaque, 255, 0)
    return out.reshape(h, w, 4)


def palette_from_frames(frames, colors: int) -> Image.Image:
    """One median-cut palette for all frames, so colours never flicker between frames."""
    opaque = np.concatenate([f[f[:, :, 3] > 0][:, :3] for f in frames])
    strip = Image.fromarray(opaque.reshape(1, -1, 3).astype(np.uint8), "RGB")
    return strip.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)


def palette_from_image(path: str, skip_darkest: int = 0) -> Image.Image:
    """Palette taken from an existing sprite sheet, so new frames use the same colours
    as hand-made ones. skip_darkest drops the N darkest colours (outline shades)."""
    a = np.asarray(Image.open(path).convert("RGBA"))
    cols = np.unique(a[a[:, :, 3] > 0][:, :3], axis=0)
    if skip_darkest:
        cols = cols[np.argsort(cols.astype(int).sum(1))][skip_darkest:]
    pal = Image.new("P", (1, 1))
    flat = [int(v) for c in cols for v in c]
    pal.putpalette(flat + flat[:3] * (256 - len(cols)))
    return pal


def apply_palette(f: np.ndarray, pal_img: Image.Image) -> np.ndarray:
    rgb = Image.fromarray(f[:, :, :3], "RGB").quantize(palette=pal_img, dither=Image.Dither.NONE).convert("RGB")
    out = f.copy()
    out[:, :, :3] = np.asarray(rgb)
    return out


def despeckle(f: np.ndarray, passes: int = 2) -> np.ndarray:
    """Replaces lone pixels with the colour most of their 8 neighbours share."""
    out = f.copy()
    h, w = f.shape[:2]
    for _ in range(passes):
        key = (out[:, :, 0].astype(np.int64) << 16) | (out[:, :, 1].astype(np.int64) << 8) | out[:, :, 2]
        key = np.where(out[:, :, 3] > 0, key, -1)
        pad = np.pad(key, 1, constant_values=-2)
        neigh = np.stack([pad[1 + dy:h + 1 + dy, 1 + dx:w + 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx], -1)
        same = (neigh == key[:, :, None]).sum(-1)
        counts = (neigh[:, :, :, None] == neigh[:, :, None, :]).sum(-1)
        best = np.take_along_axis(neigh, counts.argmax(-1)[:, :, None], -1)[:, :, 0]
        bestc = counts.max(-1)
        fix = (same <= 1) & (bestc >= 4) & (key >= 0) & (best >= 0)
        out[fix, 0] = (best[fix] >> 16) & 255
        out[fix, 1] = (best[fix] >> 8) & 255
        out[fix, 2] = best[fix] & 255
    return out


def add_outline(f: np.ndarray, color) -> np.ndarray:
    a = f[:, :, 3] > 0
    n = np.zeros_like(a)
    n[1:, :] |= a[:-1, :]
    n[:-1, :] |= a[1:, :]
    n[:, 1:] |= a[:, :-1]
    n[:, :-1] |= a[:, 1:]
    edge = n & ~a
    out = f.copy()
    out[edge, :3] = color
    out[edge, 3] = 255
    return out
