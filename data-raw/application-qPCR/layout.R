library(dplyr)

carbons = paste0(rep(LETTERS[1:8], each = 9), rep(1:9, times = 8))[-1]
carbon_name = read.csv(xfun::magic_path("carbon.csv")) |> 
    mutate(sample = carbons)

# plate layout
plate = tibble(
    well_position = paste0(rep(LETTERS[1:16], each = 24), rep(1:24, times = 16)),
    sample = c(rep(carbons[1:8], times = 3, each = 3), rep(carbons[9:16], times = 3, each = 3), rep(carbons[17:24], times = 3, each = 3), rep(carbons[25:32], times = 3, each = 3), rep(carbons[33:40], times = 3, each = 3), rep('pls', times = 24)),
    target = c(rep(rep(c('EC', 'PP', '16S'), each =  24), times = 5), rep('std', times = 24))
) |> left_join(carbon_name)


# write.csv(plate, 'plate-layout.csv', row.names = FALSE)
