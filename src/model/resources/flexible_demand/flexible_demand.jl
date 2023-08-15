@doc raw"""
    flexible_demand!(EP::Model, inputs::Dict, setup::Dict)
This function defines the operating constraints for flexible demand resources. As implemented, flexible demand resources ($y \in \mathcal{DF}$) are characterized by: 
a) maximum deferrable demand as a fraction of available capacity in a particular time step $t$, and scenario $sc$ $\rho^{max}_{y,z,t,sc}$, 
b) the maximum time this demand can be advanced and delayed, defined by parameters, $\tau^{advance}_{y,z}$ and $\tau^{delay}_{y,z}$, respectively and 
c) the energy losses associated with shifting demand, $\eta_{y,z}^{dflex}$.
**Tracking total deferred demand**
The operational constraints governing flexible demand resources are as follows.
The first two constraints model keep track of inventory of deferred demand in each time step.  Specifically, the amount of deferred demand remaining to 
be served ($\Gamma_{y,z,t,sc}$) depends on the amount in the previous time step minus the served demand during time step $t$ ($\Theta_{y,z,t,sc}$) 
while accounting for energy losses associated with demand flexibility, plus the demand that has been deferred during the current time 
step ($\Pi_{y,z,t,sc}$). Note that variable $\Gamma_{y,z,t,sc} \in \mathbb{R}$, $\forall y \in \mathcal{DF}, t  \in \mathcal{T}, sc \in \mathcal{SC}$. 
Similar to hydro inventory or storage state of charge constraints, for the first time step of the year (or each representative period), we define 
the deferred demand level based on level of deferred demand in the last time step of the year (or each representative period).
```math
\begin{aligned}
\Gamma_{y,z,t,sc} = \Gamma_{y,z,t-1,sc} -\eta_{y,z}^{dflex}\Theta_{y,z,t,sc} +\Pi_{y,z,t,sc} \hspace{4 cm}  \forall y \in \mathcal{DF}, z \in \mathcal{Z}, t \in \mathcal{T}^{interior}, sc \in \mathcal{SC} \\
\Gamma_{y,z,t,sc} = \Gamma_{y,z,t +\tau^{period}-1,sc} -\eta_{y,z}^{dflex}\Theta_{y,z,t,sc} +\Pi_{y,z,t,sc} \hspace{4 cm}  \forall y \in \mathcal{DF}, z \in \mathcal{Z}, t \in \mathcal{T}^{start}, sc \in \mathcal{SC}
\end{aligned}
```
**Bounds on available demand flexibility**
At any given time step, the amount of demand that can be shifted or deferred cannot exceed the maximum deferrable demand, defined by product of the availability 
factor ($\rho^{max}_{y,z,t,sc}$) times the available capacity($\Delta^{total}_{y,z}$).
```math
\begin{aligned}
\Pi_{y,t,sc} \leq \rho^{max}_{y,z,t,sc}\Delta^{total}_{y,z} \hspace{4 cm}  \forall y \in \mathcal{DF}, z \in \mathcal{Z}, t \in \mathcal{T}, sc \in \mathcal{SC}
\end{aligned}
```
**Maximum time delay and advancements**
Delayed demand must then be served within a fixed number of time steps. This is done by enforcing the sum of demand satisfied ($\Theta_{y,z,t,sc}$) in the 
following $\tau^{delay}_{y,z}$ time steps (e.g., t + 1 to t + $\tau^{delay}_{y,z}$) to be greater than or equal to the level of energy deferred during 
time step $t$.
```math
\begin{aligned}
\sum_{e=t+1}^{t+\tau^{delay}_{y,z}}{\Theta_{y,z,e,sc}} \geq \Gamma_{y,z,t,sc}
    \hspace{4 cm}  \forall y \in \mathcal{DF},z \in \mathcal{Z}, t \in \mathcal{T}, , sc \in \mathcal{SC}
\end{aligned}
```
A similar constraints maximum time steps of demand advancement. This is done by enforcing the sum of demand deferred ($\Pi_{y,t,sc}$) in the following 
$\tau^{advance}_{y,z}$ time steps (e.g., t + 1 to t + $\tau^{advance}_{y,z}$) to be greater than or equal to the total level of energy deferred during 
time $t$ (-$\Gamma_{y,t,sc}$). The negative sign is included to account for the established sign convention that treat demand deferred in advance of 
the actual demand is defined to be negative.
```math
\begin{aligned}
\sum_{e=t+1}^{t+\tau^{advance}_{y,z}}{\Pi_{y,z,e,sc}} \geq -\Gamma_{y,z,t,sc}
    \hspace{4 cm}  \forall y \in \mathcal{DF}, z \in \mathcal{Z}, t \in \mathcal{T}, sc \in \mathcal{SC}
\end{aligned}
```
If $t$ is first time step of the year (or the first time step of the representative period), then the above two constraints are implemented to look 
back over the last n time steps, starting with the last time step of the year (or the last time step of the representative period). This time-wrapping 
implementation is similar to the time-wrapping implementations used for defining the storage balance constraints for hydropower reservoir resources 
and energy storage resources.
"""
function flexible_demand!(EP::Model, inputs::Dict, setup::Dict)
    ## Flexible demand resources available during all hours and can be either delayed or advanced (virtual storage-shiftable demand) - DR ==1

    println("Flexible Demand Resources Module")

    dfGen = inputs["dfGen"]

    T = inputs["T"]     # Number of time steps (hours)
    Z = inputs["Z"]     # Number of zones
    FLEX = inputs["FLEX"] # Set of flexible demand resources
    SC = inputs["SC"]   # Number of scenarios

    hours_per_subperiod = inputs["hours_per_subperiod"] # Total number of hours per subperiod

    ### Variables ###

    # Variable tracking total advanced (negative) or deferred (positive) demand for demand flex resource y in period t
    @variable(EP, vS_FLEX[y in FLEX, t=1:T, sc=1:SC]);

    # Variable tracking demand deferred by demand flex resource y in period t
    @variable(EP, vCHARGE_FLEX[y in FLEX, t=1:T, sc=1:SC] >= 0);

    ### Expressions ###

    ## Power Balance Expressions ##
    @expression(EP, ePowerBalanceDemandFlex[t=1:T, z=1:Z, sc=1:SC],
    sum(-EP[:vP][y,t,sc]+EP[:vCHARGE_FLEX][y,t,sc] for y in intersect(FLEX, dfGen[(dfGen[!,:Zone].==z),:R_ID])))

    EP[:ePowerBalance] += ePowerBalanceDemandFlex

    # Capacity Reserves Margin policy
    if setup["CapacityReserveMargin"] > 0
        @expression(EP, eCapResMarBalanceFlex[res=1:inputs["NCapacityReserveMargin"], t=1:T, sc=1:SC], sum(dfGen[y,Symbol("CapRes_$res")] * (EP[:vCHARGE_FLEX][y,t,sc] - EP[:vP][y,t,sc]) for y in FLEX))
        EP[:eCapResMarBalance] += eCapResMarBalanceFlex
    end

    ## Objective Function Expressions ##

    # Variable costs of "charging" for technologies "y" during hour "t" in zone "z"
    @expression(EP, eCVarFlex_in[y in FLEX,t=1:T, sc=1:SC], inputs["omega"][t,sc]*dfGen[y,:Var_OM_Cost_per_MWh_In]*vCHARGE_FLEX[y,t,sc])

    # Sum individual resource contributions to variable charging costs to get total variable charging costs
    @expression(EP, eTotalCVarFlexInT[t=1:T, sc=1:SC], sum(eCVarFlex_in[y,t,sc] for y in FLEX))
    @expression(EP, eTotalCVarFlexInTSC[sc=1:SC], sum(eTotalCVarFlexInT[t,sc] for t in 1:T))
    #@expression(EP, eTotalCVarFlexIn, sum(eTotalCVarFlexInTSC[t] for sc in 1:SC))
    #EP[:eObj] += eTotalCVarFlexIn
    for sc in 1:SC
        EP[:eSCS][sc] += eTotalCVarFlexInTSC[sc]
    end

    ### Constraints ###

    ## Flexible demand is available only during specified hours with time delay or time advance (virtual storage-shiftable demand)
    for z in 1:Z
        # NOTE: Flexible demand operates by zone since capacity is now related to zone demand
        FLEX_Z = intersect(FLEX, dfGen[dfGen.Zone .== z, :R_ID])

        @constraints(EP, begin
        # State of "charge" constraint (equals previous state + charge - discharge)
        # NOTE: no maximum energy "stored" or deferred for later hours
        # NOTE: Flexible_Demand_Energy_Eff corresponds to energy loss due to time shifting
        [y in FLEX_Z, t in 1:T, sc in 1:SC], EP[:vS_FLEX][y,t,sc] == EP[:vS_FLEX][y, hoursbefore(hours_per_subperiod, t, 1),sc] - dfGen[y, :Flexible_Demand_Energy_Eff] * EP[:vP][y,t,sc] + EP[:vCHARGE_FLEX][y,t,sc]

        # Maximum charging rate
        # NOTE: the maximum amount that can be shifted is given by hourly availability of the resource times the maximum capacity of the resource
        [y in FLEX_Z, t=1:T, sc in 1:SC], EP[:vCHARGE_FLEX][y,t,sc] <= inputs["pP_Max"][y,t,sc]*EP[:eTotalCap][y]
        # NOTE: no maximum discharge rate unless constrained by other factors like transmission, etc.
    end)


    for y in FLEX_Z

        # Require deferred demands to be satisfied within the specified time delay
        max_flexible_demand_delay = Int(floor(dfGen[y,:Max_Flexible_Demand_Delay]))

        # Require advanced demands to be satisfied within the specified time period
        max_flexible_demand_advance = Int(floor(dfGen[y,:Max_Flexible_Demand_Advance]))

        @constraint(EP, [t in 1:T, sc in 1:SC],
            # cFlexibleDemandDelay: Constraints looks forward over next n hours, where n = max_flexible_demand_delay
            sum(EP[:vP][y,e,sc] for e=hoursafter(hours_per_subperiod, t, 1:max_flexible_demand_delay)) >= EP[:vS_FLEX][y,t,sc])

        @constraint(EP, [t in 1:T],
            # cFlexibleDemandAdvance: Constraint looks forward over next n hours, where n = max_flexible_demand_advance
            sum(EP[:vCHARGE_FLEX][y,e,sc] for e=hoursafter(hours_per_subperiod, t, 1:max_flexible_demand_advance)) >= -EP[:vS_FLEX][y,t,sc])

    end
end

return EP
end

