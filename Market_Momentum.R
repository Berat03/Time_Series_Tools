calc_sma <- function(ticker_stock, from, to, time_period, length){
  stock <- tq_get(ticker_stock, from = from, to = to , periodicity = time_period) |>
    mutate(moving_average = zoo::rollmean(x = adjusted, k = length, fill = NA, align = "right")) |>
    filter(date > ymd(from)) |> #safer with ymd
    select(date, Price = adjusted, "Moving Average" = moving_average) |>
    pivot_longer(cols = !date, names_to = "Metric", values_to = "Value")
    return (stock)
  }


result <- calc_sma(ticker_stock = "^GSPC", from = ymd("2022-01-18") , to = ymd("2023-01-10") , time_period = "daily", length = 20)

ggplot(result, aes(x = date)) +
  geom_line(aes(y = Value, color = Metric)) +
  labs(x="", y = "") +
  theme(legend.position="top")
