@doc raw"""
	long_duration_storage!(EP::Model, inputs::Dict)

This function creates variables and constraints enabling modeling of long duration storage resources when modeling representative time periods.

**Storage inventory balance at beginning of each representative period**

The constraints in this section are used to approximate the behavior of long-duration energy storage technologies when approximating annual grid operations by modeling operations over representative periods. Previously, the state of charge balance for storage (as defined in ```storage_all()```) assumed that state of charge at the beginning and end of each representative period has to be the same. In other words, the amount of energy built up or consumed by storage technology $o$ in zone $z$ over the representative period $m$, $\Delta Q_{o,z,m} = 0$. This assumption implicitly excludes the possibility of transferring energy from one representative period to the other which could be cost-optimal when the capital cost of energy storage capacity is relatively small. To model long-duration energy storage using representative periods, we replace the state of charge equation, such that the first term on the right hand side accounts for change in storage inventory associated with representative period $m$ ($\Delta Q_{o,z,m}$), which could be positive (net accumulation) or negative (net reduction).

```math
\begin{aligned}
& \Gamma_{o,z,(m-1)\times \tau^{period}+1 } =\left(1-\eta_{o,z}^{loss}\right)\times \left(\Gamma_{o,z,m\times \tau^{period}} -\Delta Q_{o,z,m}\right) -  \\
& \frac{1}{\eta_{o,z}^{discharge}}\Theta_{o,z,(m-1)\times \tau^{period}+1} + \eta_{o,z}^{charge}\Pi_{o,z,(m-1)\times \tau^{period}+1} \quad \forall o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, m \in \mathcal{M}
\end{aligned}
```

By definition $\mathcal{T}^{start}=\{\left(m-1\right) \times \tau^{period}+1 | m \in \mathcal{M}\}$, which implies that this constraint is defined for all values of $t \in T^{start}$.

**Storage inventory change input periods**

We need additional variables and constraints to approximate energy exchange between representative periods, while accounting for their chronological occurence in the original input time series data and the possibility that two representative periods may not be adjacent to each other (see Figure below). To implement this, we introduce a new variable $Q_{o,z, n}$ that models inventory of storage technology $o \in O$ in zone $z$ in each input period $n \in \mathcal{N}$. Additionally we define a function mapping, $f: n \rightarrow m$, that uniquely maps each input period $n$ to its corresponding representative period $m$. This mapping is available as an output of the process used to identify representative periods (E.g. k-means clustering [Mallapragada et al., 2018](https://www.sciencedirect.com/science/article/pii/S0360544218315238?casa_token=I-6GVNMtAVIAAAAA:G8LFXFqXxRGrXHtrzmiIGm02BusIUmm83zKh8xf1BXY81-dTnA9p2YI1NnGuzlYBXsxK12by)).

![Modeling inter-period energy exchange via long-duration storage when using representative period temporal resolution to approximate annual grid operations](assets/LDES_approach.png)
*Figure. Modeling inter-period energy exchange via long-duration storage when using representative period temporal resolution to approximate annual grid operations*

The following two equations define the storage inventory at the beginning of each input period $n+1$ as the sum of storage inventory at begining of previous input period $n$ plus change in storage inventory for that period. The latter is approximated by the change in storage inventory in the corresponding representative period, identified per the mapping $f(n)$.  The second constraint relates the storage level of the last input period, $|N|$, with the storage level at the beginning of the first input period. Finally, if the input period is also a representative period, then a third constraint enforces that initial storage level estimated by the intra-period storage balance constraint should equal the initial storage level estimated from the inter-period storage balance constraints. Note that $|N|$ refers to the last modeled period.

```math
\begin{aligned}
& Q_{o,z,n+1} = Q_{o,z,n} + \Delta Q_{o,z,f(n)}
\quad \forall  o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, n \in \mathcal{N}\setminus\{|N|\}
\end{aligned}
```

```math
\begin{aligned}
& Q_{o,z,1} = Q_{o,z,|N|} + \Delta Q_{o,z,f(|N|)}
\quad \forall  o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, n = |N|
\end{aligned}
```

```math
\begin{aligned}
& Q_{o,z,n} =\Gamma_{o,z,f(n)\times \tau^{period}} - \Delta Q_{o,z,m}
\quad \forall  o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, n \in   \mathcal{N}^{rep},
\end{aligned}
```

Finally, the next constraint enforces that the initial storage level for each input period $n$ must be less than the installed energy capacity limit. This constraint ensures that installed energy storage capacity is consistent with the state of charge during both the operational time periods $t$ during each sample period $m$ as well as at the start of each chronologically ordered input period $n$ in the full annual time series.

```math
\begin{aligned}
    Q_{o,z,n} \leq \Delta^{total, energy}_{o,z}
\quad \forall n \in \mathcal{N}, o \in \mathcal{O}^{LDES}
\end{aligned}
```
"""
function long_duration_storage!(EP::Model, inputs::Dict, number_of_scenarios_subset::Int64)

	println("Long Duration Storage Module")

	dfGen = inputs["dfGen"]

	G = inputs["G"]     # Number of resources (generators, storage, DR, and DERs)
	T = inputs["T_scenario_1"]     # Number of time steps (hours)
	Z = inputs["Z"]     # Number of zones
	SC = number_of_scenarios_subset
	NPeriods=53
	#=
	STOR_LONG_DURATION = inputs["STOR_LONG_DURATION"]
	REP_PERIOD = Array{Int64, SC}(undef, SC, 1)

	START_SUBPERIODS = Array{Int64, 2}(undef, SC, 1)

	hours_per_subperiod = Array{Int64, SC}(undef, SC, 1)
	=#
	dfPeriodMap = DataFrame[]
	#=
	NPeriods = Array{Int64, SC}(undef, SC, 1)
	MODELED_PERIODS_INDEX = Array{Int64, SC}(undef, SC, 1)
	REP_PERIODS_INDEX = Array{Int64, SC}(undef, SC, 1)

	for sc in 1:SC
		REP_PERIOD[sc,1] = inputs["REP_PERIOD_scenario_$sc"]     # Number of representative periods
	

		STOR_LONG_DURATION[sc,1] = inputs["STOR_LONG_DURATION_scenario_$sc"]
		START_SUBPERIODS[sc,1] = inputs["START_SUBPERIODS_scenario_$sc"]

		hours_per_subperiod[sc,1] = inputs["hours_per_subperiod_scenario_$sc"] #total number of hours per subperiod

		dfPeriodMap[sc,1] = inputs["Period_Map_scenario_$sc"] # Dataframe that maps modeled periods to representative periods
		NPeriods[sc,1] = size(inputs["Period_Map_scenario_$sc"])[1] # Number of modeled periods

		MODELED_PERIODS_INDEX[sc,1] = 1:NPeriods[sc,1]
		REP_PERIODS_INDEX[sc,1] = MODELED_PERIODS_INDEX[dfPeriodMap[sc,1][!,:Rep_Period] .== MODELED_PERIODS_INDEX[sc,1],1]
	end 
