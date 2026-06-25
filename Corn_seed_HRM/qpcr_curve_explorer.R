# ============================================================================
# QuantStudio qPCR 导出文件解析 + 自由选孔绘制扩增曲线 / 熔解曲线
# 适用文件: 2015-09-10_221232.txt
# 文件结构: 一个 txt 里用 [Section Name] 拼接了多个 Tab 分隔的数据表
#           本脚本已确认包含: [Sample Setup] [Amplification Data]
#                              [Results] [Melt Curve Raw Data] [Melt Curve Result]
# ============================================================================

library(dplyr)
library(ggplot2)
library(scales)

file_path <- "2015-09-10_221232.txt"   # 如路径不同请改这里
lines <- readLines(file_path, encoding = "UTF-8")

# ----------------------------------------------------------------------------
# 1. 按 [SectionName] 把整份文件切成若干张表，按需取出某一节
# ----------------------------------------------------------------------------
section_idx   <- grep("^\\[.*\\]\\s*$", lines)
section_names <- trimws(gsub("^\\[|\\]\\s*$", "", lines[section_idx]))

read_section <- function(name) {
  i <- which(section_names == name)
  if (length(i) == 0) stop(paste0("未在文件中找到小节: [", name, "]"))
  start <- section_idx[i] + 1
  end   <- if (i < length(section_idx)) section_idx[i + 1] - 1 else length(lines)
  block <- lines[start:end]
  block <- block[nzchar(trimws(block))]          # 去掉空行
  read.delim(text = block, header = TRUE, sep = "\t",
             quote = "", stringsAsFactors = FALSE)  # quote="" 避免引号干扰解析
}

amp_raw   <- read_section("Amplification Data")   # 扩增原始数据 (768 行, 96孔 x 8 cycle)
melt_raw  <- read_section("Melt Curve Raw Data")   # 熔解曲线原始数据 (96孔, 每孔数百个温度点)
setup_raw <- read_section("Sample Setup")          # 孔位 <-> 样本名 对照表

# ----------------------------------------------------------------------------
# 2. 数值清洗
#    注意: QuantStudio 导出的大数字带千位分隔符逗号, 例如 "838,411.438"，
#    熔解曲线的 Fluorescence / Derivative 几乎每一行都是这种格式，
#    必须先去掉逗号再转 as.numeric()，否则会全部变成 NA。
# ----------------------------------------------------------------------------
to_num <- function(x) as.numeric(gsub(",", "", x))

amp <- amp_raw %>%
  transmute(
    WellPos = toupper(trimws(Well.Position)),   # 形如 "A1"、"H12"
    Cycle   = as.numeric(Cycle),
    Target  = Target.Name,
    Rn      = to_num(Rn),
    DeltaRn = to_num(Delta.Rn)
  )

melt <- melt_raw %>%
  transmute(
    WellPos      = toupper(trimws(Well.Position)),
    Temperature  = as.numeric(Temperature),
    Target       = Target.Name,
    Fluorescence = to_num(Fluorescence),
    Derivative   = to_num(Derivative)
  )

# 孔位 -> 样本名对照 (用于图例同时显示孔位+样本名，也用于按样本批量选孔)
# 部分对照孔 Sample Name 为空(比如11、12列)，这种情况图例改用 Target Name 标注，避免图例只剩孔位号
well_meta <- setup_raw %>%
  transmute(
    WellPos    = toupper(trimws(Well.Position)),
    SampleName = trimws(Sample.Name),
    TargetName = trimws(Target.Name)
  ) %>%
  distinct(WellPos, SampleName, TargetName) %>%
  mutate(Label = case_when(
    nzchar(SampleName) ~ paste0(WellPos, " (", SampleName, ")"),
    nzchar(TargetName)  ~ paste0(WellPos, " (", TargetName, ")"),
    TRUE                ~ WellPos
  ))

# 按样本名批量取孔位，比如 wells_for_sample("Sample 1")
wells_for_sample <- function(sample_name) {
  well_meta %>% filter(SampleName == sample_name) %>% pull(WellPos)
}

