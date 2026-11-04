#!/usr/bin/env python3
"""CPU-only equation/index check for fused_evolve_rows.wgsl.

Does not compile or execute WGSL, model GPU FP32 rounding, prove GPU race
freedom, or measure performance. Python float/complex use binary64 here.
Checks a tuple implementation of the source producer against independent
complex-number equations, row ownership, and the FFT against a direct DFT.
"""

import argparse
import cmath
import json
import math
from pathlib import Path
import random


N = 256
LOGN = 8
PI = 3.14159265358979
LENGTHS = [1103.0, 211.3, 39.7, 7.43, 1.393, 0.2617]


def cmul(a, b):
    return (a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0])


def mul_i(a):
    return (-a[1], a[0])


def plus(a, b):
    return (a[0] + b[0], a[1] + b[1])


def scale(a, scalar):
    return (a[0] * scalar, a[1] * scalar)


def parameters(x, y, cascade, time):
    nx, ny = (x if x < N // 2 else x - N), (y if y < N // 2 else y - N)
    kx, ky = nx * (2 * PI / LENGTHS[cascade]), ny * (2 * PI / LENGTHS[cascade])
    kl = math.sqrt(kx * kx + ky * ky)
    w0 = 2 * PI / 600.0
    omega = math.sqrt(9.81 * kl + 7.4e-5 * kl * kl * kl)
    phase = math.floor(omega / w0) * w0 * time
    return kx, ky, kl, phase


def source_tuple_producer(h0, x, y, cascade, time, choppiness):
    """Tuple expression of the unchanged source producer equations."""
    kx, ky, kl, phase = parameters(x, y, cascade, time)
    if kl < 1e-5:
        return [0j, 0j, 0j, 0j]
    e = (math.cos(phase), math.sin(phase))
    h = plus(cmul(h0[:2], (e[0], -e[1])), cmul(h0[2:], e))
    ih = mul_i(h)
    invk = 1.0 / kl
    dx = scale(ih, choppiness * kx * invk)
    dz = scale(ih, choppiness * ky * invk)
    jxz = scale(h, -choppiness * kx * ky * invk)
    sx, sz = scale(ih, kx), scale(ih, ky)
    jxx = scale(h, -choppiness * kx * kx * invk)
    jzz = scale(h, -choppiness * ky * ky * invk)
    return [complex(*a) for a in [
        plus(dx, mul_i(dz)), plus(h, mul_i(jxz)),
        plus(sx, mul_i(sz)), plus(jxx, mul_i(jzz)),
    ]]


def independent_complex_producer(h0, x, y, cascade, time, choppiness):
    """Independent complex equations for the packed fields."""
    kx, ky, kl, phase = parameters(x, y, cascade, time)
    if kl < 1e-5:
        return [0j, 0j, 0j, 0j]
    h = complex(*h0[:2]) * cmath.exp(-1j * phase) + complex(*h0[2:]) * cmath.exp(1j * phase)
    dx, dz = 1j * h * (choppiness * kx / kl), 1j * h * (choppiness * ky / kl)
    jxz = -choppiness * kx * ky / kl * h
    sx, sz = 1j * kx * h, 1j * ky * h
    jxx, jzz = -choppiness * kx * kx / kl * h, -choppiness * ky * ky / kl * h
    return [dx + 1j * dz, h + 1j * jxz, sx + 1j * sz, jxx + 1j * jzz]


def bitrev(value):
    return int(f"{value:0{LOGN}b}"[::-1], 2)


def row_butterflies(workgroup):
    """Source row FFT schedule, with a stage snapshot for barrier semantics."""
    values = [row[:] for row in workgroup]
    for stage in range(LOGN):
        half = 1 << stage
        previous = [row[:] for row in values]
        for thread in range(N // 2):
            pos = thread & (half - 1)
            i0 = ((thread >> stage) << (stage + 1)) + pos
            i1 = i0 + half
            w = complex(math.cos(PI * pos / half), math.sin(PI * pos / half))
            for field in range(4):
                product = previous[i1][field] * w
                values[i0][field] = previous[i0][field] + product
                values[i1][field] = previous[i0][field] - product
    return values


def direct_inverse_dft(spectrum):
    """Unnormalized inverse DFT; source likewise applies no 1/N scaling."""
    output = []
    for j in range(N):
        fields = [0j] * 4
        for x in range(N):
            w = cmath.exp(2j * PI * x * j / N)
            for field in range(4):
                fields[field] += spectrum[x][field] * w
        output.append(fields)
    return output


def error_metrics(a, b):
    numerator, denominator, max_abs = 0.0, 0.0, 0.0
    for ar, br in zip(a, b):
        for av, bv in zip(ar, br):
            delta = abs(av - bv)
            numerator += delta * delta
            denominator += abs(bv) ** 2
            max_abs = max(max_abs, delta)
    return {"max_absolute_error": max_abs, "relative_l2_error": math.sqrt(numerator / max(denominator, 1e-300))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    rng = random.Random(8739)
    cases = []
    worst_equation = 0.0
    worst_row = 0.0
    indexed_positions = 0
    # Includes DC rows, signed-frequency boundaries, highest-frequency band,
    # zero/normal/max UI choppiness, and a time immediately before the loop.
    for cascade, y, time, choppiness in [
        (0, 0, 0.0, 0.0), (0, 7, 0.123, 1.25),
        (1, 128, 17.3, 1.6), (2, 255, 599.999, 1.25),
        (3, 7, 0.123, 1.25), (4, 0, 0.0, 1.6),
        (5, 128, 17.3, 1.25), (5, 255, 599.999, 1.6),
    ]:
        row_h0 = [[rng.uniform(-1, 1) for _ in range(4)] for _ in range(N)]
        for x in range(0, N, 13):
            row_h0[x] = [0.0] * 4
        source = [source_tuple_producer(row_h0[x], x, y, cascade, time, choppiness) for x in range(N)]
        independent = [independent_complex_producer(row_h0[x], x, y, cascade, time, choppiness) for x in range(N)]
        equation_error = error_metrics(source, independent)
        # Split execution loads the materialized producer output in bit-reverse order.
        split = [[0j] * 4 for _ in range(N)]
        for x in range(N):
            split[bitrev(x)] = source[x][:]
        # Fused execution uses exactly the candidate's two positions per thread.
        fused = [[0j] * 4 for _ in range(N)]
        owners = [0] * N
        addresses = []
        for thread in range(N // 2):
            for x in [thread, thread + N // 2]:
                owners[x] += 1
                fused[bitrev(x)] = source_tuple_producer(row_h0[x], x, y, cascade, time, choppiness)
                addresses.append((cascade * N + y) * N + x)
        assert owners == [1] * N, "Every row position must have exactly one owner"
        base = (cascade * N + y) * N
        assert sorted(addresses) == list(range(base, base + N)), "Output addresses must preserve row layout"
        indexed_positions += N
        row_error = error_metrics(row_butterflies(fused), row_butterflies(split))
        worst_equation = max(worst_equation, equation_error["relative_l2_error"])
        worst_row = max(worst_row, row_error["relative_l2_error"])
        cases.append({
            "cascade": cascade, "row": y, "time_s": time, "choppiness": choppiness,
            "producer_equation_comparison": equation_error,
            "fused_vs_split_cpu_row_comparison": row_error,
        })
    # Use an arbitrary complex row so this checks the FFT itself separately
    # from the physical spectrum and the source producer.
    arbitrary = [[complex(rng.uniform(-1, 1), rng.uniform(-1, 1)) for _ in range(4)] for _ in range(N)]
    workgroup = [[0j] * 4 for _ in range(N)]
    for x in range(N):
        workgroup[bitrev(x)] = arbitrary[x][:]
    dft_error = error_metrics(row_butterflies(workgroup), direct_inverse_dft(arbitrary))
    passed = worst_equation < 1e-12 and worst_row == 0 and dft_error["relative_l2_error"] < 1e-10
    output = {
        "classification": "CPU-only binary64 equations/index checks; WGSL uncompiled and GPU unbenchmarked",
        "source_commit": "8739f0793f84b96cb87a21558a117e1714184ad7",
        "passed": passed,
        "cases": cases,
        "positions_checked_for_unique_row_ownership": indexed_positions,
        "worst_producer_equation_relative_l2_error": worst_equation,
        "worst_fused_split_cpu_row_relative_l2_error": worst_row,
        "row_fft_vs_independent_direct_dft": dft_error,
        "limitations": [
            "Does not compile, parse, or execute the WGSL candidate.",
            "Does not model FP32 rounding, GPU contraction, register pressure, or occupancy.",
            "Does not prove GPU barrier uniformity or race freedom.",
            "Does not validate image quality, GPU speed, or power consumption.",
        ],
    }
    rendered = json.dumps(output, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
        print(f"Wrote CPU-only check to {args.output}")
        print(json.dumps({key: output[key] for key in ["passed", "positions_checked_for_unique_row_ownership", "worst_producer_equation_relative_l2_error", "worst_fused_split_cpu_row_relative_l2_error", "row_fft_vs_independent_direct_dft"]}))
    else:
        print(rendered, end="")
    if not passed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
