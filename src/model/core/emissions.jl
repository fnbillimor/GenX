@doc raw"""
	emissions!(EP::Model, inputs::Dict)

This function creates expression to add the CO2 emissions by plants in each zone, which is subsequently added to the total emissions
"""
function emissions!(EP::Model, inputs::Dict, number_of_scenarios::Int64)

	println("Emissions Module (for CO2 Policy modularization)")

	dfGen = inputs["dfGen"]

	G = inputs["G"]     # Number of resources (generators, storage, DR, and DERs)
	T = inputs["T_scenario_1"]     # Number of time steps (hours)
	Z = inputs["Z"]     # Number of zones
	SC = number_of_scenarios # Number of scenarios
	@expression(EP, eEmissionsByPlant[y=1:G,t=1:T, sc=1:SC],

		if y in inputs["COMMIT"]
			dfGen[y,:CO2_per_MWh]*EP[:vP][y,t,sc]+dfGen[y,:CO2_per_Start]*EP[:vSTART][y,t,sc]
		else
			dfGen[y,:CO2_per_MWh]*EP[:vP][y,t,sc]
		end
	)
	@expression(EP, eEmissionsByZone[z=1:Z, t=1:T, sc=1:SC], sum(eEmissionsByPlant[y,t,sc] for y in dfGen[(dfGen[!,:Zone].==z),:R_ID]))

end
