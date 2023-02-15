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
	storage_all!(EP::Model, inputs::Dict, setup::Dict)

Sets up variables and constraints common to all storage resources. See ```storage()``` in ```storage.jl``` for description of constraints.
"""
function storage_all!(EP::Model, inputs::Dict, setup::Dict)
	# Setup variables, constraints, and expressions common to all storage resources
	println("Storage Core Resources Module")

	dfGen = inputs["dfGen"]
	Reserves = setup["Reserves"]
	OperationWrapping = setup["OperationWrapping"]

	G = inputs["G"]     # Number of resources (generators, storage, DR, and DERs)
	T = inputs["T"]     # Number of time steps (hours)
	Z = inputs["Z"]     # Number of zones
	SC = inputs["SC"]   # Number of scenarios
	STOR_ALL = inputs["STOR_ALL"]
	STOR_SHORT_DURATION = inputs["STOR_SHORT_DURATION"]

	START_SUBPERIODS = inputs["START_SUBPERIODS"]
	INTERIOR_SUBPERIODS = inputs["INTERIOR_SUBPERIODS"]

	hours_per_subperiod = inputs["hours_per_subperiod"] #total number of hours per subperiod

	### Variables ###

	# Storage level of resource "y" at hour "t" [MWh] on zone "z" - unbounded
	@variable(EP, vS[y in STOR_ALL, t=1:T, sc=1:SC] >= 0);

	# Energy withdrawn from grid by resource "y" at hour "t" [MWh] on zone "z"
	@variable(EP, vCHARGE[y in STOR_ALL, t=1:T, sc=1:SC] >= 0);

	### Expressions ###

	# Energy losses related to technologies (increase in effective demand)
	@expression(EP, eELOSS[y in STOR_ALL, sc in 1:SC], sum(inputs["scenprob"][sc]*inputs["omega"][t]*EP[:vCHARGE][y,t,sc] for t in 1:T) - sum(inputs["scenprob"][sc]*inputs["omega"][t]*EP[:vP][y,t,sc] for t in 1:T))

	## Objective Function Expressions ##

	#Variable costs of "charging" for technologies "y" during hour "t" in zone "z"
	@expression(EP, eCVar_in[y in STOR_ALL,t=1:T, sc=1:SC], inputs["scenprob"][sc]*inputs["omega"][t]*dfGen[y,:Var_OM_Cost_per_MWh_In]*vCHARGE[y,t,sc])

	# Sum individual resource contributions to variable charging costs to get total variable charging costs
	@expression(EP, eTotalCVarInT[t=1:T, sc=1:SC], sum(eCVar_in[y,t,sc] for y in STOR_ALL))
	@expression(EP, eTotalCVarIn[sc=1:SC], sum(eTotalCVarInT[t,sc] for t in 1:T))
	@expression(EP, eTotalCVarInSC, sum(eTotalCVarInT[sc] for sc in 1:SC))
	EP[:eObj] += eTotalCVarInSC

	## Power Balance Expressions ##

	# Term to represent net dispatch from storage in any period
	@expression(EP, ePowerBalanceStor[t=1:T, z=1:Z, sc=1:SC],
		sum(EP[:vP][y,t,sc]-EP[:vCHARGE][y,t,sc] for y in intersect(dfGen[dfGen.Zone.==z,:R_ID],STOR_ALL)))

	EP[:ePowerBalance] += ePowerBalanceStor

	### Constraints ###

	## Storage energy capacity and state of charge related constraints:

	# Links state of charge in first time step with decisions in last time step of each subperiod
	# We use a modified formulation of this constraint (cSoCBalLongDurationStorageStart) when operations wrapping and long duration storage are being modeled
	
	if OperationWrapping ==1 && !isempty(inputs["STOR_LONG_DURATION"])
		@constraint(EP, cSoCBalStart[t in START_SUBPERIODS, y in STOR_SHORT_DURATION,sc=1:SC], EP[:vS][y,t,sc] ==
			EP[:vS][y,t+hours_per_subperiod-1,sc]-(1/dfGen[y,:Eff_Down]*EP[:vP][y,t,sc])
			+(dfGen[y,:Eff_Up]*EP[:vCHARGE][y,t,sc])-(dfGen[y,:Self_Disch]*EP[:vS][y,t+hours_per_subperiod-1,sc]))
	else
		@constraint(EP, cSoCBalStart[t in START_SUBPERIODS, y in STOR_ALL,sc=1:SC], EP[:vS][y,t,sc] ==
			EP[:vS][y,t+hours_per_subperiod-1,sc]-(1/dfGen[y,:Eff_Down]*EP[:vP][y,t,sc])
			+(dfGen[y,:Eff_Up]*EP[:vCHARGE][y,t,sc])-(dfGen[y,:Self_Disch]*EP[:vS][y,t+hours_per_subperiod-1,sc]))
	end
	

	@constraints(EP, begin

		# Max and min constraints on energy storage capacity built (as proportion to discharge power capacity)
		[y in STOR_ALL], EP[:eTotalCapEnergy][y] >= dfGen[y,:Min_Duration] * EP[:eTotalCap][y]
		[y in STOR_ALL], EP[:eTotalCapEnergy][y] <= dfGen[y,:Max_Duration] * EP[:eTotalCap][y]

		# Maximum energy stored must be less than energy capacity
		[y in STOR_ALL, t in 1:T,sc=1:SC], EP[:vS][y,t,sc] <= EP[:eTotalCapEnergy][y]

		# energy stored for the next hour
		cSoCBalInterior[t in INTERIOR_SUBPERIODS, y in STOR_ALL,sc=1:SC], EP[:vS][y,t,sc] ==
			EP[:vS][y,t-1,sc]-(1/dfGen[y,:Eff_Down]*EP[:vP][y,t,sc])+(dfGen[y,:Eff_Up]*EP[:vCHARGE][y,t,sc])-(dfGen[y,:Self_Disch]*EP[:vS][y,t-1,sc])
	end)

	# Storage discharge and charge power (and reserve contribution) related constraints:
	if Reserves == 1
		storage_all_reserves!(EP, inputs)
	else
		# Note: maximum charge rate is also constrained by maximum charge power capacity, but as this differs by storage type,
		# this constraint is set in functions below for each storage type

		# Maximum discharging rate must be less than power rating OR available stored energy in the prior period, whichever is less
		# wrapping from end of sample period to start of sample period for energy capacity constraint
		@constraints(EP, begin
			[y in STOR_ALL, t=1:T,sc=1:SC], EP[:vP][y,t,sc] <= EP[:eTotalCap][y]
			[y in STOR_ALL, t in INTERIOR_SUBPERIODS,sc=1:SC], EP[:vP][y,t,sc] <= EP[:vS][y,t-1,sc]*dfGen[y,:Eff_Down]
			[y in STOR_ALL, t in START_SUBPERIODS,sc=1:SC], EP[:vP][y,t,sc] <= EP[:vS][y,t+hours_per_subperiod-1,sc]*dfGen[y,:Eff_Down]
		end)
	end
	#From co2 Policy module
	@expression(EP, eELOSSByZone[z=1:Z,sc=1:SC],
		sum(EP[:eELOSS][y,sc] for y in intersect(inputs["STOR_ALL"], dfGen[dfGen[!,:Zone].==z,:R_ID]))
	)
end

function storage_all_reserves!(EP::Model, inputs::Dict)

	dfGen = inputs["dfGen"]
	T = inputs["T"]
	SC = inputs["SC"]   # Number of scenarios
	START_SUBPERIODS = inputs["START_SUBPERIODS"]
	INTERIOR_SUBPERIODS = inputs["INTERIOR_SUBPERIODS"]
	hours_per_subperiod = inputs["hours_per_subperiod"]

	STOR_ALL = inputs["STOR_ALL"]

	STOR_REG_RSV = intersect(STOR_ALL, inputs["REG"], inputs["RSV"]) # Set of storage resources with both REG and RSV reserves

	STOR_REG = intersect(STOR_ALL, inputs["REG"]) # Set of storage resources with REG reserves
	STOR_RSV = intersect(STOR_ALL, inputs["RSV"]) # Set of storage resources with RSV reserves

	STOR_NO_RES = setdiff(STOR_ALL, STOR_REG, STOR_RSV) # Set of storage resources with no reserves

	STOR_REG_ONLY = setdiff(STOR_REG, STOR_RSV) # Set of storage resources only with REG reserves
	STOR_RSV_ONLY = setdiff(STOR_RSV, STOR_REG) # Set of storage resources only with RSV reserves

	if !isempty(STOR_REG_RSV)
		# Storage units charging can charge faster to provide reserves down and charge slower to provide reserves up
		@constraints(EP, begin
			# Maximum storage contribution to reserves is a specified fraction of installed discharge power capacity
			[y in STOR_REG_RSV, t=1:T, sc=1:SC], EP[:vREG][y,t,sc] <= dfGen[y,:Reg_Max]*EP[:eTotalCap][y]
			[y in STOR_REG_RSV, t=1:T, sc=1:SC], EP[:vRSV][y,t,sc] <= dfGen[y,:Rsv_Max]*EP[:eTotalCap][y]

			# Actual contribution to regulation and reserves is sum of auxilary variables for portions contributed during charging and discharging
			[y in STOR_REG_RSV, t=1:T, sc=1:SC], EP[:vREG][y,t,sc] == EP[:vREG_charge][y,t,sc]+EP[:vREG_discharge][y,t,sc]
			[y in STOR_REG_RSV, t=1:T, sc=1:SC], EP[:vRSV][y,t,sc] == EP[:vRSV_charge][y,t,sc]+EP[:vRSV_discharge][y,t,sc]

			# Maximum charging rate plus contribution to reserves up must be greater than zero
			# Note: when charging, reducing charge rate is contributing to upwards reserve & regulation as it drops net demand
			[y in STOR_REG_RSV, t=1:T, sc=1:SC], EP[:vCHARGE][y,t,sc]-EP[:vREG_charge][y,t,sc]-EP[:vRSV_charge][y,t,sc] >= 0

			# Maximum discharging rate and contribution to reserves down must be greater than zero
			# Note: when discharging, reducing discharge rate is contributing to downwards regulation as it drops net supply
			[y in STOR_REG_RSV, t=1:T, sc=1:SC], EP[:vP][y,t,sc]-EP[:vREG_discharge][y,t,sc] >= 0

			# Maximum charging rate plus contribution to regulation down must be less than available storage capacity
			## Made change to let the model run and not have key error issue for time -Sam (04/20/2021)
			[y in STOR_REG_RSV, t in START_SUBPERIODS, sc=1:SC], EP[:vCHARGE][y,t,sc]+EP[:vREG_charge][y,t,sc] <= EP[:eTotalCapEnergy][y]-EP[:vS][y,t+hours_per_subperiod-1,sc]
			[y in STOR_REG_RSV, t in INTERIOR_SUBPERIODS, sc=1:SC], EP[:vCHARGE][y,t,sc]+EP[:vREG_charge][y,t,sc] <= EP[:eTotalCapEnergy][y]-EP[:vS][y,t-1,sc]
			# Note: maximum charge rate is also constrained by maximum charge power capacity, but as this differs by storage type,
			# this constraint is set in functions below for each storage type

			# Maximum discharging rate and contribution to reserves up must be less than power rating OR available stored energy in prior period, whichever is less
			# wrapping from end of sample period to start of sample period for energy capacity constraint
			[y in STOR_REG_RSV, t=1:T, sc=1:SC], EP[:vP][y,t,sc]+EP[:vREG_discharge][y,t,sc]+EP[:vRSV_discharge][y,t,sc] <= EP[:eTotalCap][y]
			[y in STOR_REG_RSV, t in INTERIOR_SUBPERIODS, sc=1:SC], EP[:vP][y,t,sc]+EP[:vREG_discharge][y,t,sc]+EP[:vRSV_discharge][y,t,sc] <= EP[:vS][y,t-1,sc]
			[y in STOR_REG_RSV, t in START_SUBPERIODS, sc=1:SC], EP[:vP][y,t,sc]+EP[:vREG_discharge][y,t,sc]+EP[:vRSV_discharge][y,t,sc] <= EP[:vS][y,t+hours_per_subperiod-1,sc]
		end)
	end
	if !isempty(STOR_REG_ONLY)
		# Storage units charging can charge faster to provide reserves down and charge slower to provide reserves up
		@constraints(EP, begin
			# Maximum storage contribution to reserves is a specified fraction of installed capacity
			[y in STOR_REG_ONLY, t=1:T, sc=1:SC], EP[:vREG][y,t,sc] <= dfGen[y,:Reg_Max]*EP[:eTotalCap][y]

			# Actual contribution to regulation and reserves is sum of auxilary variables for portions contributed during charging and discharging
			[y in STOR_REG_ONLY, t=1:T, sc=1:SC], EP[:vREG][y,t,sc] == EP[:vREG_charge][y,t,sc]+EP[:vREG_discharge][y,t,sc]

			# Maximum charging rate plus contribution to reserves up must be greater than zero
			# Note: when charging, reducing charge rate is contributing to upwards reserve & regulation as it drops net demand
			[y in STOR_REG_ONLY, t=1:T, sc=1:SC], EP[:vCHARGE][y,t,sc]-EP[:vREG_charge][y,t,sc] >= 0

			# Maximum discharging rate and contribution to reserves down must be greater than zero
			# Note: when discharging, reducing discharge rate is contributing to downwards regulation as it drops net supply
			[y in STOR_REG_ONLY, t=1:T, sc=1:SC], EP[:vP][y,t,sc] - EP[:vREG_discharge][y,t,sc] >= 0

			# Maximum charging rate plus contribution to regulation down must be less than available storage capacity
			[y in STOR_REG_ONLY, t in START_SUBPERIODS, sc=1:SC], EP[:vCHARGE][y,t,sc]+EP[:vREG_charge][y,t,sc] <= EP[:eTotalCapEnergy][y]-EP[:vS][y,t+hours_per_subperiod-1,sc]
			[y in STOR_REG_ONLY, t in INTERIOR_SUBPERIODS, sc=1:SC], EP[:vCHARGE][y,t,sc]+EP[:vREG_charge][y,t,sc] <= EP[:eTotalCapEnergy][y]-EP[:vS][y,t-1,sc]
			# Note: maximum charge rate is also constrained by maximum charge power capacity, but as this differs by storage type,
			# this constraint is set in functions below for each storage type

			# Maximum discharging rate and contribution to reserves up must be less than power rating OR available stored energy in prior period, whichever is less
			# wrapping from end of sample period to start of sample period for energy capacity constraint
			[y in STOR_REG_ONLY, t=1:T, sc=1:SC], EP[:vP][y,t,sc] + EP[:vREG_discharge][y,t,sc] <= EP[:eTotalCap][y]
			[y in STOR_REG_ONLY, t in INTERIOR_SUBPERIODS, sc=1:SC], EP[:vP][y,t,sc]+EP[:vREG_discharge][y,t,sc] <= EP[:vS][y,t-1,sc]
			[y in STOR_REG_ONLY, t in START_SUBPERIODS, sc=1:SC], EP[:vP][y,t,sc]+EP[:vREG_discharge][y,t,sc]<= EP[:vS][y,t+hours_per_subperiod-1,sc]
		end)
	end
	if !isempty(STOR_RSV_ONLY)
		# Storage units charging can charge faster to provide reserves down and charge slower to provide reserves up
		@constraints(EP, begin
			# Maximum storage contribution to reserves is a specified fraction of installed capacity
			[y in STOR_RSV_ONLY, t=1:T, sc=1:SC], EP[:vRSV][y,t,sc] <= dfGen[y,:Rsv_Max]*EP[:eTotalCap][y]

			# Actual contribution to regulation and reserves is sum of auxilary variables for portions contributed during charging and discharging
			[y in STOR_RSV_ONLY, t=1:T, sc=1:SC], EP[:vRSV][y,t,sc] == EP[:vRSV_charge][y,t,sc]+EP[:vRSV_discharge][y,t,sc]

			# Maximum charging rate plus contribution to reserves up must be greater than zero
			# Note: when charging, reducing charge rate is contributing to upwards reserve & regulation as it drops net demand
			[y in STOR_RSV_ONLY, t=1:T, sc=1:SC], EP[:vCHARGE][y,t,sc]-EP[:vRSV_charge][y,t,sc] >= 0

			# Note: maximum charge rate is also constrained by maximum charge power capacity, but as this differs by storage type,
			# this constraint is set in functions below for each storage type

			# Maximum discharging rate and contribution to reserves up must be less than power rating OR available stored energy in prior period, whichever is less
			# wrapping from end of sample period to start of sample period for energy capacity constraint
			[y in STOR_RSV_ONLY, t=1:T, sc=1:SC], EP[:vP][y,t,sc]+EP[:vRSV_discharge][y,t,sc] <= EP[:eTotalCap][y]
			[y in STOR_RSV_ONLY, t in INTERIOR_SUBPERIODS, sc=1:SC], EP[:vP][y,t,sc]+EP[:vRSV_discharge][y,t,sc] <= EP[:vS][y,t-1,sc]
			[y in STOR_RSV_ONLY, t in START_SUBPERIODS, sc=1:SC], EP[:vP][y,t,sc]+EP[:vRSV_discharge][y,t,sc] <= EP[:vS][y,t+hours_per_subperiod-1,sc]
		end)
	end
	if !isempty(STOR_NO_RES)
		# Maximum discharging rate must be less than power rating OR available stored energy in prior period, whichever is less
		# wrapping from end of sample period to start of sample period for energy capacity constraint
		@constraints(EP, begin
			[y in STOR_NO_RES, t=1:T, sc=1:SC], EP[:vP][y,t,sc] <= EP[:eTotalCap][y]
			[y in STOR_NO_RES, t in INTERIOR_SUBPERIODS, sc=1:SC], EP[:vP][y,t,sc] <= EP[:vS][y,t-1,sc]
			[y in STOR_NO_RES, t in START_SUBPERIODS, sc=1:SC], EP[:vP][y,t,sc] <= EP[:vS][y,t+hours_per_subperiod-1,sc]
		end)
	end
end
