@doc raw"""
	load_generators_variability!(setup::Dict, path::AbstractString, inputs::Dict)

Function for reading input parameters related to hourly maximum capacity factors for all generators (plus storage and flexible demand resources)
"""
function load_probability_distribution!(setup::Dict, path::AbstractString, inputs::Dict)

	# Hourly capacity factors
	data_directory = joinpath(path, setup["TimeDomainReductionFolder"])
    	if setup["TimeDomainReduction"] == 1  && time_domain_reduced_files_exist(data_directory)
        	my_dir = data_directory
	else
        	my_dir = path
	end

    	filename = "probability_distribution.csv"
	probability_distribution = load_dataframe(joinpath(my_dir, filename))
    
	# Maximum power output and variability of each energy resource
	inputs["scenprob"] = transpose(Matrix{Float64}(probability_distribution[1:inputs["T"],2:(inputs["SC"]+1)]))

    
	println(filename " Successfully Read!")

end
