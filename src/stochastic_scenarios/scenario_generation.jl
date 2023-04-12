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

function generate_scenarios(inpath::AbstractString, settings_path::AbstractString, mysetup, stage_id=-99, v=false)

	for fuelscen in 1:FSC 
		for genscen in 1:GSC 
			for loadscen in 1:LSC 
				fuels_scen_df=DataFrame(CSV.File(joinpath(fuels_path, "Fuels_data_scenario_$fuelscen.csv"), header=true) copycols=true)
				gen_var_scen_df=DataFrame(CSV.File(joinpath(genvar_path, "Generators_variability_scenario_$genscen.csv"), header=true) copycols=true)
				loadscen_df=DataFrame(CSV.File(joinpath(load_path, "Load_data_scenario_$loadscen.csv"), header=true) copycols=true)
				combined_time_series=hcat(fuels_scen_df, gen_var_df, loadscen_df)
			end
		end
	end
end