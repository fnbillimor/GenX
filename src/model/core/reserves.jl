##########################################################################################################################################
# The reserves.jl module contains functions to creates decision variables related to frequency regulation and reserves provision
# and constraints setting overall system requirements for regulation and operating reserves.
##########################################################################################################################################

@doc raw"""
	reserves!(EP::Model, inputs::Dict, setup::Dict)

This function sets up reserve decisions and constraints, using the reserves_core()` and reserves_contingency()` functions.
"""
function reserves!(EP::Model, inputs::Dict, setup::Dict, number_of_scenarios::Int64)

	UCommit = setup["UCommit"]

	if inputs["pStatic_Contingency"] > 0 || (UCommit >= 1 && inputs["pDynamic_Contingency"] >= 1)
		reserves_contingency!(EP, inputs, setup, number_of_scenarios)
	end

	reserves_core!(EP, inputs, setup, number_of_scenarios)
end


@doc raw"""
	reserves_contingency!(EP::Model, inputs::Dict, setup::Dict)

This function establishes several different versions of contingency reserve requirement expression, $CONTINGENCY$ used in the reserves_core() function below.

Contingency reserves represent requirements for upward ramping capability within a specified time frame to compensated for forced outages or unplanned failures of generators or transmission lines (e.g. N-1 contingencies).

There are three options for the $Contingency$ expression, depending on user settings:
	1. a static contingency, in which the contingency requirement is set based on a fixed value (in MW) specified in the '''reserves.csv''' input file;
	2. a dynamic contingency based on installed capacity decisions, in which the largest 'installed' generator is used to determine the contingency requirement for all time periods; and
	3. dynamic unit commitment based contingency, in which the largest 'committed' generator in any time period is used to determine the contingency requirement in that time period.

Note that the two dynamic contigencies are only available if unit commitment is being modeled.

**Static contingency**
Option 1 (static contingency) is expressed by the following constraint:
```math
\begin{aligned}
	Contingency = \epsilon^{contingency}
\end{aligned}
```
where $\epsilon^{contingency}$ is static contingency requirement in MWs.

**Dynamic capacity-based contingency**
Option 2 (dynamic capacity-based contingency) is expressed by the following constraints:
```math
\begin{aligned}
	&Contingency \geq \Omega^{size}_{y,z} \times \alpha^{Contingency,Aux}_{y,z} & \forall y \in \mathcal{UC}, z \in \mathcal{Z}\\
	&\alpha^{Contingency,Aux}_{y,z} \leq \Delta^{\text{total}}_{y,z} & \forall y \in \mathcal{UC}, z \in \mathcal{Z}\\
	&\alpha^{Contingency,Aux}_{y,z} \geq M_y \times \Delta^{\text{total}}_{y,z} & \forall y \in \mathcal{UC}, z \in \mathcal{Z}\\
\end{aligned}
```

where $M_y$ is a `big M' constant equal to the largest possible capacity that can be installed for generation cluster $y$, and $\alpha^{Contingency,Aux}_{y,z} \in [0,1]$ is a binary auxiliary variable that is forced by the second and third equations above to be 1 if the total installed capacity $\Delta^{\text{total}}_{y,z} > 0$ for any generator $y \in \mathcal{UC}$ and zone $z$, and can be 0 otherwise. Note that if the user specifies contingency option 2, and is also using the linear relaxation of unit commitment constraints, the capacity size parameter for units in the set $\mathcal{UC}$ must still be set to a discrete unit size for this contingency to work as intended.

**Dynamic commitment-based contingency**
Option 3 (dynamic commitment-based contingency) is expressed by the following set of constraints:
```math
\begin{aligned}
	& Contingency \geq \Omega^{size}_{y,z} \times Contingency\_Aux_{y,z,t,sc} & \forall y \in \mathcal{UC}, z \in \mathcal{Z}\\
	& Contingency\_Aux_{y,z,t,sc} \leq \nu_{y,z,t,sc} & \forall y \in \mathcal{UC}, z \in \mathcal{Z}\\
	& Contingency\_Aux_{y,z,t,sc} \geq M_y \times \nu_{y,z,t,sc} & \forall y \in \mathcal{UC}, z \in \mathcal{Z}\\
\end{aligned}
```

where $M_y$ is a `big M' constant equal to the largest possible capacity that can be installed for generation cluster $y$, and $Contingency\_Aux_{y,z,t,sc} \in [0,1]$ is a binary auxiliary variable that is forced by the second and third equations above to be 1 if the commitment state for that generation cluster $\nu_{y,z,t,sc} > 0$ for any generator $y \in \mathcal{UC}$ and zone $z$ and time period $t$, scenario $sc$ and can be 0 otherwise. Note that this dynamic commitment-based contingency can only be specified if discrete unit commitment decisions are used (e.g. it will not work if relaxed unit commitment is used).
"""
function reserves_contingency!(EP::Model, inputs::Dict, setup::Dict, number_of_scenarios::Int64)

	println("Reserves Contingency Module")

	dfGen = inputs["dfGen"]

	T = inputs["T_scenario_1"]     # Number of time steps (hours)
	UCommit = setup["UCommit"]
	COMMIT = inputs["COMMIT"]
	SC = number_of_scenarios   # Number of scenarios
	if UCommit >= 1
		pDynamic_Contingency = inputs["pDynamic_Contingency"]
	end

	### Variables ###

	# NOTE: If Dynamic_Contingency == 0, then contingency is a fixed parameter equal the value specified in reserves.csv via pStatic_Contingency.
	if UCommit == 1 && pDynamic_Contingency == 1
		# Contingency = largest installed thermal unit
		@variable(EP, vLARGEST_CONTINGENCY >= 0)
		# Auxiliary variable that is 0 if vCAP = 0, 1 otherwise
		@variable(EP, vCONTINGENCY_AUX[y in COMMIT], Bin)
	elseif UCommit == 1 && pDynamic_Contingency == 2
		# Contingency = largest committed thermal unit in each time period
		@variable(EP, vLARGEST_CONTINGENCY[t=1:T, sc=1:SC] >= 0)
		# Auxiliary variable that is 0 if vCOMMIT = 0, 1 otherwise
		@variable(EP, vCONTINGENCY_AUX[y in COMMIT,t=1:T, sc=1:SC], Bin)
	end

	### Expressions ###
	if UCommit == 1 && pDynamic_Contingency == 1
		# Largest contingency defined as largest installed generator
		println("Dynamic Contingency Type 1: Modeling the largest contingency as the largest installed generator")
		@expression(EP, eContingencyReq[t=1:T, sc=1:SC], vLARGEST_CONTINGENCY)
	elseif UCommit == 1 && pDynamic_Contingency == 2
		# Largest contingency defined for each hour as largest committed generator
		println("Dynamic Contingency Type 2: Modeling the largest contingency as the largest largest committed generator")
		@expression(EP, eContingencyReq[t=1:T,sc=1:SC], vLARGEST_CONTINGENCY[t,sc])
	else
		# Largest contingency defined fixed as user-specifed static contingency in MW
		println("Static Contingency: Modeling the largest contingency as user-specifed static contingency")
		@expression(EP, eContingencyReq[t=1:T,sc=1:SC,], inputs["pStatic_Contingency"])
	end

	### Constraints ###

	# Dynamic contingency related constraints
		# option 1: ensures vLARGEST_CONTINGENCY is greater than the capacity of the largest installed generator
	if UCommit == 1 && pDynamic_Contingency == 1
		@constraint(EP, cContingency[y in COMMIT], vLARGEST_CONTINGENCY >=
			inputs["dfGen"][y,:Cap_Size]*vCONTINGENCY_AUX[y] )
		# Ensure vCONTINGENCY_AUX = 0 if total capacity = 0
		@constraint(EP, cContAux1[y in COMMIT], vCONTINGENCY_AUX[y] <= EP[:eTotalCap][y])
		# Ensure vCONTINGENCY_AUX = 1 if total capacity > 0
		@constraint(EP, cContAux2[y in COMMIT], EP[:eTotalCap][y] <= inputs["pContingency_BigM"][y]*vCONTINGENCY_AUX[y])

		# option 2: ensures vLARGEST_CONTINGENCY is greater than the capacity of the largest commited generator in each hour
	elseif UCommit == 1 && pDynamic_Contingency == 2
		@constraint(EP, cContingency[y in COMMIT, t=1:T,sc=1:SC], vLARGEST_CONTINGENCY[t,sc] >=
			inputs["dfGen"][y,:Cap_Size]*vCONTINGENCY_AUX[y,t,sc] )
		# Ensure vCONTINGENCY_AUX = 0 if vCOMMIT = 0
		@constraint(EP, cContAux[y in COMMIT, t=1:T,sc=1:SC], vCONTINGENCY_AUX[y,t,sc] <= EP[:vCOMMIT][y,t,sc])
		# Ensure vCONTINGENCY_AUX = 1 if vCOMMIT > 0
		@constraint(EP, cContAux2[y in COMMIT, t=1:T,sc=1:SC], EP[:vCOMMIT][y, t,sc] <= inputs["pContingency_BigM"][y]*vCONTINGENCY_AUX[y,t,sc])
	end

