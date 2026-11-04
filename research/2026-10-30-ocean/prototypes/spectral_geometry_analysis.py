#!/usr/bin/env python3
"""Reproduce source-derived ocean workload counts and mathematical error bounds.

This is CPU analysis, not a GPU benchmark or rendered-quality validation.
Source: GodlyDonuts/web-ocean, commit 8739f0793f84b96cb87a21558a117e1714184ad7.
Uses Python's standard library only. No network or GPU is required.

Run:
    python spectral_geometry_analysis.py --output ../results/spectral_geometry.json
"""

import argparse
import json
import math
from pathlib import Path
import struct


N = 256
PATCH_LENGTHS = [1103.0, 211.3, 39.7, 7.43, 1.393, 0.2617]
SOURCE_COMMIT = "8739f0793f84b96cb87a21558a117e1714184ad7"


def f32(x):
    """Match assignment to a JavaScript Float32Array."""
    return struct.unpack("f", struct.pack("f", x))[0]


def band_analysis():
    """Apply main.js:427-434 and sim.js:107-113 to signed FFT coordinates.

    Frequencies use continuous omega; source quantizes DOWN to multiples of
    2*pi/600. Continuous omega is therefore a slightly conservative bound.
    Gaussian coefficients, directional gains, and short-wave damping can make
    occupied bins carry little energy; occupied count is not an energy measure.
    """
    result = []
    for c, length in enumerate(PATCH_LENGTHS):
        lower_bin = 0.5 if c == 0 else 6.0
        upper_bin = (
            6 * length / PATCH_LENGTHS[c + 1]
            if c < len(PATCH_LENGTHS) - 1
            else 0.98 * N / 2
        )
        bins = [
            (x, y)
            for y in range(-N // 2, N // 2)
            for x in range(-N // 2, N // 2)
            if lower_bin <= math.hypot(x, y) < upper_bin
        ]
        kmax = 2 * math.pi * upper_bin / length
        fmax = math.sqrt(9.81 * kmax + 7.4e-5 * kmax**3) / (2 * math.pi)
        result.append({
            "cascade": c,
            "patch_length_m": length,
            "min_radial_bin": lower_bin,
            "exclusive_max_radial_bin": upper_bin,
            "max_integer_axis_bin_present": max(max(abs(x), abs(y)) for x, y in bins),
            "occupied_frequency_positions": len(bins),
            "occupied_fraction": len(bins) / N**2,
            "minimum_wavelength_bound_m": 2 * math.pi / kmax,
            "max_continuous_frequency_bound_hz": fmax,
            "nyquist_rate_bound_hz": 2 * fmax,
            # Linear interpolation at the midpoint of a sinusoid attenuates
            # its cosine component by cos(pi*f/fs).
            "linear_midpoint_two_percent_rate_hz": math.pi * fmax / math.acos(0.98),
            # Hermite remainder: |error|/A <= omega^4*dt^4/384.
            # This is an absolute error relative to a mode's amplitude, not
            # relative error against its value near zero crossings.
            "hermite_two_percent_remainder_bound_rate_hz": (
                math.pi * fmax / (24 * 0.02) ** 0.25
            ),
        })
    return result


def temporal_examples(bands):
    examples = []
    for band, rate in zip(bands[:3], [1.0, 2.0, 5.0]):
        freq = band["max_continuous_frequency_bound_hz"]
        x = math.pi * freq / rate
        examples.append({
            "cascade": band["cascade"],
            "candidate_endpoint_rate_hz": rate,
            "linear_midpoint_mode_amplitude_error": 1 - math.cos(x),
            "exact_derivative_hermite_midpoint_mode_amplitude_error": (
                1 - math.cos(x) - 0.5 * x * math.sin(x)
            ),
            "hermite_uniform_absolute_error_bound_over_mode_amplitude": x**4 / 24,
        })
    return {
        "examples": examples,
        "baseline_first_three_cascade_updates_per_second_at_30fps": 90,
        "candidate_first_three_transform_equivalent_updates_per_second": 16,
        "assumptions": [
            "Endpoint fields and their exact temporal derivatives are both transformed.",
            "Computing temporal derivatives doubles transforms per endpoint update.",
            "Future wave states are analytic; no presentation delay is necessary.",
            "Nonlinear moments, Jacobians, shading, and foam need separate treatment.",
            "Bounds are per harmonic amplitude, not rendered-image error bounds.",
            "No GPU time, interpolation memory cost, or power saving was measured.",
        ],
    }


def derivative_analysis():
    """Centered derivative-stencil response to a pure mode at bin32.

    First five bands have max axis frequency32; last band does not satisfy
    this condition. A 6th-order stencil has a 3-texel halo on each side.
    Values omit texture quantization, filtering, and nonlinear shading error.
    """
    result = []
    for grid in [128, 256]:
        theta = 2 * math.pi * 32 / grid
        response = {
            "second_order": math.sin(theta) / theta,
            "fourth_order": (8 * math.sin(theta) - math.sin(2 * theta)) / (6 * theta),
            "sixth_order": (
                45 * math.sin(theta) - 9 * math.sin(2 * theta) + math.sin(3 * theta)
            ) / (30 * theta),
        }
        result.append({
            "grid_size": grid,
            "axis_frequency_bin": 32,
            "response_relative_to_exact_spectral_derivative": response,
            "amplitude_loss": {key: 1 - value for key, value in response.items()},
        })
    return result


def traffic_analysis():
    coefficients = 6 * N * N
    # Evolve: h0 read16 + spec writes32. Rows: spec reads32 + tmp writes32.
    # Columns: tmp reads32 + three RGBA16F textures written24.
    before = 16 + 32 + 32 + 32 + 32 + 24
    after = 16 + 32 + 32 + 24
    return {
        "coefficient_count": coefficients,
        "current_explicit_bytes_per_coefficient_evolve_rows_columns": before,
        "fused_evolve_rows_explicit_bytes_per_coefficient": after,
        "current_explicit_bytes_per_frame": coefficients * before,
        "fused_explicit_bytes_per_frame": coefficients * after,
        "removed_explicit_bytes_per_frame": coefficients * (before - after),
        "removed_spec_buffer_allocation_bytes": 2 * coefficients * 16,
        "twiddle_sincos_pairs_source_loop_iterations_per_frame": 2 * 6 * N * (N // 2) * 8,
        "mixed_5x128_1x256_fft_operation_model_fraction": (
            (5 * 128**2 * 7 + 256**2 * 8) / (6 * 256**2 * 8)
        ),
        "warnings": [
            "Explicit load/store accounting is not measured DRAM traffic.",
            "Caches, shared memory, compiler lowering, and synchronization are excluded.",
            "The source already packs eight real fields into four complex IFFTs.",
            "The column pass already fuses final texture assembly.",
            "Mixed grid sizes preserve frequency support, not identical interpolation.",
        ],
    }


def mat4_mul_column_major(a, b):
    """Match main.js:56-64, with Float32Array assignment rounding."""
    out = [0.0] * 16
    for c in range(4):
        b0, b1, b2, b3 = b[c * 4:c * 4 + 4]
        for row in range(4):
            out[c * 4 + row] = f32(
                a[row] * b0 + a[4 + row] * b1 + a[8 + row] * b2 + a[12 + row] * b3
            )
    return out


def cdlod_count(aspect=16 / 9):
    """CPU reproduction of main.js selectAll/selectNode, default camera.

    Counts submitted triangles before GPU clipping/rasterization, not fragments,
    visible triangles, hardware vertex-shader invocations, or GPU runtime.
    """
    cx, cy, cz = 0.0, 2.4, 0.0
    yaw, pitch, fov = 0.0, math.radians(-5.5), math.radians(58)
    c_yaw, s_yaw = math.cos(yaw), math.sin(yaw)
    c_pitch, s_pitch = math.cos(pitch), math.sin(pitch)
    fx, fy, fz = c_pitch * s_yaw, s_pitch, -c_pitch * c_yaw
    rx, ry, rz = c_yaw, 0.0, s_yaw
    ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
    proj = [0.0] * 16
    proj[0], proj[5], proj[11], proj[14] = (
        f32(1 / (math.tan(fov / 2) * aspect)),
        f32(1 / math.tan(fov / 2)), -1.0, f32(0.05)
    )
    view = [0.0] * 16
    view[0], view[4], view[8] = map(f32, [rx, ry, rz])
    view[1], view[5], view[9] = map(f32, [ux, uy, uz])
    view[2], view[6], view[10] = map(f32, [-fx, -fy, -fz])
    view[15] = 1.0
    matrix = mat4_mul_column_major(proj, view)
    planes = []
    for i in range(4):
        row, sign = i >> 1, -1 if i & 1 else 1
        planes.append([matrix[3 + k * 4] + sign * matrix[row + k * 4] for k in range(4)])
    ranges = [16.0 * 2**level for level in range(17)]
    nodes = []

    def sphere_hit(x, z, size, radius):
        dx = max(x - cx, 0, cx - (x + size))
        dz = max(z - cz, 0, cz - (z + size))
        dy = max(-4.0 - cy, 0, cy - 4.0)
        return dx * dx + dy * dy + dz * dz <= radius * radius

    def in_frustum(x, z, size):
        minima = [x - 4 - cx, -4 - cy, z - 4 - cz]
        maxima = [x + size + 4 - cx, 4 - cy, z + size + 4 - cz]
        for plane in planes:
            xyz = [maxima[i] if plane[i] > 0 else minima[i] for i in range(3)]
            if sum(plane[i] * xyz[i] for i in range(3)) + plane[3] < 0:
                return False
        return True

    def add_node(level):
        if len(nodes) < 8192:
            nodes.append(level)

    def select_node(x, z, size, level):
        if not sphere_hit(x, z, size, ranges[level]):
            return False
        if not sphere_hit(x, z, size, 160000) or not in_frustum(x, z, size):
            return True
        if level == 0 or not sphere_hit(x, z, size, ranges[level - 1]):
            add_node(level)
            return True
        half = size / 2
        for i in range(4):
            nx, nz = x + (i & 1) * half, z + (i >> 1) * half
            if not select_node(nx, nz, half, level - 1):
                if sphere_hit(nx, nz, half, 160000) and in_frustum(nx, nz, half):
                    add_node(level - 1)
        return True

    top_size = 2.0 * 2**16
    for zi in range(math.floor((cz - 160000) / top_size), math.floor((cz + 160000) / top_size) + 1):
        for xi in range(math.floor((cx - 160000) / top_size), math.floor((cx + 160000) / top_size) + 1):
            select_node(xi * top_size, zi * top_size, top_size, 16)
    return {
        "camera": {"position_m": [cx, cy, cz], "yaw_deg": 0, "pitch_deg": -5.5, "fovy_deg": 58},
        "aspect": aspect,
        "selected_nodes": len(nodes),
        "nodes_by_lod": {str(level): nodes.count(level) for level in range(17)},
        "submitted_triangles": len(nodes) * 32 * 32 * 2,
        "sum_of_unique_vertex_indices_per_instance": len(nodes) * 33 * 33,
    }


def projected_grid_candidates(baseline_triangles):
    result = []
    for cell in [4, 8]:
        cells_x, cells_y = math.ceil(2560 / cell), math.ceil(1440 / cell)
        triangles = 2 * cells_x * cells_y
        result.append({
            "viewport": [2560, 1440],
            "nominal_screen_cell_px": cell,
            "full_viewport_grid_cells": [cells_x, cells_y],
            "triangles_before_refinement": triangles,
            "baseline_to_candidate_triangle_ratio": baseline_triangles / triangles,
        })
    return {
        "candidates": result,
        "warnings": [
            "These are geometry budgets, not quality-equivalent implementations.",
            "A full-screen grid includes sky area unless clipped to the ocean domain.",
            "Projected grid vertices have to cover displaced water, including horizon crests.",
            "Near/horizon silhouettes and large waves require adaptive refinement/guard bands.",
            "Fixing the camera does not freeze displaced screen coordinates or their Jacobian.",
            "A proposed acceptance target is sub-0.25-pixel silhouette/displacement error.",
            "Triangle ratio is not a GPU speedup prediction.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    bands = band_analysis()
    geometry = [cdlod_count(16 / 9), cdlod_count(16 / 10)]
    output = {
        "source_commit": SOURCE_COMMIT,
        "classification": "CPU reproduction and analytic workload/error models; no GPU measurements",
        "band_analysis": bands,
        "all_bands_occupied_fraction": sum(b["occupied_frequency_positions"] for b in bands) / (6 * N * N),
        "temporal_interpolation": temporal_examples(bands),
        "derivative_stencils": derivative_analysis(),
        "fft_data_movement": traffic_analysis(),
        "cdlod_reproduction": geometry,
        "projected_grid_candidates": projected_grid_candidates(geometry[0]["submitted_triangles"]),
        "source_locations": {
            "bands_and_lengths": "js/main.js:39,427-434; js/wgsl/sim.js:107-113",
            "dispersion": "js/wgsl/sim.js:8-9,29,146-149",
            "packed_fields": "js/wgsl/sim.js:156-164,168-252",
            "buffers_and_dispatch": "js/main.js:104-121,658-685",
            "cdlod": "js/main.js:309-330,445,488-600,783",
        },
    }
    rendered = json.dumps(output, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
        print(f"Wrote CPU analysis to {args.output}")
        print(f"16:9 nodes={geometry[0]['selected_nodes']}, triangles={geometry[0]['submitted_triangles']}")
        print(f"Explicit bytes/frame saved by evolve-row fusion={output['fft_data_movement']['removed_explicit_bytes_per_frame']}")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()
