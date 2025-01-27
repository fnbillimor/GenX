using CSV, DataFrames, Dates, TimeSeries, Statistics
using StatsBase, LinearAlgebra
using Plots
using HypothesisTests
using Distributions
using Optim

# Function to read and preprocess data
function read_and_preprocess_data(filenames)
    data = DataFrame()
    for filename in filenames
        df = CSV.read(filename, DataFrame, header=false) # Adjust header if needed
        rename!(df, [:Value]) # Assuming only one column of values
        if isempty(data)
            data = df
        else
            append!(data, df)
        end
    end
    return data[:Value] # Return the values as a vector
end

# Function to perform time series analysis and forecasting
function forecast_timeseries(data, forecast_length=8760)
    # Convert data to TimeArray for easier time series handling
    time_index = DateTime(2001, 1, 1, 1):Hour(1):DateTime(2022 + 1, 1, 1, 0) #Creates a time index from 2001 to 2023
    ts = TimeArray(time_index, data)

    # Decompose the time series into trend, seasonality, and residuals
    decomp = decompose(ts, period = 8760) # Yearly Seasonality

    # Fit ARMA model to residuals
    residuals = decomp.resid
    # Find optimal (p,q) ARMA order
    best_aic = Inf
    best_order = (0,0)
    for p in 0:5
        for q in 0:5
            try
                model = fit(ARMA{p,q}, residuals.Value)
                if aic(model) < best_aic
                    best_aic = aic(model)
                    best_order = (p,q)
                end
            catch
                continue
            end
        end
    end
    println("Best ARMA order: ", best_order)
    arma_model = fit(ARMA{best_order[1], best_order[2]}, residuals.Value)
    arma_forecast = forecast(arma_model, forecast_length)

    # Forecast the trend (Can be improved with more sophisticated methods)
    trend_forecast = repeat(last(decomp.trend.Value, 1), forecast_length) # Simple last value carry forward

    # Forecast the seasonality (Repeat last year's seasonality)
    seasonal_forecast = repeat(last(decomp.seasonal.Value, 8760), 1)

    # Combine forecasts
    forecast_values = trend_forecast .+ seasonal_forecast .+ arma_forecast
    forecast_time_index = DateTime(2023, 1, 1, 1):Hour(1):DateTime(2024, 1, 1, 0)
    forecast_ts = TimeArray(forecast_time_index, forecast_values)

    return forecast_ts, decomp # Return the TimeArray and the decomposition for further analysis
end

# Example usage
