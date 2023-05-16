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
	load_data(setup::Dict, path::AbstractString, inputs_load::Dict)

Function for reading input parameters related to electricity load (demand)
"""
function load_load_data(setup::Dict, path::AbstractString, inputs_load::Dict)
	# Load related inputs
	data_directory = joinpath(path, setup["TimeDomainReductionFolder"])
    	if setup["TimeDomainReduction"] == 1  && time_domain_reduced_files_exist(data_directory)
       		my_dir = data_directory
	else
        	my_dir = path
	end
    	filename = "Load_data_scenario_*.csv"
	load_files = glob(filename, my_dir)
	load_in = DataFrame.(CSV.File.(load_files))
	for i in 1:length(load_in)
		as_vector(col::Symbol) = collect(skipmissing(load_in[i][!, col]))

		# Number of time steps (periods)
    		T = length(as_vector(:Time_Index))
		# Number of demand curtailment/lost load segments
    		SEG = length(as_vector(:Demand_Segment))

		## Set indices for internal use
    		inputs["T_scenario_$i"] = T
    		inputs["SEG_scenario_$i"] = SEG
		Z = inputs["Z"]   # Number of zones

		inputs["omega_scenario_$i"] = zeros(Float64, T) # weights associated with operational sub-period in the model - sum of weight = 8760
    		# Weights for each period - assumed same weights for each sub-period within a period
    		inputs["Weights_scenario_$i"] = as_vector(:Sub_Weights) # Weights each period

    		# Total number of periods and subperiods
    		inputs["REP_PERIOD_scenario_$i"] = convert(Int16, as_vector(:Rep_Periods)[1])
    		inputs["H_scenario_$i"] = convert(Int64, as_vector(:Timesteps_per_Rep_Period)[1])

    		# Creating sub-period weights from weekly weights
    		for w in 1:inputs["REP_PERIOD_scenario_$i"]
        		for h in 1:inputs["H_scenario_$i"]
            			t = inputs["H_scenario_$i"]*(w-1)+h
            			inputs["omega_scenario_$i"][t] = inputs["Weights_scenario_$i"][w]/inputs["H_scenario_$i"]
        		end
    		end

		# Create time set steps indicies
		inputs["hours_per_subperiod_scenario_$i"] = div.(T,inputs["REP_PERIOD_scenario_$i"]) # total number of hours per subperiod
		hours_per_subperiod = inputs["hours_per_subperiod_scenario_$i"] # set value for internal use

		inputs["START_SUBPERIODS_scenario_$i"] = 1:hours_per_subperiod:T 	# set of indexes for all time periods that start a subperiod (e.g. sample day/week)
		inputs["INTERIOR_SUBPERIODS_scenario_$i"] = setdiff(1:T, inputs["START_SUBPERIODS_scenario_$i"]) # set of indexes for all time periods that do not start a subperiod

		# Demand in MW for each zone
		#println(names(load_in))
		start = findall(s -> s == "Load_MW_z1", names(load_in[i]))[1] #gets the starting column number of all the columns, with header "Load_MW_z1"
    		scale_factor = setup["ParameterScale"] == 1 ? ModelScalingFactor : 1
    		# Max value of non-served energy
    		inputs["Voll_scenario_$i"] = as_vector(:Voll) / scale_factor # convert from $/MWh $ million/GWh (assuming objective is divided by 1000)
    		# Demand in MW
    		inputs["pD_scenario_$i"] =Matrix(load_in[i][1:T, start:start+Z-1]) / scale_factor  # convert to GW

		# Cost of non-served energy/demand curtailment
    		# Cost of each segment reported as a fraction of value of non-served energy - scaled implicitly
    		inputs["pC_D_Curtail_scenario_$i"] = as_vector(:Cost_of_Demand_Curtailment_per_MW) * inputs["Voll_scenario_$i"][1]
    		# Maximum hourly demand curtailable as % of the max demand (for each segment)
    		inputs["pMax_D_Curtail_scenario_$i"] = as_vector(:Max_Demand_Curtailment)
	end

	println(filename * " Successfully Read!")
end

# ensure that the length of load data exactly matches
# the number of subperiods times their length
# and that the number of subperiods equals the list of provided weights
function validatetimebasis(inputs::Dict)
	println("Validating time basis")
	demand_length = size(inputs["pD"], 1)
	generators_variability_length = size(inputs["pP_Max"], 2)
    
	typical_fuel = first(inputs["fuels"])
	fuel_costs_length = size(inputs["fuel_costs"][typical_fuel], 1)
    
	T = inputs["T"]
	hours_per_subperiod = inputs["hours_per_subperiod"]
	number_of_representative_periods = inputs["REP_PERIOD"]
	expected_length_1 = hours_per_subperiod * number_of_representative_periods
    
	H = inputs["H"]
	expected_length_2 = H * number_of_representative_periods
    
	check_equal = [T,
		       demand_length,
		       generators_variability_length,
		       fuel_costs_length,
		       expected_length_1,
		       expected_length_2]
    
	allequal(x) = all(y->y==x[1], x)
	ok = allequal(check_equal)
    
	if ~ok
	    error("""Critical error in time series construction:
		     lengths of the various time series, and/or the expected
		     total length based on the number of representative periods and their length,
		     are not all equal.
    
		     Expected length:                    $T
			 (set by the Time index in demand_data.csv [or load_data.csv])
		     Demand series length:               $demand_length
			 (demand_data.csv [or load_data.csv])
		     Resource time profiles length:      $generators_variability_length
			 (generators_variability.csv)
		     Fuel costs length:                  $fuel_costs_length
			 (fuels_data.csv)
    
		     Metrics from demand_data.csv [load_data.csv]:
		     Detected time steps:            $T
		     No. of representative periods:  $number_of_representative_periods
			 Euclidean quotient of these:    $hours_per_subperiod
    
		     No. of representative periods:  $number_of_representative_periods
		     Time steps per rep. period:     $H
			 Product of these:               $expected_length_2
		  """)
	end
    
	if "Weights" in keys(inputs)
	    weights = inputs["Weights"]
	    num_weights = length(weights)
	    if num_weights != number_of_representative_periods
		error("""Critical error in time series construction:
		      In demand_data.csv [or load_data.csv],
		      the number of subperiod weights ($num_weights) does not match
		      the expected number of representative periods, ($number_of_representative_periods).""")
	    end
	end
end
    
    
@doc raw"""
prevent_doubled_timedomainreduction(path::AbstractString)
    
This function prevents TimeDomainReduction from running on a case which
already has more than one Representative Period or has more than one Sub_Weight specified.
"""
function prevent_doubled_timedomainreduction(path::AbstractString)
    
	filename = "Load_data.csv"
	load_in = load_dataframe(joinpath(path, filename))
	as_vector(col::Symbol) = collect(skipmissing(load_in[!, col]))
	representative_periods = convert(Int16, as_vector(:Rep_Periods)[1])
	sub_weights = as_vector(:Sub_Weights)
	num_sub_weights = length(sub_weights)
	if representative_periods != 1 || num_sub_weights > 1
	    error("""Critical error in time series construction:
		  Time domain reduction (clustering) is being called for,
		  on data which may already be clustered. In demand_data.csv [or load_data.csv],
		  the number of representative periods (:Rep_Period) is ($representative_periods)
		  and the number of subperiod weight entries (:Sub_Weights) is ($num_sub_weights).
		  Each of these must be 1: only a single period can have TimeDomainReduction applied.""")
	end
    
end
    