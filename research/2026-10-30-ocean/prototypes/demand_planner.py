"""CPU reference for conservative wallpaper demand planning.

This does not discover macOS window opacity and is not a GPU benchmark.
OpaqueRegion inputs must already be justified by the caller; window alpha=1
is NOT sufficient. The bloom pullback models the source shader's sample
locations and bilinear support, without evaluating its radiance values.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Iterable

import numpy as np


@dataclass(frozen=True)
class Rect:
    x0: float
    y0: float
    x1: float
    y1: float

    @property
    def area(self) -> float:
        return max(0.0, self.x1 - self.x0) * max(0.0, self.y1 - self.y0)

    def clip(self, other: "Rect") -> "Rect":
        return Rect(max(self.x0, other.x0), max(self.y0, other.y0),
                    min(self.x1, other.x1), min(self.y1, other.y1))

    def erode(self, amount: float) -> "Rect":
        return Rect(self.x0 + amount, self.y0 + amount,
                    self.x1 - amount, self.y1 - amount)


@dataclass(frozen=True)
class OpaqueRegion:
    rect: Rect
    confirmed_opaque: bool = False
    moving: bool = False
    age_seconds: float = 0.0


def union_area(rects: Iterable[Rect], clip: Rect) -> float:
    """Exact union area by an x sweep, suitable as an independent reference."""
    rs = [r.clip(clip) for r in rects]
    rs = [r for r in rs if r.area > 0]
    xs = sorted({x for r in rs for x in (r.x0, r.x1)})
    area = 0.0
    for a, b in zip(xs, xs[1:]):
        spans = sorted((r.y0, r.y1) for r in rs if r.x0 < b and r.x1 > a)
        if not spans:
            continue
        lo, hi = spans[0]
        total_y = 0.0
        for s, e in spans[1:]:
            if s > hi:
                total_y += hi - lo
                lo, hi = s, e
            else:
                hi = max(hi, e)
        total_y += hi - lo
        area += (b - a) * total_y
    return area


def visible_tiles(width: int, height: int, tile: int,
                  regions: Iterable[OpaqueRegion], *, safety_margin: float = 0,
                  max_age: float = 0.25, fully_occluded: bool = False) -> np.ndarray:
    """Only skip tiles wholly covered by a union of trusted opaque regions.

    A margin is a geometric guard, not proof of opacity. Unknown, moving or
    stale regions are ignored. fully_occluded must come from an authoritative
    whole-surface signal. Coordinates are render pixels, origin top-left.
    """
    if width <= 0 or height <= 0 or tile <= 0:
        raise ValueError("positive dimensions and tile size required")
    out = np.ones((math.ceil(height / tile), math.ceil(width / tile)), dtype=bool)
    if fully_occluded:
        out[:] = False
        return out
    trusted = [r.rect.erode(safety_margin) for r in regions
               if r.confirmed_opaque and not r.moving
               and 0 <= r.age_seconds <= max_age]
    for y in range(out.shape[0]):
        for x in range(out.shape[1]):
            box = Rect(x * tile, y * tile, min(width, (x + 1) * tile),
                       min(height, (y + 1) * tile))
            out[y, x] = union_area(trusted, box) < box.area - 1e-9
    return out


def tile_pixels(mask: np.ndarray, tile: int, width: int, height: int) -> np.ndarray:
    return np.repeat(np.repeat(mask, tile, axis=0), tile, axis=1)[:height, :width]


def merge_tiles(mask: np.ndarray, tile: int, width: int, height: int) -> list[Rect]:
    """Merge equal horizontal runs over adjacent rows into disjoint scissors."""
    active: dict[tuple[int, int], tuple[int, int]] = {}
    completed: list[tuple[int, int, int, int]] = []
    for y in range(mask.shape[0] + 1):
        row = mask[y] if y < mask.shape[0] else np.zeros(mask.shape[1], dtype=bool)
        edges = np.diff(np.r_[False, row, False].astype(np.int8))
        runs = list(zip(np.where(edges == 1)[0], np.where(edges == -1)[0]))
        present = set(runs)
        for run in list(active):
            if run not in present:
                start, end = active.pop(run)
                completed.append((run[0], start, run[1], end))
        for run in runs:
            active[run] = (active.get(run, (y, y))[0], y + 1)
    return [Rect(x0 * tile, y0 * tile, min(x1 * tile, width), min(y1 * tile, height))
            for x0, y0, x1, y1 in completed]


DOWN_OFFSETS = tuple((x, y) for y in (-2, 0, 2) for x in (-2, 0, 2)) + (
    (-1, -1), (1, -1), (-1, 1), (1, 1))
UP_OFFSETS = tuple((x, y) for y in (-1, 0, 1) for x in (-1, 0, 1))


def pullback_samples(destination: np.ndarray, source_shape: tuple[int, int],
                     offsets: tuple[tuple[int, int], ...]) -> np.ndarray:
    """Pull demanded output texels through normalized-UV bilinear samples.

    Includes all four bilinear neighbors, including zero-weight neighbors at
    exact integer coordinates; therefore deliberately conservative. Clamp-to-
    edge addressing matches bloom's sampler. Supports non-power-of-two sizes.
    """
    sh, sw = source_shape
    dh, dw = destination.shape
    result = np.zeros((sh, sw), dtype=bool)
    yy, xx = np.nonzero(destination)
    if not len(xx):
        return result
    x = (xx + 0.5) * sw / dw - 0.5
    y = (yy + 0.5) * sh / dh - 0.5
    for ox, oy in offsets:
        bx = np.floor(x + ox).astype(np.int64)
        by = np.floor(y + oy).astype(np.int64)
        for sy in (0, 1):
            iy = np.clip(by + sy, 0, sh - 1)
            for sx in (0, 1):
                ix = np.clip(bx + sx, 0, sw - 1)
                result[iy, ix] = True
    return result


def bloom_demand(visible: np.ndarray, levels: int = 8, base_divisor: int = 2) -> dict:
    """Backward dependency masks for downsample/additive-upsample bloom.

    The source has 13-tap downsamples and 9-tap upsamples. Each upsample output
    also consumes that level's original downsample through additive blending.
    This planner does not assume hidden HDR can be omitted from bloom.
    """
    if levels < 1 or base_divisor < 1:
        raise ValueError("invalid bloom configuration")
    h, w = visible.shape
    bh, bw = max(1, h // base_divisor), max(1, w // base_divisor)
    shapes = [(max(1, bh >> i), max(1, bw >> i)) for i in range(levels)]
    final_masks = [np.zeros(shape, dtype=bool) for shape in shapes]
    final_masks[0] = pullback_samples(visible, shapes[0], ((0, 0),))
    down_masks = [np.zeros(shape, dtype=bool) for shape in shapes]
    for i in range(levels):
        down_masks[i] |= final_masks[i]
        if i + 1 < levels:
            final_masks[i + 1] |= pullback_samples(final_masks[i], shapes[i + 1], UP_OFFSETS)
    hdr_for_bloom = np.zeros_like(visible)
    for i in range(levels - 1, -1, -1):
        src_shape = visible.shape if i == 0 else shapes[i - 1]
        required = pullback_samples(down_masks[i], src_shape, DOWN_OFFSETS)
        if i == 0:
            hdr_for_bloom |= required
        else:
            down_masks[i - 1] |= required
    return {"hdr": visible | hdr_for_bloom, "bloom_source": hdr_for_bloom,
            "down": down_masks, "up": final_masks}


def spectrum_blend(power0: np.ndarray, power1: np.ndarray, amount: float,
                   random_complex: np.ndarray) -> np.ndarray:
    """Stable phase identity with interpolated spectral energy."""
    a = np.clip(amount, 0.0, 1.0)
    power = (1 - a) * np.maximum(power0, 0) + a * np.maximum(power1, 0)
    return random_complex * np.sqrt(power)


def solar_direction(azimuth_degrees: float, altitude_degrees: float) -> np.ndarray:
    """Azimuth clockwise from north; world +X east,+Y up,-Z north.

    This converts angles; it does not implement a solar ephemeris.
    """
    a, h = np.deg2rad([azimuth_degrees, altitude_degrees])
    return np.array([math.cos(h) * math.sin(a), math.sin(h), -math.cos(h) * math.cos(a)])


def wave_from_azimuth(azimuth_degrees: float) -> float:
    return (azimuth_degrees + 90.0) % 360.0


def hermite(y0: np.ndarray, v0: np.ndarray, y1: np.ndarray, v1: np.ndarray,
            interval: float, u: float) -> np.ndarray:
    return ((2*u**3 - 3*u**2 + 1)*y0 + (u**3 - 2*u**2 + u)*interval*v0
            + (-2*u**3 + 3*u**2)*y1 + (u**3 - u**2)*interval*v1)


def harmonic_interpolation_error(frequency: float, update_rate: float,
                                 phases: int = 128, samples: int = 129) -> dict:
    """Worst absolute unit-amplitude error over phase and interval, not GPU data."""
    omega = 2 * math.pi * frequency
    dt = 1 / update_rate
    phase = np.linspace(0, 2 * math.pi, phases, endpoint=False)
    y0 = np.cos(phase)
    y1 = np.cos(phase + omega * dt)
    v0 = -omega * np.sin(phase)
    v1 = -omega * np.sin(phase + omega * dt)
    lin_error = cub_error = 0.0
    for u in np.linspace(0, 1, samples):
        truth = np.cos(phase + omega * dt * u)
        lin = (1-u)*y0 + u*y1
        cub = hermite(y0, v0, y1, v1, dt, u)
        lin_error = max(lin_error, float(np.max(np.abs(lin-truth))))
        cub_error = max(cub_error, float(np.max(np.abs(cub-truth))))
    return {"frequency_hz": frequency, "update_hz": update_rate,
            "linear_max_abs_error": lin_error, "hermite_max_abs_error": cub_error}


def derivative_response(bin_fraction: float, order: int = 4) -> float:
    """Centered finite-difference derivative amplitude / spectral derivative."""
    x = 2 * math.pi * bin_fraction
    if x == 0:
        return 1.0
    if order == 4:
        return (8 * math.sin(x) - math.sin(2*x)) / (6*x)
    if order == 6:
        return (45 * math.sin(x) - 9 * math.sin(2*x) + math.sin(3*x)) / (30*x)
    raise ValueError("order must be 4 or 6")