end


@doc raw"""
	reserves_core!(EP::Model, inputs::Dict, setup::Dict)

This function creates decision variables related to frequency regulation and reserves provision and constraints setting overall system requirements for regulation and operating reserves.

**Regulation and reserves decisions**
$f_{y,t,sc,z} \geq 0$ is the contribution of generation or storage resource $y \in Y$ in time $t \in T$, scenario $sc \in \mathcal{SC}$, and zone $z \in Z$ to frequency regulation

$r_{y,t,sc,z} \geq 0$ is the contribution of generation or storage resource $y \in Y$ in time $t \in T$, scenario $sc \in \mathcal{SC}$, and zone $z \in Z$ to operating reserves up

We assume frequency regulation is symmetric (provided in equal quantity towards both upwards and downwards regulation). To reduce computational complexity, operating reserves are 
only modeled in the upwards direction, as downwards reserves requirements are rarely binding in practice.

Storage resources ($y \in \mathcal{O}$) have two pairs of auxilary variables to reflect contributions to regulation and reserves when charging and discharging, where the primary variables
($f_{y,z,t,sc}$ \& $r_{y,z,t,sc}$) becomes equal to sum of these auxilary variables.

**Unmet operating reserves**

$unmet\_rsv_{t,sc} \geq 0$ denotes any shortfall in provision of operating reserves during each time period $t \in T$ and scenario $sc \in \mathcal{SC}$

There is a penalty $C^{rsv}$ added to the objective function to penalize reserve shortfalls, which is the expected value of the penalty for each scenario 
weighted by the respective probabilities equal to:

```math
\begin{aligned}
	C^{rvs} = \sum_{sc\in\mathcal{SC}}\sum_{t \in T} prob_{sc}\times\omega_{t, sc} \times unmet\_rsv_{t,sc}
\end{aligned}
```

**Frequency regulation requirements**

Total requirements for frequency regulation (aka primary reserves) in each time step $t$ and in each scenario $sc$ are specified as fractions of hourly demand 
(to reflect demand forecast errors) and variable renewable avaialblity in the time step (to reflect wind and solar forecast errors).

```math
\begin{aligned}
	\sum_{y \in Y, z \in Z} f_{y,t,sc,z} \geq \epsilon^{load}_{reg} \times \sum_{z \in Z} \mathcal{D}_{z,t,sc} + \epsilon^{vre}_{reg} \times \sum_{z \in Z} \rho^{max}_{y,z,t,sc} \times \Delta^{\text{total}}_{y,z} \quad \forall t \in T, sc \in \mathcal{SC}
\end{aligned}
```
where $\mathcal{D}_{z,t,sc}$ is the forecasted electricity demand in zone $z$ at time $t$ and scenario $sc$ (before any demand flexibility); $\rho^{max}_{y,z,t,sc}$ is the forecasted capacity factor for variable renewable resource $y \in VRE$ and zone $z$ in time step $t$ in scenario $sc$; $\Delta^{\text{total}}_{y,z}$ is the total installed capacity of variable renewable resources $y \in VRE$ and zone $z$; and $\epsilon^{load}_{reg}$ and $\epsilon^{vre}_{reg}$ are parameters specifying the required frequency regulation as a fraction of forecasted demand and variable renewable generation.

**Operating reserve requirements**

Total requirements for operating reserves in the upward direction (aka spinning reserves or contingency reserces or secondary reserves) in each time step $t$ and scenario $sc$ are specified as fractions of time step's demand (to reflect demand forecast errors) and variable renewable avaialblity in the time step (to reflect wind and solar forecast errors) plus the largest planning contingency (e.g. potential forced generation outage).

```math
\begin{aligned}
	\sum_{y \in Y, z \in Z} r_{y,z,t,sc} + r^{unmet}_{t,sc} \geq \epsilon^{load}_{rsv} \times \sum_{z \in Z} \mathcal{D}_{z,t,sc} + \epsilon^{vre}_{rsv} \times \sum_{z \in Z} \rho^{max}_{y,z,t,sc} \times \Delta^{\text{total}}_{y,z} + Contingency \quad \forall t \in T, sc \in \mathcal{SC}
\end{aligned}
```

where $\mathcal{D}_{z,t,sc}$ is the forecasted electricity demand in zone $z$ at time $t$ and scenario $sc$ (before any demand flexibility); $\rho^{max}_{y,z,t,sc}$ is the forecasted capacity factor for variable renewable resource $y \in VRE$ and zone $z$ in time step $t$ in scenario $sc$; $\Delta^{\text{total}}_{y,z}$ is the total installed capacity of variable renewable resources $y \in VRE$ and zone $z$; and $\epsilon^{load}_{rsv}$ and $\epsilon^{vre}_{rsv}$ are parameters specifying the required contingency reserves as a fraction of forecasted demand and variable renewable generation. $Contingency$ is an expression defined in the reserves\_contingency() function meant to represent the largest `N-1` contingency (unplanned generator outage) that the system operator must carry operating reserves to cover and depends on how the user wishes to specify contingency requirements.
"""
function reserves_core!(EP::Model, inputs::Dict, setup::Dict, number_of_scenarios::Int64)

	# DEV NOTE: After simplifying reserve changes are integrated/confirmed, should we revise such that reserves can be modeled without UC constraints on?
	# Is there a use case for economic dispatch constraints with reserves?

	println("Reserves Core Module")

	dfGen = inputs["dfGen"]
	UCommit = setup["UCommit"]

	T = inputs["T_scenario_1"]     # Number of time steps (hours)
	Z = inputs["Z"]     # Number of zones
	SC = number_of_scenarios   # Number of scenarios
	REG = inputs["REG"]
	RSV = inputs["RSV"]

	### Variables ###

	## Integer Unit Commitment configuration for variables

	## Decision variables for reserves
	@variable(EP, vREG[y in REG, t=1:T,sc=1:SC] >= 0) # Contribution to regulation (primary reserves), assumed to be symmetric (up & down directions equal)
	@variable(EP, vRSV[y in RSV, t=1:T,sc=1:SC] >= 0) # Contribution to operating reserves (secondary reserves or contingency reserves); only model upward reserve requirements

	# Storage techs have two pairs of auxilary variables to reflect contributions to regulation and reserves
	# when charging and discharging (primary variable becomes equal to sum of these auxilary variables)
	@variable(EP, vREG_discharge[y in intersect(inputs["STOR_ALL"], REG), t=1:T,sc=1:SC] >= 0) # Contribution to regulation (primary reserves) (mirrored variable used for storage devices)
	@variable(EP, vRSV_discharge[y in intersect(inputs["STOR_ALL"], RSV), t=1:T,sc=1:SC] >= 0) # Contribution to operating reserves (secondary reserves) (mirrored variable used for storage devices)
	@variable(EP, vREG_charge[y in intersect(inputs["STOR_ALL"], REG), t=1:T,sc=1:SC] >= 0) # Contribution to regulation (primary reserves) (mirrored variable used for storage devices)
	@variable(EP, vRSV_charge[y in intersect(inputs["STOR_ALL"], RSV), t=1:T,sc=1:SC] >= 0) # Contribution to operating reserves (secondary reserves) (mirrored variable used for storage devices)

	@variable(EP, vUNMET_RSV[t=1:T,sc=1:SC] >= 0) # Unmet operating reserves penalty/cost

	### Expressions ###
	## Total system reserve expressions
	# Regulation requirements as a percentage of load and scheduled variable renewable energy production in each hour
	# Reg up and down requirements are symmetric
	@expression(EP, eRegReq[t=1:T,sc=1:SC], inputs["pReg_Req_Load"]*sum(inputs["pD_scenario_$sc"][t,z] for z=1:Z) +
		inputs["pReg_Req_VRE"]*sum(inputs["pP_Max_scenario_$sc"][y,t]*EP[:eTotalCap][y] for y in intersect(inputs["VRE"], inputs["MUST_RUN"])))
	# Operating reserve up / contingency reserve requirements as ˚a percentage of load and scheduled variable renewable energy production in each hour
	# and the largest single contingency (generator or transmission line outage)
	@expression(EP, eRsvReq[t=1:T,sc=1:SC], inputs["pRsv_Req_Load"]*sum(inputs["pD_scenario_$sc"][t,z] for z=1:Z) +
		inputs["pRsv_Req_VRE"]*sum(inputs["pP_Max_scenario_$sc"][y,t]*EP[:eTotalCap][y] for y in intersect(inputs["VRE"], inputs["MUST_RUN"])))

	# N-1 contingency requirement is considered only if Unit Commitment is being modeled
	if UCommit >= 1 && (inputs["pDynamic_Contingency"] >= 1 || inputs["pStatic_Contingency"] > 0)
		EP[:eRsvReq] = EP[:eRsvReq] + EP[:eContingencyReq]
	end

	## Objective Function Expressions ##

	# Penalty for unmet operating reserves
	@expression(EP, eCRsvPen[t=1:T,sc=1:SC], inputs["omega_scenario_$sc"][t]*inputs["pC_Rsv_Penalty"]*vUNMET_RSV[t,sc])
	@expression(EP, eTotalCRsvPen[sc=1:SC], sum(eCRsvPen[t,sc] for t=1:T) +
		sum(dfGen[y,:Reg_Cost]*vRSV[y,t,sc] for y in RSV, t=1:T) +
		sum(dfGen[y,:Rsv_Cost]*vREG[y,t,sc] for y in REG, t=1:T) )
	
	EP[:eSCS] += eTotalCRsvPen
	### Constraints ###

	## Total system reserve constraints
	# Regulation requirements as a percentage of load and scheduled variable renewable energy production in each hour
	# Note: frequencty regulation up and down requirements are symmetric and all resources contributing to regulation are assumed to contribute equal capacity to both up and down directions
	@constraint(EP, cReg[t=1:T,sc=1:SC], sum(vREG[y,t,sc] for y in REG) >= EP[:eRegReq][t,sc])

	@constraint(EP, cRsvReq[t=1:T,sc=1:SC], sum(vRSV[y,t,sc] for y in RSV) + vUNMET_RSV[t,sc] >= EP[:eRsvReq][t,sc])

end
