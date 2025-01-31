@doc raw"""
	load_inputs(setup::Dict,path::AbstractString)

Loads various data inputs from multiple input .csv files in path directory and stores variables in a Dict (dictionary) object for use in model() function

inputs:
setup - dict object containing setup parameters
path - string path to working directory

returns: Dict (dictionary) object containing all data inputs
"""
function load_inputs!(
    setup::Dict,
    path::AbstractString,
    scenario_num::Int64,
    weather_scenarios::Int64,
    fuel_scenario_num::Int64,
    inputs::Dict,
    tdr_exists::Bool,
    source_flag = false,
)
    source_flag = true #flag to indicate which implementation of load_input calls the load_generators_data.jl true for call from the case runner, and false for call from the TDR

    ## Read input files
    println("Reading Input CSV Files")
    ## Declare Dict (dictionary) object used to store parameters
    #inputs = Dict()
    # Read input data about power network topology, operating and expansion attributes
    if isfile(joinpath(path, "Network.csv"))
        network_var = load_network_data!(setup, path, inputs)
    else
        inputs["Z"] = 1
        inputs["L"] = 0
    end

    # Read temporal-resolved load data, and clustering information if relevant
    load_load_data!(setup, path, inputs, weather_scenarios, fuel_scenario_num, tdr_exists)
    # Read fuel cost data, including time-varying fuel costs
    load_fuels_data!(setup, path, inputs, weather_scenarios, tdr_exists)
    # Read in generator/resource related inputs
    load_generators_data!(setup, path, inputs, source_flag, fuel_scenario_num, weather_scenarios)
    # Read in generator/resource availability profiles
    load_generators_variability!(setup, path, inputs, weather_scenarios, fuel_scenario_num, tdr_exists)

    validatetimebasis(inputs, scenario_num, fuel_scenario_num)

    if setup["CapacityReserveMargin"] == 1
        load_cap_reserve_margin!(setup, path, inputs)
        if inputs["Z"] > 1
            load_cap_reserve_margin_trans!(setup, inputs, network_var)
        end
    end

    # Read in general configuration parameters for reserves (resource-specific reserve parameters are read in generators_data())
    if setup["Reserves"] == 1
        load_reserves!(setup, path, inputs)
    end

    if setup["MinCapReq"] == 1
        load_minimum_capacity_requirement!(path, inputs, setup)
    end

    if setup["MaxCapReq"] == 1
        load_maximum_capacity_requirement!(path, inputs, setup)
    end

    if setup["EnergyShareRequirement"] == 1
        load_energy_share_requirement!(setup, path, inputs)
    end

    if setup["CO2Cap"] >= 1
        load_co2_cap!(setup, path, inputs)
    end

    # Read in mapping of modeled periods to representative periods
    for sc = 1:scenario_num
        if is_period_map_necessary(inputs, sc) &&
           is_period_map_exist(setup, path, inputs, sc)
            load_period_map!(setup, path, inputs, sc)
        end
    end

    #load_probability_distribution!(setup, path, inputs, scenario_num)

    println("CSV Files Successfully Read In From $path")

    return inputs
end

function load_inputs!(
    setup::Dict,
    path::AbstractString,
    scenario_num::Int64,
    sc::Int64,
    fsc::Int64,
    tdr_exists::Bool,
    source_flag = false,
)
    #flag to indicate which implementation of load_input calls the load_generators_data.jl true for call from the case runner, and false for call from the TDR
    ## Read input files
    println("Reading Input CSV Files")
    ## Declare Dict (dictionary) object used to store parameters
    inputs = Dict()
    # Read input data about power network topology, operating and expansion attributes
    if isfile(joinpath(path, "Network.csv"))
        network_var = load_network_data!(setup, path, inputs)
    else
        inputs["Z"] = 1
        inputs["L"] = 0
    end

    # Read temporal-resolved load data, and clustering information if relevant
    load_load_data!(setup, path, inputs, sc, tdr_exists)
    # Read fuel cost data, including time-varying fuel costs
    load_fuels_data!(setup, path, inputs, scenario_num, fsc, tdr_exists)
    # Read in generator/resource related inputs
    load_generators_data!(setup, path, inputs, source_flag, fsc, sc)
    # Read in generator/resource availability profiles
    load_generators_variability!(setup, path, inputs, sc, tdr_exists)

    validatetimebasis(inputs, sc)

    if setup["CapacityReserveMargin"] == 1
        load_cap_reserve_margin!(setup, path, inputs)
        if inputs["Z"] > 1
            load_cap_reserve_margin_trans!(setup, inputs, network_var)
        end
    end

    # Read in general configuration parameters for reserves (resource-specific reserve parameters are read in generators_data())
    if setup["Reserves"] == 1
        load_reserves!(setup, path, inputs)
    end

    if setup["MinCapReq"] == 1
        load_minimum_capacity_requirement!(path, inputs, setup)
    end

    if setup["MaxCapReq"] == 1
        load_maximum_capacity_requirement!(path, inputs, setup)
    end

    if setup["EnergyShareRequirement"] == 1
        load_energy_share_requirement!(setup, path, inputs)
    end

    if setup["CO2Cap"] >= 1
        load_co2_cap!(setup, path, inputs)
    end

    # Read in mapping of modeled periods to representative periods
    if is_period_map_necessary(inputs, sc) && is_period_map_exist(setup, path, inputs, sc)
        load_period_map!(setup, path, inputs)
    end

    println("CSV Files Successfully Read In From $path")

    return inputs
end


function is_period_map_necessary(inputs::Dict, sc::Int64)
    multiple_rep_periods = inputs["REP_PERIOD_scenario_$sc"] > 1
    has_stor_lds = !isempty(inputs["STOR_LONG_DURATION"])
    has_hydro_lds = !isempty(inputs["STOR_HYDRO_LONG_DURATION"])
    multiple_rep_periods && (has_stor_lds || has_hydro_lds)
end

function is_period_map_exist(setup::Dict, path::AbstractString, inputs::Dict, sc::Int64)
    filename = "Period_map_scenario_$sc.csv"
    is_here = isfile(joinpath(path, "Period_map", filename))
    is_in_folder =
        isfile(joinpath(path, setup["TimeDomainReductionFolder"], "Period_map", filename))
    is_here || is_in_folder
end
