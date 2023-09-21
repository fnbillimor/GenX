@doc raw"""
	load_period_map!(setup::Dict, path::AbstractString, inputs::Dict)

Read input parameters related to mapping of representative time periods to full chronological time series
"""
function load_period_map!(setup::Dict, path::AbstractString, inputs::Dict, sc::Int64)
	period_map = "Period_map_scenario_$sc.csv"
	data_directory = joinpath(path, setup["TimeDomainReductionFolder"], "Period_map")
	if setup["TimeDomainReduction"] == 1 && isfile(joinpath(data_directory, period_map))  # Use Time Domain Reduced data for GenX
		my_dir = data_directory
	else
		my_dir = joinpath(path, "Period_map")
	end
	file_path = joinpath(my_dir, period_map)
    	inputs["Period_Map_scenario_$sc"] = load_dataframe(file_path)

	println(period_map * " Successfully Read!")
end
