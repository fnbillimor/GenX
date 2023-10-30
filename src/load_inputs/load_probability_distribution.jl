@doc raw"""
	load_generators_variability!(setup::Dict, path::AbstractString, inputs::Dict)

Function for reading input parameters related to hourly maximum capacity factors for all generators (plus storage and flexible demand resources)
"""
function load_probability_distribution!(setup::Dict, path::AbstractString, inputs::Dict, scenario_num::Int64)

	#=# Hourly capacity factors
	data_directory = joinpath(path, setup["TimeDomainReductionFolder"])
    	if setup["TimeDomainReduction"] == 1  && time_domain_reduced_files_exist(data_directory)
        	my_dir = data_directory
	else
        	my_dir = path
	end
	=#
	my_dir = path
    	filename = "probability_distribution.csv"
	probability_distribution = load_dataframe(joinpath(my_dir, filename))
    
	# Maximum power output and variability of each energy resource
	scenprob=extract_matrix_from_dataframe(probability_distribution, "scenario")
	inputs["scenprob"] = scenprob
    
	println(filename, " Successfully Read!")

end
