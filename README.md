# HRM-ML Paper

This repository provides the supplementary materials for the following study:

*Precise prediction of dual-species synthetic community structure with high-resolution melting curve and machine learning* authored by Chun-Hui Gao, Jiaqi He, Bin Cao, Huan He, Rui Zhang, Cong Lan, Yichao Wu, and Peng Cai. **In submission**.

## Read the contents

-   Online Book: <https://hrm-ml.bio-spring.top>

-   PDF document: <https://hrm-ml.bio-spring.top/HRM-ML-Paper.pdf>

## Compile by yourself

### Requirements

This project uses [renv](https://rstudio.github.io/renv/) to manage R and Python dependencies.

-   R (with renv)
-   Python (used via reticulate, dependencies are managed by renv)
-   [Quarto CLI](https://quarto.org/)

### Compile

``` shell
git clone https://github.com/gaospecial/hrm-ml
cd hrm-ml
```

Restore the R environment:

``` r
renv::restore()
```

Then render the book with Quarto CLI:

``` shell
quarto render
```
