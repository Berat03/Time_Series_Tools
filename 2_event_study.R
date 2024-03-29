# User Inputs
ant = 10
est = 30
adj = 10
ticker_stock <- "ATVI" 
ticker_bench <- "^GSPC" 
event_date <- YMD("2018-11-05") 

# Dates to index from
begin <-event_date - as.difftime((7 * est), unit="days") 
end <-event_date + as.difftime((7 * adj), unit="days") 

# Get data from yahoo finance
stock <- tq_get(ticker_stock, get = "stock.prices", from = begin, to = end, periodicity = "daily") |>
  tq_mutate(mutate_fun = periodReturn, col_rename = 'stock_return', period = "daily")  |>
  select(symbol, date, stock_adj = adjusted, stock_return) |>
  arrange(date) |>
  slice(-1)
bench <- tq_get(ticker_bench, get = "stock.prices", from = begin, to = end, periodicity = "daily") |>
  tq_mutate(mutate_fun = periodReturn, col_rename = 'bench_return', period = "daily") |>
  select(symbol, date, bench_adj = adjusted, bench_return) |>
  arrange(date) |>
  slice(-1)

# Mutate data
abnormal_returns <- left_join(stock, bench, by = c("date" = "date")) |>
  mutate(ID = row_number()) 
eventID <- which(abnormal_returns$date == event_date, arr.ind=TRUE)

abnormal_returns <- abnormal_returns |>
  mutate(dates_relative = as.integer(-1 *(ID - eventID))) |>
  mutate(time_period = ifelse(dates_relative > ant, "EST", 
                              ifelse(dates_relative <= ant & dates_relative >= 1, "ANT", 
                                     ifelse(dates_relative == 0, "EVENT", ifelse(dates_relative < 0, "ADJ", NA))))) |>
  filter(dates_relative <= (est + ant) & dates_relative >= (-1 * adj)) |> 
  select(date, dates_relative, time_period, stock_adj, bench_adj, stock_return, bench_return) 

EST <-abnormal_returns[abnormal_returns$time_period == "EST",]
average_stock_returns_est<- mean(EST$stock_return)
CAPM_table <- EST |>
  tq_performance(Ra = stock_return, Rb = bench_return, performance_fun = table.CAPM)
alpha <- CAPM_table$Alpha
beta <- CAPM_table$Beta 

abnormal_returns <- abnormal_returns |>
  select(date,dates_relative, time_period,stock_adj, bench_adj, stock_return, bench_return) |>
  mutate(ConstantModel= stock_return - average_stock_returns_est) |>
  mutate(MarketModel = stock_return - bench_return) |>
  mutate(CAPM =  stock_return - (alpha + beta*bench_return))




####################################################################################
# Less 'fat' code
EST <- abnormal_returns[abnormal_returns$time_period == "EST",] # Second time declaring
ANT <- abnormal_returns[abnormal_returns$time_period == "ANT",] 
EVENT <- abnormal_returns[abnormal_returns$time_period == "EVENT",]
ADJ <- abnormal_returns[abnormal_returns$time_period == "ADJ",]
TOTAL <- abnormal_returns[abnormal_returns$time_period != "EST",]

time_periods = c("Anticipation", "Event", "Adjustment", "Total")

stdev_const <- STDEV(abnormal_returns[["ConstantModel"]])
stdev_market <- STDEV(abnormal_returns[["MarketModel"]])
stdev_capm <- STDEV(abnormal_returns[["CAPM"]])

STD_errors <- data_frame(time_periods = time_periods, const_stdev = c((stdev_const * sqrt(10)),stdev_const,(stdev_const * sqrt(10)), (stdev_const * sqrt(21))),
                         market_stdev = c((stdev_market * sqrt(10)), stdev_market,(stdev_market * sqrt(10)), (stdev_market * sqrt(21))),
                         capm_stdev = c((stdev_capm * sqrt(10)),stdev_capm,(stdev_capm * sqrt(10)), (stdev_capm * sqrt(21))))

returns_CAR <- tibble(time_periods = time_periods, 
                      ConstantModel = c(sum(ANT$ConstantModel), sum(EVENT$ConstantModel), sum(ADJ$ConstantModel), SUM(TOTAL$ConstantModel)),
                      MarketModel = c(sum(ANT$MarketModel), sum(EVENT$MarketModel), sum(ADJ$MarketModel), sum(TOTAL$MarketModel)), 
                      CAPM = c(sum(ANT$CAPM), sum(EVENT$CAPM), sum(ADJ$CAPM), sum(TOTAL$CAPM)))

