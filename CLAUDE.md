# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Quarto book accompanying the paper *"Precise prediction of dual-species synthetic community structure with high-resolution melting curve and machine learning"*. It uses R for data processing/visualization and Python (via reticulate) for ML model comparison, published as a reproducible literate programming document.

Online: https://hrm-ml.bio-spring.top

## Build Commands

```bash
# Render the entire book (HTML + PDF)
quarto render

# Render a single chapter
quarto render single-species-modeling.qmd

# Preview with live reload
quarto preview
```

Requires R with tidyverse/tidymodels/mcmodel/cowplot installed, Python with scikit-learn/numpy/pandas, and Quarto CLI. PDF output requires a LaTeX distribution with `ctex` and `amsthm` packages.

## Architecture

**Literate programming pipeline** — each `.qmd` chapter contains R and Python code cells alongside narrative:

- `global-settings.qmd` — shared setup loaded by all chapters (packages, theme, strain labels, well positions, seed)
- `data-preprocess.qmd` — reads raw qPCR data from `data-raw/modeling-qPCR/` (QuantStudio files via `mcmodel::read_quantstudio()`), filters melting curves (80–90°C), writes clean CSVs to `data-clean/`
- `single-species-modeling.qmd` — amplification curves, Ct analysis, linear regression for E. coli and P. putida
- `two-species-modeling.qmd` — dual-species melting curves, Random Forest models on gradient matrix
- `model-selection.qmd` — compares ML algorithms using Python (scikit-learn) via reticulate
- `model-optimization.qmd` — training data size, cycle number, and hyperparameter effects
- `method-evaluation.qmd` — validates against qPCR gold standard and 16S rRNA sequencing (DADA2 pipeline)

**Data flow:** `data-raw/` → `data-preprocess.qmd` → `data-clean/*.csv` → modeling chapters

**Key data concepts:**
- 384-well plate: single-species dilution series (A1–F3 for EC, A4–F6 for PP) + 16×16 two-species gradient matrix (A7–P22)
- PCR cycles 30/35/40 × 3 experimental replicates
- ML features: temperature columns (T80, T80.1, … T90); targets: species concentrations (label_E, label_P)

## Conventions

- Quarto freeze mode is `auto` — code only re-executes when source changes; cached results live in `_freeze/`
- The `_quarto.yml` chapter order determines book structure, not filename sorting
- R code uses `tidyverse` style; global ggplot theme is set in `global-settings.qmd`
- Strain colors: EC = red3, PP = purple3
- Random seed: `set.seed(0)` in global settings
