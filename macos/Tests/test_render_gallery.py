#!/usr/bin/env python3
"""Fault-injection tests: CI must reject failed/missing/stale benchmark outputs."""
import importlib.util,json,subprocess,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('gallery',Path(__file__).with_name('render_gallery.py'))
gallery=importlib.util.module_from_spec(spec);spec.loader.exec_module(gallery)

class GalleryFailures(unittest.TestCase):
    def report(self):
        return dict(offscreen=True,windowCount=0,activationPolicy=2,errors=[],solarCacheWrites=0,
                    profiled=False,samples=180,gpuMedianMs=10,gpuMeanMs=11,gpuP95Ms=15)
    def run_benchmark(self, mode):
        with tempfile.TemporaryDirectory() as t:
            out=Path(t);report=out/'benchmark-day.json';report.write_text(json.dumps(self.report()))
            def runner(cmd,**kwargs):
                self.assertFalse(report.exists(),'Old report must be deleted before launch')
                if mode not in ['failed','missing']:
                    d=self.report()
                    if mode=='errors':d['errors']=['GPU failure']
                    if mode=='empty':d['samples']=0
                    if mode=='nan':d['gpuMedianMs']=float('nan')
                    report.write_text(json.dumps(d))
                return subprocess.CompletedProcess(cmd,17 if mode=='failed' else 0,stdout='',stderr='')
            return gallery.benchmark('day',{},out,runner=runner)
    def test_failed_process_rejects_stale_report(self):self.assertFalse(self.run_benchmark('failed')['ok'])
    def test_missing_report_rejected(self):self.assertFalse(self.run_benchmark('missing')['ok'])
    def test_gpu_errors_rejected(self):self.assertFalse(self.run_benchmark('errors')['ok'])
    def test_empty_samples_rejected(self):self.assertFalse(self.run_benchmark('empty')['ok'])
    def test_nonfinite_timings_rejected(self):self.assertFalse(self.run_benchmark('nan')['ok'])
    def test_valid_benchmark_accepted(self):self.assertTrue(self.run_benchmark('valid')['ok'])
    def test_failed_capture_does_not_reuse_old_png(self):
        with tempfile.TemporaryDirectory() as t:
            out=Path(t);raw=out/'day.rgba16f.bgra8';png=out/'day.png'
            raw.write_bytes(b'old');png.write_bytes(b'old')
            def runner(cmd,**kwargs):return subprocess.CompletedProcess(cmd,1,stdout='',stderr='Failed')
            self.assertFalse(gallery.capture('day',{},out,runner=runner)['ok'])
            self.assertFalse(raw.exists());self.assertFalse(png.exists())
    def test_benchmark_failure_fails_gallery_exit(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as t:
            gallery.Image.new('RGB',(2,2)).save(Path(t)/'noon.png')
            with patch.object(gallery,'out',Path(t)),patch.object(gallery,'capture',return_value={'scene':'noon','ok':True}),patch.object(gallery,'benchmark',return_value={'ok':False}):
                self.assertEqual(gallery.main(['noon']),1)

if __name__=='__main__':unittest.main()
