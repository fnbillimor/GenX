@doc raw"""
	discharge!(EP::Model, inputs::Dict, setup::Dict)
This module defines the power decision variable $\Theta_{y,t,sc} \forall y \in \mathcal{G}, t \in \mathcal{T}$, sc \in \mathcal{SC} representing energy injected into the grid by resource $y$ by at time period $t$ and scenario $sc$.
This module additionally defines contributions to the objective function from variable costs of generation (variable O&M plus fuel cost) from all resources $y \in \mathcal{G}$ over all time periods $t \in \mathcal{T}$ and scenario $sc \in \mathcal{SC}$:
```math
\begin{aligned}
	Obj_{Var\_gen, sc} =
	\mathcal{PR}_{sc}\times\sum_{y \in \mathcal{G} } \sum_{t \in \mathcal{T}}\omega_{t,sc}\times(\pi^{VOM}_{y} + \pi^{FUEL}_{y})\times \Theta_{y,t,sc}
\end{aligned}
```
"""
function discharge!(EP::Model, inputs::Dict, setup::Dict, number_of_scenarios::Int64)

	println("Discharge Module")

	dfGen = inputs["dfGen"]

	G = inputs["G"]     # Number of resources (generators, storage, DR, and DERs)
	T = inputs["T_scenario_1"]     # Number of time steps
	Z = inputs["Z"]	    # Number of zones
	SC = number_of_scenarios   # Number of scenarios
	### Variables ###

	# Energy injected into the grid by resource "y" at hour "t" in scenario "sc"
	@variable(EP, vP[y=1:G,t=1:T,sc=1:SC] >=0);

	### Expressions ###

	## Objective Function Expressions ##

	# Variable costs of "generation" for resource "y" during hour "t" in scenario "sc"= variable O&M plus fuel cost
	@expression(EP, eCVar_out[y=1:G,t=1:T,sc=1:SC], (inputs["omega_scenario_$sc"][t]*(dfGen[y,:Var_OM_Cost_per_MWh]+inputs["C_Fuel_per_MWh"][y,t,sc])*vP[y,t,sc]))
	#@expression(EP, eCVar_out[y=1:G,t=1:T], (round(inputs["omega"][t,sc]*(dfGen[y,:Var_OM_Cost_per_MWh]+inputs["C_Fuel_per_MWh"][y,t]), digits=RD)*vP[y,t]))
	# Sum individual resource contributions to variable discharging costs to get total variable discharging costs
	@expression(EP, eTotalCVarOutTSC[t=1:T,sc=1:SC], sum(eCVar_out[y,t,sc] for y in 1:G))
	@expression(EP, eTotalCVarOutT[sc=1:SC], sum(eTotalCVarOutTSC[t,sc] for t in 1:T))

	# Add total variable discharging cost contribution to the objective function
	EP[:eSCS] += eTotalCVarOutT

	# ESR Policy
	if setup["EnergyShareRequirement"] >= 1
		
		@expression(EP, eESRDischarge[ESR=1:inputs["nESR"],sc=1:SC], sum(inputs["omega_scenario_$sc"][t]*dfGen[y,Symbol("ESR_$ESR")]*EP[:vP][y,t,sc] for y=dfGen[findall(x->x>0,dfGen[!,Symbol("ESR_$ESR")]),:R_ID], t=1:T)
						- sum(inputs["dfESR"][z,ESR]*inputs["omega_scenario_$sc"][t]*inputs["pD_scenario_$sc"][t,z] for t=1:T, z=findall(x->x>0,inputs["dfESR"][:,ESR])))

		EP[:eESR] += eESRDischarge
	end
	
end