# 按列号批量取孔位，比如 wells_in_columns(11:12) 取出全部行的第11、12列(常见的对照组排布)
# rows 默认自动取数据里实际出现过的行号(比如96孔板就是 A~H)
wells_in_columns <- function(cols, rows = NULL) {
  if (is.null(rows)) {
    rows <- sort(unique(substr(c(amp$WellPos, melt$WellPos), 1, 1)))
  }
  as.vector(outer(rows, cols, FUN = function(r, c) paste0(r, c)))
}

# ----------------------------------------------------------------------------
# 3. 绘图函数：把想看的孔位传进去即可
# ----------------------------------------------------------------------------

# 扩增曲线。
#   wells:    要画的孔位向量；留空(NULL)则画当前数据里的全部孔(全板总览图)
#   metric:   "DeltaRn"(基线校正后，默认配线性纵轴) 或 "Rn"(原始信号，常配对数纵轴)
#   color_by: "Well" 按单孔+样本名上色(适合少量孔位，便于分辨每个样本)
#             "Row"  按行 A/B/C... 上色(适合像QuantStudio软件那种全板总览图，对应图例 A~P)
#   y_scale:  "linear" 或 "log"。"log" 下纵轴会显示成 0.1 / 1 / 10 这种普通数字,
#             而不是 1E-01 / 1E+00 / 1E+01 的科学计数法
plot_amplification <- function(wells = NULL, target = NULL,
                                metric = c("DeltaRn", "Rn"),
                                color_by = c("Well", "Row"),
                                y_scale = c("linear", "log")) {
  metric   <- match.arg(metric)
  color_by <- match.arg(color_by)
  y_scale  <- match.arg(y_scale)

  # 对数纵轴必须用恒正的 Rn；ΔRn 可能为 0 或负值，取对数会出错，这里自动切换并提示
  if (y_scale == "log" && metric == "DeltaRn") {
    message("提示：对数纵轴下已自动把 metric 切换为 'Rn'（ΔRn 可能含0或负值，无法取对数）。")
    metric <- "Rn"
  }

  d <- amp
  if (!is.null(wells))  d <- d %>% filter(WellPos %in% toupper(trimws(wells)))
  if (!is.null(target)) d <- d %>% filter(Target == target)
  if (nrow(d) == 0) stop("没有匹配到任何孔位的数据，请检查孔位名称(如 'A1'/'H12')是否正确。")

  d <- d %>%
    left_join(well_meta, by = "WellPos") %>%
    mutate(Row = substr(WellPos, 1, 1))

  group_col   <- if (color_by == "Row") "Row" else "Label"
  legend_name <- if (color_by == "Row") "行 (Row)" else "孔位 / 样本"
  y_lab       <- if (metric == "DeltaRn") "\u0394Rn (基线校正后荧光)" else "Rn (原始荧光)"

  p <- ggplot(d, aes(Cycle, .data[[metric]], color = .data[[group_col]], group = WellPos)) +
    geom_line(linewidth = 0.6, alpha = 0.85) +
    labs(title = "扩增曲线 (Amplification Plot)",
         x = "循环数 (Cycle)", y = y_lab, color = legend_name) +
    theme_bw(base_size = 12) +
    theme(plot.title = element_text(face = "bold", hjust = 0.5),
          panel.grid.minor = element_line(linewidth = 0.2))

  # 关键: 对数纵轴 + 普通数字标签(不用科学计数法)
  if (y_scale == "log") {
    p <- p + scale_y_log10(labels = scales::label_number(accuracy = 0.1))
  }

  p
}

