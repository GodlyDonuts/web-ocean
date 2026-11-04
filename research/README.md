# Supplied ocean research

`2026-10-30-ocean/` retains the user-supplied research kit. All 19 manifest-listed files were checked for byte count and SHA-256 and copied unchanged, together with its original manifest. Its source snapshot is commit `8739f0793f84b96cb87a21558a117e1714184ad7`; its workload counts are not descriptions of the current native renderer.

The original README and scripts are reference material. The original visibility probe defaults to opening desktop windows; automated project checks use the adapted opt-in diagnostic under `macos/Diagnostics/` instead. The included WGSL is a reference for a fusion already implemented and GPU-validated in native Metal. Its CPU results do not establish GPU timing, rendered equivalence or energy savings.

The original 17 CPU tests and the independent fused-equation/DFT checker were rerun successfully with the bundled Python runtime. They require NumPy (and Matplotlib for plot regeneration). They are separate from the native app's package-free build. The imported results remain the supplied evidence; local reruns and the current six-level native bloom model are recorded in the project integration report.

See [the engineering roadmap](../docs/engineering-roadmap.md), [the integration verification report](../docs/research-integration-report-2026-10-30.json), and [the current native bloom analysis](../docs/research-native-bloom-2026-10-30.json).
