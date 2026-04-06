# FPA Final

MATLAB analysis and visualization pipeline for fiber photometry session processing, population plots, and export workflows.

## What This Repo Contains

- Session-processing scripts for building `sub_*.mat` outputs from TDT and behavior data
- Population and per-animal plotting utilities
- GUI tools for group-level trace exploration and tone-metric export
- FLMM-ready export tooling
- A bundled `TDTMatlabSDK/` dependency used by the analysis pipeline

## Repository Layout

- `Run_all.m`: end-to-end starter script
- `fp_project_setup.m`: adds the project folders to the MATLAB path
- `Functions/`: reusable analysis and plotting helpers
- `Debug/`: one-off debugging and inspection scripts
- `Legacy/`: older superseded scripts kept for reference
- `TDTMatlabSDK/`: bundled vendor SDK dependency

## Expected Local Data Layout

This repository is set up to keep large local datasets out of version control. The code expects a project root shaped like this:

```text
FPA_Final/
├── AnimalData/
├── behavior/
├── Results/
├── SessionKey.xlsx
└── ...code files
```

These data and output paths are ignored by Git by default.

## Quick Start

1. Open the repo in MATLAB.
2. Run `fp_project_setup`.
3. Place your local data folders in the repo root if you want to use the default paths.
4. Start with `Run_all` for the standard workflow.

Useful entrypoints:

- `Run_all.m`: build session key, process sessions, launch the population viewer
- `fp_run_all_sessions.m`: batch-process sessions into `Results/session/`
- `fp_run_all_sessions_FLMM_export.m`: export FLMM-ready CSV files
- `fp_plot_all_animals_tiles.m`: generate per-animal tiled plots
- `fp_early_vs_late.m`: run early-vs-late plotting batches
- `fp_gui_population_viewer_1214.m`: active population viewer GUI
- `fp_gui_population_viewer_tone_metrics_sessionkey_0114.m`: GUI with tone metrics and SessionKey integration

## Notes For GitHub

- `.gitignore` excludes generated outputs, local datasets, MATLAB autosaves, and machine-specific clutter.
- The bundled `TDTMatlabSDK/` is kept in the repo because the code depends on it locally.
- If you do not want to redistribute the SDK, remove that folder and document an external install step instead.

## Upload Checklist

- Confirm `AnimalData/`, `behavior/`, `Results/`, and `SessionKey.xlsx` are local-only
- Review `Debug/` and `Legacy/` and remove anything you do not want public
- Add a license if you plan to share or publish the code broadly