# 熔解曲线。type = "derivative" 是标准的熔解峰图(-dF/dT vs 温度，用于读Tm)，
#          type = "raw" 是熔解阶段的原始荧光信号(随温度下降的那条曲线)
plot_melt <- function(wells, target = NULL, type = c("derivative", "raw")) {
  type  <- match.arg(type)
  wells <- toupper(trimws(wells))

  d <- melt %>% filter(WellPos %in% wells)
  if (!is.null(target)) d <- d %>% filter(Target == target)
  if (nrow(d) == 0) stop("没有匹配到任何孔位的数据，请检查孔位名称(如 'A1'/'H12')是否正确。")

  d <- d %>% left_join(well_meta, by = "WellPos")

  if (type == "derivative") {
    ggplot(d, aes(Temperature, Derivative, color = Label, group = WellPos)) +
      geom_line(linewidth = 0.8) +
      labs(title = "熔解曲线 - 一阶导数峰图 (-dF/dT)",
           x = "温度 (\u00b0C)", y = "-dF/dT", color = "孔位 / 样本") +
      theme_minimal(base_size = 12) +
      theme(plot.title = element_text(face = "bold", hjust = 0.5))
  } else {
    ggplot(d, aes(Temperature, Fluorescence, color = Label, group = WellPos)) +
      geom_line(linewidth = 0.8) +
      labs(title = "熔解曲线 - 原始荧光信号",
           x = "温度 (\u00b0C)", y = "荧光强度", color = "孔位 / 样本") +
      theme_minimal(base_size = 12) +
      theme(plot.title = element_text(face = "bold", hjust = 0.5))
  }
}

# ----------------------------------------------------------------------------
# 4. 在这里自由选择你想看的孔位，改完直接整段重新运行即可
# ----------------------------------------------------------------------------
selected_wells <- c("A1", "A2", "B1", "H10")     # <<< 改成你想画的孔位
# 也可以按样本名批量取孔位，例如:
# selected_wells <- wells_for_sample("Sample 1")

p_amp        <- plot_amplification(selected_wells)                 # 默认画 ΔRn(线性纵轴, 按孔上色)
p_melt_deriv <- plot_melt(selected_wells, type = "derivative")      # 熔解峰图(读Tm用)
p_melt_raw   <- plot_melt(selected_wells, type = "raw")             # 熔解原始荧光

# 像QuantStudio软件那种全板总览图: Rn + 对数纵轴(不用科学计数法) + 按行(A/B/C...)上色
# wells = NULL 表示画文件里出现的所有孔；想看部分孔就传入对应的孔位向量
p_amp_overview <- plot_amplification(wells = NULL, metric = "Rn",
                                      color_by = "Row", y_scale = "log")

print(p_amp)
print(p_melt_deriv)
print(p_melt_raw)
print(p_amp_overview)

# 11、12列对照组 (这份数据里这两列 Sample Name 为空、Target Name = "Target 2"，
# 和左边1~10列的 Target 1 是两套独立的体系，所以单独拎出来看)
control_wells        <- wells_in_columns(11:12)
p_amp_control         <- plot_amplification(control_wells, metric = "Rn", y_scale = "log")
p_melt_control_deriv  <- plot_melt(control_wells, type = "derivative")
p_melt_control_raw    <- plot_melt(control_wells, type = "raw")

print(p_amp_control)
print(p_melt_control_deriv)
print(p_melt_control_raw)

# ----------------------------------------------------------------------------
# 5. 需要的话保存为图片
# ----------------------------------------------------------------------------
ggsave("amplification_selected.png",   p_amp,        width = 9, height = 6, dpi = 300, bg = "white")
ggsave("melt_derivative_selected.png", p_melt_deriv, width = 9, height = 6, dpi = 300, bg = "white")
ggsave("melt_raw_selected.png",        p_melt_raw,   width = 9, height = 6, dpi = 300, bg = "white")
ggsave("amplification_overview_log.png", p_amp_overview, width = 9, height = 6, dpi = 300, bg = "white")
ggsave("amplification_control_11_12.png",       p_amp_control,        width = 9, height = 6, dpi = 300, bg = "white")
ggsave("melt_control_11_12_derivative.png",     p_melt_control_deriv, width = 9, height = 6, dpi = 300, bg = "white")
ggsave("melt_control_11_12_raw.png",            p_melt_control_raw,   width = 9, height = 6, dpi = 300, bg = "white")