=#
	REP_PERIOD = inputs["REP_PERIOD_scenario_1"]     # Number of representative periods
	

	STOR_LONG_DURATION = inputs["STOR_LONG_DURATION"]
	START_SUBPERIODS = inputs["START_SUBPERIODS_scenario_1"]

	hours_per_subperiod = inputs["hours_per_subperiod_scenario_1"] #total number of hours per subperiod
	for sc in 1:SC
		push!(dfPeriodMap, inputs["Period_Map_scenario_$sc"]) # Dataframe that maps modeled periods to representative periods
	end
	for sc in 1:1
		NPeriods=size(inputs["Period_Map_scenario_$sc"])[1] # Number of modeled periods
	end
	#NPeriods=size(dfPeriodMap[2])[1] # Number of modeled periods

	MODELED_PERIODS_INDEX = 1:NPeriods
	REP_PERIODS_INDEX = MODELED_PERIODS_INDEX[dfPeriodMap[1][!,:Rep_Period] .== MODELED_PERIODS_INDEX]
	

	### Variables ###

	# Variables to define inter-period energy transferred between modeled periods

	# State of charge of storage at beginning of each modeled period n
	@variable(EP, vSOCw[y in STOR_LONG_DURATION, n in MODELED_PERIODS_INDEX, sc=1:SC] >= 0)

	# Build up in storage inventory over each representative period w
	# Build up inventory can be positive or negative
	@variable(EP, vdSOC[y in STOR_LONG_DURATION, w=1:REP_PERIOD, sc=1:SC])

	### Constraints ###

	# Links last time step with first time step, ensuring position in hour 1 is within eligible change from final hour position
	# Modified initial state of storage for long-duration storage - initialize wth value carried over from last period
	# Alternative to cSoCBalStart constraint which is included when not modeling operations wrapping and long duration storage
	# Note: tw_min = hours_per_subperiod*(w-1)+1; tw_max = hours_per_subperiod*w
	@constraint(EP, cSoCBalLongDurationStorageStart[w=1:REP_PERIOD, y in STOR_LONG_DURATION, sc=1:SC],
				    EP[:vS][y,hours_per_subperiod*(w-1)+1,sc] == (1-dfGen[y,:Self_Disch])*(EP[:vS][y,hours_per_subperiod*w,sc]-vdSOC[y,w,sc])-(1/dfGen[y,:Eff_Down]*EP[:vP][y,hours_per_subperiod*(w-1)+1,sc])+(dfGen[y,:Eff_Up]*EP[:vCHARGE][y,hours_per_subperiod*(w-1)+1,sc]))

	# Storage at beginning of period w = storage at beginning of period w-1 + storage built up in period w (after n representative periods)
	## Multiply storage build up term from prior period with corresponding weight
	@constraint(EP, cSoCBalLongDurationStorageInterior[y in STOR_LONG_DURATION, r in MODELED_PERIODS_INDEX[1:(end-1)], sc=1:SC],
					vSOCw[y,r+1,sc] == vSOCw[y,r,sc] + vdSOC[y,dfPeriodMap[sc][r,:Rep_Period_Index],sc])

	## Last period is linked to first period
	@constraint(EP, cSoCBalLongDurationStorageEnd[y in STOR_LONG_DURATION, r in MODELED_PERIODS_INDEX[end], sc=1:SC],
					vSOCw[y,1,sc] == vSOCw[y,r,sc] + vdSOC[y,dfPeriodMap[sc][r,:Rep_Period_Index],sc])

	# Storage at beginning of each modeled period cannot exceed installed energy capacity
	@constraint(EP, cSoCBalLongDurationStorageUpper[y in STOR_LONG_DURATION, r in MODELED_PERIODS_INDEX, sc=1:SC],
					vSOCw[y,r,sc] <= EP[:eTotalCapEnergy][y])

	# Initial storage level for representative periods must also adhere to sub-period storage inventory balance
	# Initial storage = Final storage - change in storage inventory across representative period
	@constraint(EP, cSoCBalLongDurationStorageSub[y in STOR_LONG_DURATION, r in REP_PERIODS_INDEX, sc=1:SC],
					vSOCw[y,r,sc] == EP[:vS][y,hours_per_subperiod*dfPeriodMap[sc][r,:Rep_Period_Index],sc] - vdSOC[y,dfPeriodMap[sc][r,:Rep_Period_Index],sc])

end
