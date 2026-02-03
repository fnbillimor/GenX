# Full Benders Decomposition Integration with MacroEnergySolvers.jl

## Overview

Integrating GenX with MacroEnergySolvers.jl requires fundamentally restructuring the model from a **monolithic formulation** (one unified model) to a **decomposed formulation** (separate planning and operational subproblems). This guide explains what's required.

## Key Concept: The Decomposition

### Current Architecture (Monolithic)
Your current GenX model is a **single JuMP Model** containing:
- Investment variables (capacity decisions): `vCAP`, `vRETCAP`, etc.
- Operational variables (dispatch decisions): `vP`, `vCHARGE`, `vCOMMIT`, etc.
- All constraints together
- Single unified objective function

### Required Architecture (Benders Decomposition)
You need to create **separate models**:

1. **Planning Problem (Master)**: Contains only investment decisions
2. **Operational Subproblems**: One per scenario, containing only dispatch decisions
3. **Linking**: Capacity values link planning → operational problems

---

## MacroEnergySolvers.jl API Requirements

Based on the package documentation and source code, the `benders()` function requires:

```julia
results = benders(
    planning_problem,        # JuMP Model
    subproblems,            # Vector{Dict} or DArray{Dict}
    linking_variables_sub,  # Dict{Int, Vector{String}}
    setup                   # Dict with algorithm parameters
)
```

### 1. Planning Problem Model

A JuMP model with these **specific components**:

```julia
# Required variables
@variable(planning_problem, vCAP[...] >= 0)           # Investment variables
@variable(planning_problem, vRETCAP[...] >= 0)        # Retirement variables
@variable(planning_problem, vTHETA[w=1:num_subproblems])  # Auxiliary variables for each subproblem

# Required expressions (MUST have these exact names)
@expression(planning_problem, eFixedCost, 
    # Sum of all investment costs
    sum(inv_cost * vCAP[y] + fom_cost * (existing_cap + vCAP[y] - vRETCAP[y]) 
        for y in resources)
)

@expression(planning_problem, eApproximateVariableCost,
    # Approximation of operational costs using vTHETA
    sum(prob[w] * vTHETA[w] for w in 1:num_subproblems)
)

# Required objective
@objective(planning_problem, Min, eFixedCost + eApproximateVariableCost)
```

**Key Points:**
- Contains **ONLY** investment/capacity variables
- **NO** operational variables (vP, vCHARGE, etc.)
- `vTHETA[w]` are placeholder variables that will be updated with operational costs during Benders iterations
- Expression names `eFixedCost` and `eApproximateVariableCost` are **mandatory**
- In your case: `eFixedCost` corresponds to your current `EP[:sSIC]`

### 2. Subproblems Structure

A vector (or distributed array) of dictionaries, one per operational subproblem:

```julia
subproblems = Vector{Dict{Any, Any}}()

for sc in 1:number_of_scenarios
    subproblem_dict = Dict(
        :model => operational_model_scenario_sc,  # JuMP Model for this scenario
        :linking_variables_sub => ["vCAP", "vRETCAP", ...],  # Linking variable names
        :subproblem_index => sc  # Index identifier
    )
    push!(subproblems, subproblem_dict)
end
```

Each **operational model** must:
- Contain all dispatch variables: `vP[y,t]`, `vCHARGE[y,t]`, etc.
- Have operational constraints: power balance, storage balance, reserves, etc.
- Have capacity variables **as parameters** (fixed values from planning problem)
- **NOT** have investment variables

### 3. Linking Variables Dictionary

Maps each subproblem to its linking variables:

```julia
linking_variables_sub = Dict(
    1 => ["vCAP", "vRETCAP", "vCAP_charge", "vCAP_energy", ...],  # Scenario 1
    2 => ["vCAP", "vRETCAP", "vCAP_charge", "vCAP_energy", ...],  # Scenario 2
    # ... one entry per scenario
)
```

