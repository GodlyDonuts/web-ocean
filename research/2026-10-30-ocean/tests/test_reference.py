import sys
from pathlib import Path
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "prototypes"))
from demand_planner import (Rect, OpaqueRegion, union_area, visible_tiles,
                           tile_pixels, merge_tiles, bloom_demand,
                           pullback_samples, DOWN_OFFSETS, spectrum_blend,
                           solar_direction, wave_from_azimuth, hermite,
                           harmonic_interpolation_error, derivative_response)


class VisibilityTests(unittest.TestCase):
    def test_unknown_or_transparent_metadata_cannot_occlude(self):
        mask = visible_tiles(64, 64, 16, [OpaqueRegion(Rect(0, 0, 64, 64))])
        self.assertTrue(mask.all())

    def test_moving_and_stale_regions_fail_open(self):
        for r in [OpaqueRegion(Rect(0, 0, 64, 64), True, True),
                  OpaqueRegion(Rect(0, 0, 64, 64), True, False, 1.0)]:
            self.assertTrue(visible_tiles(64, 64, 16, [r]).all())

    def test_full_occlusion_is_authoritative(self):
        self.assertFalse(visible_tiles(65, 63, 16, [], fully_occluded=True).any())

    def test_two_regions_can_cover_one_tile(self):
        regions = [OpaqueRegion(Rect(0, 0, 8, 16), True), OpaqueRegion(Rect(8, 0, 16, 16), True)]
        self.assertFalse(visible_tiles(16, 16, 16, regions).any())

    def test_union_does_not_double_count_overlap(self):
        self.assertEqual(union_area([Rect(0, 0, 8, 8), Rect(4, 0, 12, 8)], Rect(0,0,16,16)), 96)

    def test_visible_sliver_retains_whole_tile(self):
        region = OpaqueRegion(Rect(0, 0, 15.999, 16), True)
        self.assertTrue(visible_tiles(16, 16, 16, [region]).all())

    def test_merged_scissors_have_exact_tile_coverage_and_no_overlap(self):
        rng = np.random.default_rng(42)
        for _ in range(30):
            m = rng.random((7, 9)) > 0.4
            rects = merge_tiles(m, 8, 68, 53)
            raster = np.zeros((53, 68), dtype=np.uint8)
            for r in rects:
                raster[int(r.y0):int(r.y1), int(r.x0):int(r.x1)] += 1
            np.testing.assert_array_equal(raster, tile_pixels(m, 8, 68, 53))

    def test_random_occlusion_never_removes_visible_pixels(self):
        rng = np.random.default_rng(7)
        for _ in range(20):
            rectangles = []
            truth_hidden = np.zeros((47, 61), dtype=bool)
            for _ in range(8):
                x0, x1 = sorted(rng.integers(0, 62, 2))
                y0, y1 = sorted(rng.integers(0, 48, 2))
                rectangles.append(OpaqueRegion(Rect(x0, y0, x1, y1), True))
                truth_hidden[y0:y1,x0:x1] = True
            m = tile_pixels(visible_tiles(61,47,8,rectangles),8,61,47)
            self.assertFalse(np.any(~m & ~truth_hidden))


class DependencyTests(unittest.TestCase):
    def test_empty_demand_does_no_work(self):
        result = bloom_demand(np.zeros((72,128),bool), 6)
        self.assertFalse(result['hdr'].any())

    def test_local_visible_region_requires_hidden_hdr(self):
        visible = np.zeros((128,256),bool)
        visible[:, :8] = True
        r = bloom_demand(visible, 5)
        self.assertGreater(r['hdr'].sum(), visible.sum())
        self.assertTrue(np.all(r['hdr'][visible]))

    def test_more_levels_cannot_reduce_dependencies(self):
        visible = np.zeros((144,256),bool)
        visible[20:25,100:105] = True
        a = bloom_demand(visible, 3)['hdr']
        b = bloom_demand(visible, 7)['hdr']
        self.assertFalse(np.any(a & ~b))

    def test_sample_pullback_against_independent_scalar_reference(self):
        dest = np.zeros((5,7), bool)
        dest[2,3] = True
        actual = pullback_samples(dest,(11,16), DOWN_OFFSETS)
        expected = np.zeros((11,16),bool)
        import math
        for ox,oy in DOWN_OFFSETS:
            x = (3+.5)*16/7-.5+ox
            y = (2+.5)*11/5-.5+oy
            for yy in (math.floor(y),math.floor(y)+1):
                for xx in (math.floor(x),math.floor(x)+1):
                    expected[min(10,max(0,yy)),min(15,max(0,xx))] = True
        np.testing.assert_array_equal(actual,expected)


class PhysicsAndTimeTests(unittest.TestCase):
    def test_compass_axes(self):
        for azimuth, expected in [(0,[0,0,-1]),(90,[1,0,0]),(180,[0,0,1]),(270,[-1,0,0])]:
            np.testing.assert_allclose(solar_direction(azimuth,0),expected,atol=1e-14)
        np.testing.assert_allclose(solar_direction(45,90),[0,1,0],atol=1e-14)
        self.assertEqual(wave_from_azimuth(0),90)
        self.assertEqual(wave_from_azimuth(270),0)

    def test_phase_identity_and_energy_interpolation(self):
        z = np.exp(1j*np.linspace(0,2*np.pi,64,endpoint=False))
        h = spectrum_blend(np.ones(64),np.ones(64)*4,.5,z)
        np.testing.assert_allclose(np.abs(h)**2,2.5,atol=1e-14)
        np.testing.assert_allclose(h/np.abs(h),z,atol=1e-14)

    def test_hermite_matches_endpoint_values_and_slopes(self):
        for u, expected in [(0,2),(1,5)]:
            self.assertAlmostEqual(float(hermite(2,3,5,-1,2,u)),expected)
        eps=1e-6
        d0=(hermite(2,3,5,-1,2,eps)-hermite(2,3,5,-1,2,0))/(2*eps)
        d1=(hermite(2,3,5,-1,2,1)-hermite(2,3,5,-1,2,1-eps))/(2*eps)
        self.assertAlmostEqual(float(d0),3,places=4)
        self.assertAlmostEqual(float(d1),-1,places=4)

    def test_temporal_hermite_improves_smooth_harmonic(self):
        r=harmonic_interpolation_error(.486,2)
        self.assertLess(r['hermite_max_abs_error'],.015)
        self.assertGreater(r['linear_max_abs_error'],.2)

    def test_finite_difference_resolutions_are_not_interchangeable(self):
        self.assertLess(1-derivative_response(32/256,6),.002)
        self.assertGreater(1-derivative_response(32/128,6),.06)


if __name__ == '__main__':
    unittest.main(verbosity=2)
