# HRM-ML Paper

This repository provides the supplementary materials for the following study:

*Precise prediction of dual-species synthetic community structure with high-resolution melting curve and machine learning* authored by Chun-Hui Gao, Jiaqi He, Bin Cao, Huan He, Rui Zhang, Cong Lan, Yichao Wu, and Peng Cai. **In submission**.

## Read the contents

-   Online Book: <https://hrm-ml.bio-spring.top>

-   PDF document: <https://hrm-ml.bio-spring.top/HRM-ML-Paper.pdf>

## Compile by yourself

### Requirements

This project depends on several Python modules and R packages.

-   Python
    -   `scikit-learn`
    -   `numpy`
    -   `pandas`

Using conda.

``` shell
conda create -n hrm-ml
conda activate hrm-ml
conda install scikit-learn numpy pandas
```

-   R
    -   `tidyverse`
    -   `tidymodels`
    -   `mcmodel`: in [GitHub](https://github.com/gaospecial/mcmodel).

Using `pak` to install.

``` r
install.packages("pak")
pak::pak("tidyverse")
pak::pak("tidymodels")
pak::pak("gaospecial/mcmodel")
```

### Compile

Using RStudio.

``` shell
git clone https://github.com/gaospecial/hrm-ml
cd hrm-ml
```

Open `*.Rproj` file with RStudio, and press `<SHIFT> + <CMD> + B` to compile the book.
