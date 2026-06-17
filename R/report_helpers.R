# Shared helpers for Quarto report display.

label_names <- function(x) {
  labels <- gsub("_", " ", x)
  labels <- gsub("\\belo\\b", "Elo", labels, ignore.case = TRUE)
  labels <- gsub("\\brmse\\b", "RMSE", labels, ignore.case = TRUE)
  labels <- gsub("\\bmae\\b", "MAE", labels, ignore.case = TRUE)
  labels <- gsub("\\bid\\b", "ID", labels, ignore.case = TRUE)
  tools::toTitleCase(labels)
}

fmt_number <- function(x, digits = 3) {
  ifelse(
    is.na(x),
    NA,
    format(round(x, digits), big.mark = ",", nsmall = digits, trim = TRUE)
  )
}

fmt_integer <- function(x) {
  ifelse(is.na(x), NA, format(round(x), big.mark = ",", trim = TRUE))
}

fmt_percent <- function(x, digits = 1) {
  ifelse(is.na(x), NA, paste0(format(round(100 * x, digits), nsmall = digits, trim = TRUE), "%"))
}

fmt_p_value <- function(x) {
  ifelse(
    is.na(x),
    NA,
    ifelse(x < 0.001, "<0.001", format(round(x, 3), nsmall = 3, trim = TRUE))
  )
}

display_table <- function(x, caption = NULL, digits = 3, max_rows = NULL) {
  out <- as.data.frame(x)
  if (!is.null(max_rows) && nrow(out) > max_rows) {
    out <- head(out, max_rows)
  }
  names(out) <- label_names(names(out))
  knitr::kable(
    out,
    format = "html",
    escape = TRUE,
    digits = digits,
    caption = caption,
    table.attr = 'class="clean-table"'
  )
}

metric_cards <- function(cards) {
  card_html <- apply(cards, 1, function(row) {
    note <- if (!is.na(row[["note"]]) && nzchar(row[["note"]])) {
      paste0("<small>", row[["note"]], "</small>")
    } else {
      ""
    }
    paste0(
      '<div class="metric">',
      "<strong>", row[["label"]], "</strong>",
      "<span>", row[["value"]], "</span>",
      note,
      "</div>"
    )
  })
  paste0('<div class="metric-strip">', paste(card_html, collapse = ""), "</div>")
}

empty_note <- function(text) {
  data.frame(note = text)
}
