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
function load_generators_variability!(setup::Dict, path::AbstractString, inputs::Dict)

	# Hourly capacity factors
	data_directory = joinpath(path, setup["TimeDomainReductionFolder"])
    	if setup["TimeDomainReduction"] == 1  && time_domain_reduced_files_exist(data_directory)
        	my_dir = data_directory
	else
        	my_dir = path
	end

    	filename = "Generators_variability_scenario_*.csv"
    	gen_var_files = glob(filename, my_dir)
	gen_var = DataFrame.(CSV.File.(gen_var_files))

	all_resources = inputs["RESOURCES"]

	
	for i in 1:length(gen_var)
		existing_variability = names(gen_var[i])
		for r in all_resources
			if r ∉ existing_variability
				@info "assuming availability of 1.0 for resource $r."
				ensure_column!(gen_var[i], r, 1.0)
	    		end
		end
		# Reorder DataFrame to R_ID order (order provided in Generators_data.csv)
		select!(gen_var[i], [:Time_Index; Symbol.(all_resources) ])
    
		# Maximum power output and variability of each energy resource
		inputs["pP_Max_scenario_$i"] = transpose(Matrix{Float64}(gen_var[i][1:inputs["T"],2:(inputs["G"]+1)]))
	end

    
	println(filename * " Successfully Read!")

end