These are the **capacity variables** that couple planning and operations.

### 4. Setup Dictionary

Algorithm configuration:

```julia
setup_benders = Dict(
    :MaxIter => 100,              # Maximum Benders iterations
    :ConvTol => 1e-3,             # Convergence tolerance
    :MaxCpuTime => 7200,          # Max CPU time in seconds
    :StabParam => 0.5,            # Regularization parameter γ ∈ [0,1]
    :StabDynamic => true,         # Dynamic adjustment of γ
    :IntegerInvestment => true,   # If capacity variables are integer
    :Distributed => false,        # Use distributed computing
    :ExpectFeasibleSubproblems => true  # Skip feasibility cuts if guaranteed feasible
)
```

---

## Required Code Changes

### Step 1: Create New Function Structure

You'll need a new function that wraps `generate_model`:

```julia
function generate_benders_decomposition(setup::Dict, inputs::Dict, 
                                       OPTIMIZER::MOI.OptimizerWithAttributes, 
                                       number_of_scenarios::Int64)
    
    # Step 1: Build planning problem
    planning_problem = build_planning_problem(setup, inputs, OPTIMIZER)
    
    # Step 2: Build operational subproblems (one per scenario)
    subproblems = build_operational_subproblems(setup, inputs, OPTIMIZER, number_of_scenarios)
    
    # Step 3: Define linking variables
    linking_variables_sub = build_linking_variables_dict(inputs, number_of_scenarios)
    
    # Step 4: Configure Benders algorithm
    benders_setup = configure_benders_algorithm(setup)
    
    # Step 5: Solve using Benders decomposition
    results = benders(planning_problem, subproblems, linking_variables_sub, benders_setup)
    
    return results
end
```

### Step 2: Build Planning Problem

Create a new file: `src/model/benders/build_planning_problem.jl`

```julia
function build_planning_problem(setup::Dict, inputs::Dict, OPTIMIZER)
    
    PP = Model(OPTIMIZER)
    
    # Add investment variables ONLY
    G = inputs["G"]
    NEW_CAP = inputs["NEW_CAP"]
    RET_CAP = inputs["RET_CAP"]
    SC = number_of_scenarios
    
    @variable(PP, vCAP[y in NEW_CAP] >= 0)
    @variable(PP, vRETCAP[y in RET_CAP] >= 0)
    
    # For storage resources
    if !isempty(inputs["STOR_ALL"])
        @variable(PP, vCAP_energy[y in inputs["NEW_CAP_ENERGY"]] >= 0)
    end
    if !isempty(inputs["STOR_ASYMMETRIC"])
        @variable(PP, vCAP_charge[y in inputs["NEW_CAP_CHARGE"]] >= 0)
    end
    
    # For transmission
    if inputs["Z"] > 1
        @variable(PP, vNEW_TRANS_CAP[l in inputs["EXPANSION_LINES"]] >= 0)
    end
    
    # Auxiliary variables for operational costs (one per subproblem/scenario)
    @variable(PP, vTHETA[sc=1:SC])
    
    # Total capacity expression (needed for some constraints)
    @expression(PP, eTotalCap[y in 1:G],
        if y in intersect(NEW_CAP, RET_CAP)
            inputs["dfGen"][y,:Existing_Cap_MW] + vCAP[y] - vRETCAP[y]
        elseif y in NEW_CAP
            inputs["dfGen"][y,:Existing_Cap_MW] + vCAP[y]
        elseif y in RET_CAP
            inputs["dfGen"][y,:Existing_Cap_MW] - vRETCAP[y]
        else
            inputs["dfGen"][y,:Existing_Cap_MW]
        end
    )
    
    # Investment cost expression (REQUIRED NAME)
    @expression(PP, eFixedCost,
        sum(inputs["dfGen"][y,:Inv_Cost_per_MWyr] * vCAP[y] +
            inputs["dfGen"][y,:Fixed_OM_Cost_per_MWyr] * eTotalCap[y]
            for y in 1:G)
        # Add storage energy capacity costs
        + (isempty(inputs["STOR_ALL"]) ? 0 : 
           sum(inputs["dfGen"][y,:Inv_Cost_per_MWhyr] * vCAP_energy[y] 
               for y in inputs["NEW_CAP_ENERGY"]))
        # Add transmission costs
        + (inputs["Z"] == 1 ? 0 :
           sum(inputs["pC_Line_Reinforcement"][l] * vNEW_TRANS_CAP[l]
               for l in inputs["EXPANSION_LINES"]))
    )
    
    # Approximate operational cost (REQUIRED NAME)
    @expression(PP, eApproximateVariableCost,
        sum(inputs["scenprob"][sc] * vTHETA[sc] for sc in 1:SC)
    )
    
    # Objective function
    @objective(PP, Min, eFixedCost + eApproximateVariableCost)
    
    # Add planning-level constraints
    # - Min/max capacity constraints
    # - Minimum capacity requirements (if cross-scenario)
    # - CO2 cap (if cross-scenario)
    
    for y in intersect(NEW_CAP, RET_CAP)
        @constraint(PP, vRETCAP[y] <= inputs["dfGen"][y,:Existing_Cap_MW])
    end
    
    # Max capacity limits
    for y in NEW_CAP
        if inputs["dfGen"][y,:Max_Cap_MW] >= 0
            @constraint(PP, eTotalCap[y] <= inputs["dfGen"][y,:Max_Cap_MW])
        end
    end
    
    # Min capacity requirements (if applicable)
    if setup["MinCapReq"] == 1
        # Add min cap constraints
    end
    
    return PP
end
```

