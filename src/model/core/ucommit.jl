@doc raw"""
	ucommit(EP::Model, inputs::Dict, setup::Dict)

This function creates decision variables and cost expressions associated with thermal plant unit commitment or start-up and shut-down decisions (cycling on/off)

**Unit commitment decision variables:**

This function defines the following decision variables:

$\nu_{y,t,z}$ designates the commitment state of generator cluster $y$ in zone $z$ at time $t$;
$\chi_{y,t,z}$ represents number of startup decisions in cluster $y$ in zone $z$ at time $t$;
$\zeta_{y,t,z}$ represents number of shutdown decisions in cluster $y$ in zone $z$ at time $t$.

**Cost expressions:**

The total cost of start-ups across all generators subject to unit commitment ($y \in UC$) and all time periods, t is expressed as:
```math
\begin{aligned}
	C^{start} = \sum_{y \in UC, t \in T} \omega_t \times start\_cost_{y,t} \times \chi_{y,t}
\end{aligned}
```

The sum of start-up costs is added to the objective function.
"""
function ucommit!(EP::Model, inputs::Dict, setup::Dict)

	println("Unit Commitment Module")

	dfGen = inputs["dfGen"]

	G = inputs["G"]     # Number of resources (generators, storage, DR, and DERs)
	T = inputs["T"]     # Number of time steps (hours)
	Z = inputs["Z"]     # Number of zones
	COMMIT = inputs["COMMIT"] # For not, thermal resources are the only ones eligible for Unit Committment
	SC = inputs["SC"]   # Number of scenarios
	### Variables ###

	## Decision variables for unit commitment
	# commitment state variable
	@variable(EP, vCOMMIT[y in COMMIT, t=1:T, sc=1:SC] >= 0)
	# startup event variable
	@variable(EP, vSTART[y in COMMIT, t=1:T, sc=1:SC] >= 0)
	# shutdown event variable
	@variable(EP, vSHUT[y in COMMIT, t=1:T, sc=1:SC] >= 0)

	### Expressions ###

	## Objective Function Expressions ##

	# Startup costs of "generation" for resource "y" during hour "t"
	@expression(EP, eCStart[y in COMMIT, t=1:T, sc=1:SC],(inputs["omega"][t,sc]*inputs["C_Start"][y,t,sc]*vSTART[y,t,sc]))

	# Julia is fastest when summing over one row one column at a time
	@expression(EP, eTotalCStartT[t=1:T, sc=1:SC], sum(eCStart[y,t,sc] for y in COMMIT))
	@expression(EP, eTotalCStartTSC[t=1:T], sum(eTotalCStartT[t,sc] for sc=1:SC))
	@expression(EP, eTotalCStart, sum(eTotalCStartTSC[t] for t=1:T))

	EP[:eObj] += eTotalCStart

	### Constratints ###
	## Declaration of integer/binary variables
	if setup["UCommit"] == 1 # Integer UC constraints
		for y in COMMIT
			set_integer.(vCOMMIT[y,:])
			set_integer.(vSTART[y,:])
			set_integer.(vSHUT[y,:])
			if y in inputs["RET_CAP"]
				set_integer(EP[:vRETCAP][y])
			end
			if y in inputs["NEW_CAP"]
				set_integer(EP[:vCAP][y])
			end
		end
	end #END unit commitment configuration
	return EP
end
