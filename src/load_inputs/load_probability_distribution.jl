"""
GenX: An Configurable Capacity Expansion Model
Copyright (C) 2021,  Massachusetts Institute of Technology
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
A complete copy of the GNU General Public License v2 (GPLv2) is available
in LICENSE.txt.  Users uncompressing this from an archive may not have
received this license file.  If not, see <http://www.gnu.org/licenses/>.
"""

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