### Step 3: Build Operational Subproblems

Create: `src/model/benders/build_subproblems.jl`

```julia
function build_operational_subproblems(setup::Dict, inputs::Dict, 
                                      OPTIMIZER, number_of_scenarios::Int64)
    
    subproblems = Vector{Dict{Any, Any}}()
    
    for sc in 1:number_of_scenarios
        # Create operational model for this scenario
        OP = Model(OPTIMIZER)
        
        T = inputs["T_scenario_$sc"]
        Z = inputs["Z"]
        G = inputs["G"]
        
        # ===== OPERATIONAL VARIABLES ONLY =====
        
        # Generation/discharge variables
        @variable(OP, vP[y=1:G, t=1:T] >= 0)
        
        # Storage charge variables
        if !isempty(inputs["STOR_ALL"])
            @variable(OP, vCHARGE[y in inputs["STOR_ALL"], t=1:T] >= 0)
            @variable(OP, vS[y in inputs["STOR_ALL"], t=1:T] >= 0)
        end
        
        # Unit commitment variables
        if setup["UCommit"] > 0
            @variable(OP, vCOMMIT[y in inputs["COMMIT"], t=1:T] >= 0)
            @variable(OP, vSTART[y in inputs["COMMIT"], t=1:T] >= 0)
            @variable(OP, vSHUT[y in inputs["COMMIT"], t=1:T] >= 0)
        end
        
        # Reserve variables
        if setup["Reserves"] > 0
            @variable(OP, vREG[y=1:G, t=1:T] >= 0)
            @variable(OP, vRSV[y=1:G, t=1:T] >= 0)
        end
        
        # Transmission flow variables
        if Z > 1
            @variable(OP, vFLOW[l=1:inputs["L"], t=1:T])
        end
        
        # Non-served energy
        @variable(OP, vNSE[z=1:Z, t=1:T] >= 0)
        
        # ===== CAPACITY VARIABLES AS PARAMETERS =====
        # These will be FIXED based on planning problem solution
        
        @variable(OP, vCAP_fixed[y in inputs["NEW_CAP"]])
        @variable(OP, vRETCAP_fixed[y in inputs["RET_CAP"]])
        
        # Total capacity (computed from fixed values)
        @expression(OP, eTotalCap[y in 1:G],
            if y in intersect(inputs["NEW_CAP"], inputs["RET_CAP"])
                inputs["dfGen"][y,:Existing_Cap_MW] + vCAP_fixed[y] - vRETCAP_fixed[y]
            elseif y in inputs["NEW_CAP"]
                inputs["dfGen"][y,:Existing_Cap_MW] + vCAP_fixed[y]
            elseif y in inputs["RET_CAP"]
                inputs["dfGen"][y,:Existing_Cap_MW] - vRETCAP_fixed[y]
            else
                inputs["dfGen"][y,:Existing_Cap_MW]
            end
        )
        
        # ===== OPERATIONAL CONSTRAINTS =====
        
        # Power balance
        @expression(OP, ePowerBalance[t=1:T, z=1:Z],
            sum(vP[y,t] for y in inputs["RESOURCES_IN_ZONE"][z])
            - sum(vCHARGE[y,t] for y in intersect(inputs["STOR_ALL"], inputs["RESOURCES_IN_ZONE"][z]))
            - (Z > 1 ? sum(inputs["pNetwork_Map"][l,z] * vFLOW[l,t] for l=1:inputs["L"]) : 0)
            + vNSE[z,t]
        )
        @constraint(OP, cPowerBalance[t=1:T, z=1:Z],
            ePowerBalance[t,z] == inputs["pD_scenario_$sc"][t,z]
        )
        
        # Generation capacity constraints
        @constraint(OP, cMaxPower[y=1:G, t=1:T],
            vP[y,t] <= inputs["pP_Max_scenario_$sc"][y,t] * eTotalCap[y]
        )
        
        # Storage balance constraints
        if !isempty(inputs["STOR_ALL"])
            @constraint(OP, cStorageBalance[y in inputs["STOR_ALL"], t=1:T],
                vS[y,t] == (t > 1 ? vS[y,t-1] : inputs["pInitial_Storage"][y]) +
                           inputs["dfGen"][y,:Eff_Up] * vCHARGE[y,t] -
                           vP[y,t] / inputs["dfGen"][y,:Eff_Down]
            )
        end
        
        # Unit commitment constraints
        if setup["UCommit"] > 0
            # Add commitment, ramping, min up/down time constraints
        end
        
        # Reserve constraints
        if setup["Reserves"] > 0
            # Add reserve provision constraints
        end
        
        # Transmission constraints
        if Z > 1
            # Add flow limits based on fixed transmission capacity
        end
        
        # ===== OBJECTIVE: OPERATIONAL COSTS =====
        
        @expression(OP, eOperationalCost,
            # Variable O&M and fuel costs
            sum(inputs["omega_scenario_$sc"][t] *
                (inputs["dfGen"][y,:Var_OM_Cost_per_MWh] + inputs["dfGen"][y,:Fuel_Cost]) *
                vP[y,t]
                for y=1:G, t=1:T)
            # Charging costs
            + sum(inputs["omega_scenario_$sc"][t] *
                  inputs["dfGen"][y,:Var_OM_Cost_per_MWh_In] *
                  vCHARGE[y,t]
                  for y in inputs["STOR_ALL"], t=1:T)
            # Start-up costs
            + (setup["UCommit"] > 0 ?
               sum(inputs["omega_scenario_$sc"][t] *
                   inputs["dfGen"][y,:Start_Cost_per_MW] *
                   inputs["dfGen"][y,:Cap_Size] *
                   vSTART[y,t]
                   for y in inputs["COMMIT"], t=1:T) : 0)
            # Non-served energy penalty
            + sum(inputs["omega_scenario_$sc"][t] *
                  inputs["pPrice_NSE"] *
                  vNSE[z,t]
                  for z=1:Z, t=1:T)
        )
        
        @objective(OP, Min, eOperationalCost)
        
        # ===== BUILD LINKING VARIABLES LIST =====
        
        linking_vars = String["vCAP_fixed[$y]" for y in inputs["NEW_CAP"]]
        append!(linking_vars, ["vRETCAP_fixed[$y]" for y in inputs["RET_CAP"]])
        
        if !isempty(inputs["STOR_ALL"])
            # Add storage capacity linking variables
        end
        
        if Z > 1
            # Add transmission capacity linking variables
        end
        
        # ===== CREATE SUBPROBLEM DICT =====
        
        subproblem_dict = Dict{Any, Any}(
            :model => OP,
            :linking_variables_sub => linking_vars,
            :subproblem_index => sc
        )
        
        push!(subproblems, subproblem_dict)
    end
    
    return subproblems
end
```