bhar <- function(dataframe, model){
  return(apply ((dataframe[, model] + 1), 2, prod) - 1)
}

returns_BHAR <- tibble(time_periods = time_periods, 
                       ConstantModel = c(bhar(ANT, "ConstantModel"), bhar(EVENT, "ConstantModel"), bhar(ADJ, "ConstantModel"), bhar(TOTAL, "ConstantModel")),
                       MarketModel = c(bhar(ANT, "MarketModel"), bhar(EVENT, "MarketModel"), bhar(ADJ, "MarketModel"), bhar(TOTAL, "MarketModel")),
                       CAPM = c(bhar(ANT, "CAPM"), bhar(EVENT, "CAPM"), bhar(ADJ, "CAPM"), bhar(TOTAL, "CAPM")))

t_stat_CAR <- cbind(returns_CAR[1],round(returns_CAR[-1]/STD_errors[-1],digits = 6))

t_stat_BHAR <- cbind(returns_BHAR[1],round(returns_BHAR[-1]/STD_errors[-1],digits = 6))

inital_df <- nrow(EST) 
p_val_CAR <- t_stat_CAR |>
  mutate(ConstantModel = (2 * pt(q=abs(t_stat_CAR$ConstantModel), lower.tail = FALSE, df=(inital_df - 1)))) |>
  mutate(MarketModel = (2 * pt(q=abs(t_stat_CAR$MarketModel), lower.tail = FALSE, df=(inital_df - 1)))) |>
  mutate(CAPM = (2 * pt(q=abs(t_stat_CAR$CAPM), lower.tail = FALSE, df=(inital_df - 2)))) |>
  select(time_periods, ConstantModel, MarketModel, CAPM) 

p_val_BHAR <- t_stat_BHAR |>
  mutate(ConstantModel = (2 * pt(q=abs(t_stat_BHAR$ConstantModel), lower.tail = FALSE, df=(inital_df - 1)))) |>
  mutate(MarketModel = (2 * pt(q=abs(t_stat_BHAR$MarketModel), lower.tail = FALSE, df=(inital_df - 1)))) |>
  mutate(CAPM = (2 * pt(q=abs(t_stat_BHAR$CAPM), lower.tail = FALSE, df=(inital_df - 2)))) |>
  select(time_periods, ConstantModel, MarketModel, CAPM)

ggplot(data = abnormal_returns, aes(x = dates_relative)) +
  geom_line(aes(y = stock_return, color = time_period)) +
  geom_line(aes(y = bench_return, color = "black")) +
  labs(x = 'Trading Days Before Event', y = 'Realised Returns') +
  geom_vline(aes(xintercept = 0), linetype = 2) +
  scale_x_reverse()



ar_compare_models <- abnormal_returns |>
  pivot_longer(cols = c(ConstantModel, MarketModel, CAPM), names_to = 'model', values_to = 'value') |>
  select(date, dates_relative, model, value )

ggplot(ar_compare_models, aes(x = dates_relative)) +
  geom_line(aes(y= value, color = model)) +
  labs(x = 'Trading Days Before Event', y = 'Abnormal Returns') +
  geom_vline(aes(xintercept = 0), linetype = 2) +
  scale_x_reverse()



####################################################################################
# Calculate P values for each day with period
#abnormal_returns <- abnormal_returns |>
# pivot_longer(cols = c(ConstantModel, MarketModel, CAPM), names_to = 'model', values_to = 'value') |>
#mutate(t_stat = ifelse(model=="CAPM", (value/stdev_capm), ifelse(model=="MarketModel", (value/stdev_market),
#                                                                ifelse(model=="ConstantModel", (value/stdev_const), NA)))) |>
#mutate(p_val = ifelse(model=="CAPM", (2 * pt(q=abs(t_stat_CAR$ConstantModel), lower.tail = FALSE, df=(inital_df - 1))), 
#                                           ifelse(model=="MarketModel", (2 * pt(q=abs(t_stat_CAR$MarketModel), lower.tail = FALSE, df=(inital_df - 1))),
#                                                             ifelse(model=="ConstantModel", (2 * pt(q=abs(t_stat_CAR$CAPM), lower.tail = FALSE, df=(inital_df - 2))), NA))))

