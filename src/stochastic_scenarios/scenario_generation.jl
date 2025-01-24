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




function generate_scenarios!(inpath::AbstractString, settings_path::AbstractString, mysetup, stage_id=-99, v=false)
	inputs = Dict()
	fuels_path = joinpath(inpath, "Fuels_data")
	load_path = joinpath(inpath, "Load_data")
	genvar_path = joinpath(inpath, "Generators_variability")
	FSC=length(filter!(file -> endswith(file, ".csv"),readdir(fuels_path)))
	WSC=length(filter!(file -> endswith(file, ".csv"),readdir(load_path)))#WSC always comes up as 1 more than the number of files or scenarios
	for fuelscen in 1:FSC 
		fuels_scen_df=DataFrame(CSV.File(joinpath(fuels_path, "Fuels_data_scenario_$fuelscen.csv"), header=true), copycols=true)
		for weatheryearscen in 1:WSC
			gen_var_scen_df=DataFrame(CSV.File(joinpath(genvar_path, "Generators_variability_scenario_$weatheryearscen.csv"), header=true), copycols=true)
			loadscen_df=DataFrame(CSV.File(joinpath(load_path, "Load_data_scenario_$weatheryearscen.csv"), header=true), copycols=true)
			#combined_time_series=hcat(fuels_scen_df, gen_var_scen_df, loadscen_df, makeunique=true)
		end
	end

	calculate_joint_probabilities!(inpath, settings_path, mysetup, inputs, FSC, WSC)

	return FSC, WSC, FSC*WSC, inputs
end

function calculate_joint_probabilities!(inpath::AbstractString, settings_path::AbstractString, mysetup, inputs::Dict, FSC::Int64, WSC::Int64, stage_id=-99, v=false)
	fuel_probability_df=DataFrame(CSV.File(joinpath(inpath, "probability_distribution_fuel.csv"), header=true), copycols=true)
	weather_probability_df=DataFrame(CSV.File(joinpath(inpath, "probability_distribution_weather.csv"), header=true), copycols=true)
	joint_probability_df=DataFrame()
	joint_probability=zeros(FSC*WSC,1)
	for fuelscen in 1:FSC
		for weatheryearscen in 1:WSC
			joint_probability_df[!, Symbol("Joint_Prob_$(fuelscen)_$(weatheryearscen)")] = fuel_probability_df[!, fuelscen] .* weather_probability_df[!, weatheryearscen]
			joint_probability[(fuelscen-1)*WSC+weatheryearscen]=joint_probability_df[!, Symbol("Joint_Prob_$(fuelscen)_$(weatheryearscen)")][1]
		end
	end
	inputs["scenprob"]=joint_probability
end