### Step 4: Build Linking Variables Dictionary

```julia
function build_linking_variables_dict(inputs::Dict, number_of_scenarios::Int64)
    
    linking_variables_sub = Dict{Int, Vector{String}}()
    
    # Same linking variables for all scenarios (capacity decisions)
    linking_vars = String[]
    
    for y in inputs["NEW_CAP"]
        push!(linking_vars, "vCAP_fixed[$y]")
    end
    
    for y in inputs["RET_CAP"]
        push!(linking_vars, "vRETCAP_fixed[$y]")
    end
    
    # Storage capacity variables
    if !isempty(inputs["STOR_ALL"])
        for y in inputs["NEW_CAP_ENERGY"]
            push!(linking_vars, "vCAP_energy_fixed[$y]")
        end
    end
    
    # Transmission capacity variables
    if inputs["Z"] > 1
        for l in inputs["EXPANSION_LINES"]
            push!(linking_vars, "vNEW_TRANS_CAP_fixed[$l]")
        end
    end
    
    # Same linking variables for all scenarios
    for sc in 1:number_of_scenarios
        linking_variables_sub[sc] = copy(linking_vars)
    end
    
    return linking_variables_sub
end
```

### Step 5: Modify Existing Modules

Many existing modules need modification to work in decomposed mode:

