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
	load_fuels_data(setup::Dict, path::AbstractString, inputs_fuel::Dict)

Function for reading input parameters related to fuel costs and CO$_2$ content of fuels
"""
function load_fuels_data(setup::Dict, path::AbstractString, inputs_fuel::Dict)

	# Fuel related inputs - read in different files depending on if time domain reduction is activated or not
	data_directory = joinpath(path, setup["TimeDomainReductionFolder"])
	if setup["TimeDomainReduction"] == 1  && time_domain_reduced_files_exist(data_directory)
		my_dir = data_directory
	else
		my_dir = path
	end
	filename = "Fuels_data_scenario_*.csv"
	fuels_files = glob(filename, my_dir)
	fuels_in = DataFrame.(CSV.File.(fuels_files))
	
	
	for i in 1:length(fuels_in)
		existing_fuels = names(fuels_in[i])
		for nonfuel in ("None",)
			if nonfuel ∉ existing_fuels
		    		ensure_column!(fuels_in[i], nonfuel, 0.0)
			end
		end

	    	# Fuel costs & CO2 emissions rate for each fuel type
	    	fuels = names(fuels_in[i])[2:end]
	    	costs = Matrix(fuels_in[i][2:end, 2:end])
	    	CO2_content = fuels_in[i][1, 2:end] # tons CO2/MMBtu
	    	fuel_costs = Dict{AbstractString, Array{Float64}}()
	    	fuel_CO2 = Dict{AbstractString, Float64}()
	
	    	scale_factor = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1
	
	    	for j = 1:length(fuels)
		    fuel_costs[fuels[j]] = costs[:,j] / scale_factor
		    # fuel_CO2 is kton/MMBTU with scaling, or ton/MMBTU without scaling.
		    fuel_CO2[fuels[j]] = CO2_content[j] / scale_factor
	    	end
	
	    	inputs["fuels_scenario_$i"] = fuels
	    	inputs["fuel_costs_scenario_$i"] = fuel_costs
	    	inputs["fuel_CO2_scenario_$i"] = fuel_CO2
	
	    	println(filename * " Successfully Read!")
	
	    	return fuel_costs, fuel_CO2
	end
end
	
function ensure_column!(df::DataFrame, col::AbstractString, fill_element)
	if col ∉ names(df)
		df[!, col] = fill(fill_element, nrow(df))
	end
end
