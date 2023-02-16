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
    non_served_energy!(EP::Model, inputs::Dict, setup::Dict)
This function defines the non-served energy/curtailed demand decision variable $\Lambda_{s,t,z} \forall s \in \mathcal{S}, \forall t \in \mathcal{T}, z \in \mathcal{Z}$, representing the total amount of demand curtailed in demand segment $s$ at time period $t$ in zone $z$. The first segment of non-served energy, $s=1$, is used to denote the cost of involuntary demand curtailment (e.g. emergency load shedding or rolling blackouts), specified as the value of $n_{1}^{slope}$. Additional segments, $s \geq 2$ can be used to specify a segment-wise approximation of a price elastic demand curve, or segments of price-responsive curtailable loads (aka demand response). Each segment denotes a price/cost at which the segment of demand is willing to curtail consumption, $n_{s}^{slope}$, representing the marginal willingness to pay for electricity of this segment of demand (or opportunity cost incurred when demand is not served) and a maximum quantity of demand in this segment, $n_{s}^{size}$, specified as a share of demand in each zone in each time step, $D_{t,z}.$ Note that the current implementation assumes demand segments are an equal share of hourly load in all zones.
This function defines contributions to the objective function from the cost of non-served energy/curtailed demand from all demand curtailment segments $s \in \mathcal{S}$ over all time periods $t \in \mathcal{T}$ and all zones $z \in \mathcal{Z}$:
```math
\begin{aligned}
	Obj_{NSE} =
	\sum_{s \in \mathcal{S} } \sum_{t \in \mathcal{T}} \sum_{z \in \mathcal{Z}}\omega_{t} \times n_{s}^{slope} \times \Lambda_{s,t,z}
\end{aligned}
```
Contributions to the power balance expression from non-served energy/curtailed demand from each demand segment $s \in \mathcal{S}$ are also defined as:
```math
\begin{aligned}
	PowerBal_{NSE} =
	\sum_{s \in \mathcal{S} } \Lambda_{s,t,z}
		\hspace{4 cm}  \forall s \in \mathcal{S}, t \in \mathcal{T}
\end{aligned}
```
**Bounds on curtailable demand**
Demand curtailed in each segment of curtailable demands $s \in \mathcal{S}$ cannot exceed maximum allowable share of demand:
```math
\begin{aligned}
	\Lambda_{s,t,z} \leq (n_{s}^{size} \times D_{t,z})
	\hspace{4 cm}  \forall s \in \mathcal{S}, t \in \mathcal{T}, z\in \mathcal{Z}
\end{aligned}
```
Additionally, total demand curtailed in each time step cannot exceed total demand:
```math
\begin{aligned}
	\sum_{s \in \mathcal{S} } \Lambda_{s,t,z} \leq D_{t,z}
	\hspace{4 cm}  \forall t \in \mathcal{T}, z\in \mathcal{Z}
\end{aligned}
```
"""
function non_served_energy!(EP::Model, inputs::Dict, setup::Dict)

	println("Non-served Energy Module")

	T = inputs["T"]     # Number of time steps
	Z = inputs["Z"]     # Number of zones
	SEG = inputs["SEG"] # Number of load curtailment segments
	SC = inputs["SC"]   # Number of scenarios
	### Variables ###

	# Non-served energy/curtailed demand in the segment "s" at hour "t" in zone "z"
	@variable(EP, vNSE[s=1:SEG,t=1:T,z=1:Z,sc=1:SC] >= 0);

	### Expressions ###

	## Objective Function Expressions ##

	# Cost of non-served energy/curtailed demand at hour "t" in zone "z"
	@expression(EP, eCNSE[s=1:SEG,t=1:T,z=1:Z,sc=1:SC], (inputs["scenprob"][sc]*inputs["omega"][t]*inputs["pC_D_Curtail"][s]*vNSE[s,t,z,sc]))

	# Sum individual demand segment contributions to non-served energy costs to get total non-served energy costs
	# Julia is fastest when summing over one row one column at a time
	@expression(EP, eTotalCNSETSSC[t=1:T,z=1:Z,s=1:SEG], sum(eCNSE[s,t,z,sc] for sc in 1:SC))
	@expression(EP, eTotalCNSETS[t=1:T,z=1:Z], sum(eCNSETSSC[s,t,z] for s in 1:SEG))
	@expression(EP, eTotalCNSET[t=1:T], sum(eTotalCNSETS[t,z] for z in 1:Z))
	@expression(EP, eTotalCNSE, sum(eTotalCNSET[t] for t in 1:T))
	
	# Add total cost contribution of non-served energy/curtailed demand to the objective function
	EP[:eObj] += eTotalCNSE
	
### FNB:	Currently we appear to be summating overs scenarios, then demand, then region, then time.  
### 		Proposed revisions in line with the revised objective function.
###	
###	@expression(EP, eTotalCNSETS[t=1:T,z=1:Z,sc in 1:SC], sum(eCNSE[s,t,z,sc] for s in 1:SEG))
###	@expression(EP, eTotalCNSET[t=1:T,sc in 1:SC], sum(eTotalCNSETS[t,z,sc] for z in 1:Z))
###	@expression(EP, eTotalCNSE[sc in 1:SC], sum(eTotalCNSET[t,sc] for t in 1:T))
###
###	for sc in 1:SC		
###		EP[:eSCS[sc]] += eTotalCNSE[sc]
###	end


	## Power Balance Expressions ##
	@expression(EP, ePowerBalanceNse[t=1:T, z=1:Z, sc=1:SC],
	sum(vNSE[s,t,z,sc] for s=1:SEG))

	# Add non-served energy/curtailed demand contribution to power balance expression
	EP[:ePowerBalance] += ePowerBalanceNse

	# Capacity Reserves Margin policy
	if setup["CapacityReserveMargin"] > 0
		if SEG >=2
			@expression(EP, eCapResMarBalanceNSE[res=1:inputs["NCapacityReserveMargin"], t=1:T, sc=1:SC], sum(EP[:vNSE][s,t,z,sc] for s in 2:SEG, z in findall(x->x!=0,inputs["dfCapRes"][:,res])))
			EP[:eCapResMarBalance] += eCapResMarBalanceNSE
		end
	end

	### Constratints ###

	# Demand curtailed in each segment of curtailable demands cannot exceed maximum allowable share of demand
	@constraint(EP, cNSEPerSeg[s=1:SEG, t=1:T, z=1:Z, sc=1:SC], vNSE[s,t,z,sc] <= inputs["pMax_D_Curtail"][s]*inputs["pD"][t,z,sc])

	# Total demand curtailed in each time step (hourly) cannot exceed total demand
	@constraint(EP, cMaxNSE[t=1:T, z=1:Z, sc=1:SC], sum(vNSE[s,t,z,sc] for s=1:SEG) <= inputs["pD"][t,z,sc])

end