#### `investment_discharge.jl`
- Remove investment variables and constraints from operational models
- Only add to planning problem when building that

#### `storage.jl`, `thermal.jl`, etc.
- Modify to only add operational variables/constraints
- Use **fixed capacity parameters** instead of variables

#### `transmission.jl`
- Separate investment decisions (planning) from flow decisions (operational)

---

## How Benders Algorithm Works

1. **Initialization**: Solve planning problem with vTHETA[w] unconstrained → get initial capacities

2. **Iteration Loop**:
   ```
   a. FIX capacity variables in subproblems to planning solution values
   b. SOLVE all operational subproblems in parallel
   c. COLLECT dual variables (marginal costs of capacity)
   d. ADD Benders cuts to planning problem:
      vTHETA[w] >= operational_cost[w] + 
                   sum(dual[y] * (vCAP[y] - current_capacity[y]))
   e. SOLVE planning problem again
   f. CHECK convergence: |UB - LB| < tolerance
   ```

3. **Termination**: When bounds converge or max iterations reached

The `vTHETA` variables are **updated** via Benders cuts to approximate operational costs as function of capacity decisions.

---

## Handling Your Special Features

### 1. CVaR Risk Measure

Your model includes CVaR terms in the objective:
```julia
(1-β)*E[cost] + β*CVaR_α[cost]
```

**Challenge**: CVaR couples scenarios together via the VaR variable.

**Solution**: 
- Add `vVAR` to the **planning problem**
- Add `vCVAR_aux[sc]` variables to each **subproblem**
- Modify subproblem objectives to include CVaR terms
- Use extended Benders cuts that include CVaR dual variables

### 2. Multi-Period Linkages

Your model has inter-period storage linkage constraints.

**Solution**:
- If linkages are **within** a scenario: keep in subproblems
- If linkages are **across** scenarios: must reformulate or use multi-cut Benders

### 3. Policy Constraints

CO2 caps, energy share requirements, capacity reserve margins.

