# Native rendering

Plot uses Objective-C and macOS frameworks only. AppKit handles windows, controls and text; Metal renders data; Core Graphics handles axes and image composition. There is no WebKit, Plotly, JavaScript or Rust runtime, and no package manager is needed to build it.

```sh
./bin/install-app
./bin/test
./bin/benchmark-metal --points 3000000
./bin/benchmark-metal --points 1000000 --windows 8 --markers
```

The app is installed only at `/Applications/Plot.app`. `bin/build-app` installs without launching. Test and benchmark executables live in ignored `build/`; no additional app bundles are created.

## Data and drawing

CSV, whitespace tables, MPMS `[Data]`, SPEC `#L` and Rigaku RAS are parsed directly into contiguous 64-bit numeric storage. Missing cells remain NaN. Files opened together are grouped by default X/Y names, with columns limited to those present in every file. The original data stays immutable and can be shared by duplicated windows.

Each plotted series keeps its original 64-bit XY values and a normalized 32-bit GPU buffer. Axis limits remain doubles. Deep zoom rebuilds the buffer from the original doubles before float precision would merge nearby points. Buffer replacement leaves outstanding GPU commands' data intact. The GPU pixel tests cover large offsets, deep zoom, missing-data gaps, isolated markers, shared axes and selection colors.

The Metal device, command queue and pipelines are shared across all windows. Views redraw only on changes; there is no continuous render loop. Selection changes update uniforms and draw order without recreating buffers. Pointer inspection runs after a short dwell on a background queue and does not redraw the GPU layer.

One opaque AppKit toolbar follows the focused plot. It hides while another application or an auxiliary window is active. The plot window itself is rectangular and opaque; there are no transparent regions intercepting clicks outside the visible shape. Resize from the bottom-right grip.

The toolbar supports home, view history, pan/box zoom, line/point display, outlier exclusion, axes, filtering and PNG export. Multiple Y columns are stacked with a shared X range. Axis limits can be entered manually; leave both limits blank for automatic fitting. Closing the filter window resets the filter. CSV export writes filtered rows from all grouped files, retaining a dataset label when needed. PNG export explicitly renders the Metal textures and composites the axes and header; it does not rely on capturing an opaque GPU layer.

Theme and editor settings are saved in macOS user defaults for the existing `com.okadaharuto.plots` bundle identifier. Graphs remain white in both themes. Native settings start with system theme/default editor; old WebKit local-storage preferences are not imported.

## Initial drawing benchmark

Measured on Apple M5 (10 GPU cores), 2026-10-16, using the first Metal prototype and its Core Graphics reference. Each target is 1200×800 pixels. Every point is drawn without downsampling. One warm-up and five measured batches; table entries are medians in milliseconds.

| Data | Mode | Metal GPU | Metal including wait | Core Graphics |
| --- | --- | ---: | ---: | ---: |
| 1,000 × 1 | Line | 0.11 | 0.29 | 0.67 |
| 3,000,000 × 1 | Line | 11.28 | 11.83 | 464.84 |
| 1,000,000 × 8 | Line | 25.78 | 29.00 | 1,035.91 |
| 1,000 × 1 | Point | 0.10 | 0.44 | 0.77 |
| 3,000,000 × 1 | Point | 25.08 | 27.67 | 2,066.58 |
| 1,000,000 × 8 | Point | 45.05 | 49.72 | 5,588.09 |

[Raw measurements](metal-benchmark-2026-10-16.csv). Eight targets means eight independent datasets rendered sequentially, not the FPS of eight composited windows. Metal uses 4x MSAA; the Core Graphics reference uses its standard antialiasing. Line joins and dot edges are not identical. `prepare_ms` excludes file parsing and synthetic-data generation. The memory column contains both backends and is not a backend memory comparison.

These numbers do not measure power consumption, compositing, input latency or the previous Plotly renderer. They demonstrate that the dense-data case is suitable for Metal; they do not establish that every small plot is cheaper on every Mac. The benchmark uses the production renderer, so it can be rerun after changes.

During migration, the new parser was also compared with the previous Rust/JSON path on five real scientific files (484,295 numeric cells): grouping, row/column counts, defaults and missing values matched. Finite values matched within four floating-point epsilons; the JSON and direct decimal parsing paths can differ in their last bits.

## Migration observations

A separate one-off comparison used the previous Plotly 2.35.2 in WKWebView and the native plot controller with the same prepared 3-million-point waveform at 1200×800 pixels. Plotly initial plot creation plus two animation frames and a WebGL finish took 585ms. Native plot construction plus Metal rendering/readback took about 97ms. Neither includes file parsing or initial library/pipeline startup; the different synchronization paths mean this is not a pure GPU speed comparison.

After redraws, `vmmap` reported 25.9MiB for the WebKit host and 912.4MiB for its new WebContent process. The native process reported about 229.5MiB of physical footprint. WebKit's GPU/network services are excluded. These observations support the migration's memory goal, but do not measure total GPU memory or energy use. [Recorded observations](migration-measurements-2026-10-16.json).

Eight actual native windows, each containing one million points, were also opened successfully. Power consumption remains unmeasured.
