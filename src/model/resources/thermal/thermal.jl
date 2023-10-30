@doc raw"""
	thermal!(EP::Model, inputs::Dict, setup::Dict)
The thermal module creates decision variables, expressions, and constraints related to thermal power plants e.g. coal, oil or natural gas steam plants, natural gas combined cycle and combustion turbine plants, nuclear, hydrogen combustion etc.
This module uses the following 'helper' functions in separate files: ```thermal_commit()``` for thermal resources subject to unit commitment decisions and constraints (if any) and ```thermal_no_commit()``` for thermal resources not subject to unit commitment (if any).
"""
function thermal!(EP::Model, inputs::Dict, setup::Dict, number_of_scenarios::Int64)
	dfGen = inputs["dfGen"]

	T = inputs["T_scenario_1"]     # Number of time steps (hours)
	Z = inputs["Z"]     # Number of zones
	SC = number_of_scenarios   # Number of scenarios

	THERM_COMMIT = inputs["THERM_COMMIT"]
	THERM_NO_COMMIT = inputs["THERM_NO_COMMIT"]
	THERM_ALL = inputs["THERM_ALL"]

	dfGen = inputs["dfGen"]

	if !isempty(THERM_COMMIT)
		thermal_commit!(EP, inputs, setup, number_of_scenarios)
	end

	if !isempty(THERM_NO_COMMIT)
		thermal_no_commit!(EP, inputs, setup)
	end
	##CO2 Polcy Module Thermal Generation by zone
	@expression(EP, eGenerationByThermAll[z=1:Z, t=1:T, sc=1:SC], # the unit is GW
		sum(EP[:vP][y,t,sc] for y in intersect(inputs["THERM_ALL"], dfGen[dfGen[!,:Zone].==z,:R_ID]))
	)
	EP[:eGenerationByZone] += eGenerationByThermAll

	# Capacity Reserves Margin policy
	if setup["CapacityReserveMargin"] > 0
		@expression(EP, eCapResMarBalanceThermal[res=1:inputs["NCapacityReserveMargin"], t=1:T, sc=1:SC], sum(dfGen[y,Symbol("CapRes_$res")] * EP[:eTotalCap][y] for y in THERM_ALL))
		EP[:eCapResMarBalance] += eCapResMarBalanceThermal
	end
end