**Solution**:
- **Scenario-specific** constraints: keep in subproblems
- **Cross-scenario** constraints: add to planning problem with auxiliary variables

---

## File Structure Changes

Proposed new structure:

```
src/
├── model/
│   ├── generate_model.jl              # Existing monolithic model
│   ├── generate_benders_model.jl      # NEW: Wrapper for Benders
│   ├── benders/                        # NEW DIRECTORY
│   │   ├── build_planning_problem.jl  # Build master problem
│   │   ├── build_subproblems.jl       # Build operational subproblems
│   │   ├── linking_variables.jl       # Define coupling
│   │   ├── configure_algorithm.jl     # Benders parameters
│   │   └── process_results.jl         # Extract solution
│   ├── core/
│   │   ├── discharge/
│   │   │   ├── investment_discharge.jl     # MODIFY: split planning/ops
│   │   │   └── operational_dispatch.jl     # NEW
│   │   ├── transmission_investment.jl      # SPLIT from transmission.jl
│   │   └── transmission_operations.jl      # SPLIT from transmission.jl
│   └── resources/
│       └── storage/
│           ├── storage_investment.jl        # SPLIT
│           └── storage_operations.jl        # SPLIT
```

---

## Estimation of Implementation Effort

### Scope of Changes

| Component | Effort | Files Affected |
|-----------|--------|----------------|
| Planning problem builder | High | New file + 10-15 modules |
| Subproblem builder | High | New file + all constraint modules |
| Modify investment modules | Medium | 5-10 files |
| Modify operational modules | Medium | 15-20 files |
| CVaR decomposition | High | New file + objective |
| Testing & debugging | Very High | - |
| **TOTAL** | **~3-6 weeks full-time** | **30-40 files** |

### Key Challenges

1. **Variable Scoping**: Distinguishing investment vs. operational variables throughout
2. **Expression Building**: Many modules build expressions incrementally - need to track which model
3. **CVaR Decomposition**: Non-trivial to decompose risk measures
4. **Multi-Period Constraints**: May need reformulation
5. **Testing**: Ensuring decomposed model gives same solution as monolithic

---

## Alternative: Hybrid Approach

Instead of full decomposition, consider:

### Option A: Scenario Decomposition Only
- Keep investment + operations in single temporal model
- Decompose only across scenarios
- Simpler but less memory reduction

### Option B: Nested Benders
- Outer loop: Investment (master)
- Middle loop: Scenarios (sub-masters)
- Inner loop: Time periods (sub-subproblems)
- More complex but better for very large problems

### Option C: Rolling Horizon with Benders
- Use Benders only for investment stage
- Solve operations sequentially for each scenario
- Good compromise between monolithic and full decomposition

---

## Recommendations

### 1. **Assess Need**
- Is your current problem solvable in reasonable time?
- Would parallel scenario solving help more than decomposition?
- Consider distributed computing first (simpler)

### 2. **Start Small**
- Test on simplified version: single zone, no storage, no unit commitment
- Validate against monolithic solution
- Gradually add complexity

### 3. **Use Existing Tools**
- MacroEnergySolvers.jl handles the Benders algorithm logic
- Focus on proper model decomposition
- Leverage their regularization techniques

### 4. **Consider Alternatives**
- **Dantzig-Wolfe decomposition** for time periods
- **Lagrangian relaxation** for coupling constraints
- **Distributed solve** of monolithic model with decomposition-based cuts

---

## Next Steps

If you decide to proceed:

1. **Create prototype** with toy problem (2 resources, 2 scenarios, 24 hours)
2. **Build planning problem** for toy problem
3. **Build operational subproblems** for toy problem
4. **Test Benders algorithm** on toy problem
5. **Validate** against monolithic solve
6. **Scale up** gradually

Would you like me to:
- Create a prototype implementation for a simplified case?
- Help prioritize which features to implement first?
- Explore alternative decomposition strategies?
