@doc raw"""
	load_generators_variability!(setup::Dict, path::AbstractString, inputs::Dict)

Read input parameters related to hourly maximum capacity factors for generators, storage, and flexible demand resources
"""
function load_generators_variability!(
    setup::Dict,
    path::AbstractString,
    inputs::Dict,
    weather_scenarios::Int64,
    fuel_scenarios::Int64,
    tdr_exists::Bool
)

    # Hourly capacity factors
    data_directory = joinpath(path, setup["TimeDomainReductionFolder"])
    if setup["TimeDomainReduction"] == 1 && tdr_exists
        my_dir = joinpath(data_directory, "Generators_variability")
    else
        my_dir = joinpath(path, "Generators_variability")
    end

    filename = "Generators_variability_scenario_*.csv"
    gen_var_files = glob(filename, my_dir)
    gen_var = DataFrame.(CSV.File.(gen_var_files))

    all_resources = inputs["RESOURCES"]


    for i = 1:length(gen_var)
        existing_variability = names(gen_var[i])
        for r in all_resources
            if r ∉ existing_variability
                @info "assuming availability of 1.0 for resource $r."
                ensure_column!(gen_var[i], r, 1.0)
            end
        end
        # Reorder DataFrame to R_ID order (order provided in Generators_data.csv)
        select!(gen_var[i], [:Time_Index; Symbol.(all_resources)])
        for fsc = 1:fuel_scenarios
            # Maximum power output and variability of each energy resource
            inputs["pP_Max_scenario_$((fsc-1)*weather_scenarios+i)"] = transpose(
                Matrix{Float64}(gen_var[i][1:inputs["T_scenario_$((fsc-1)*weather_scenarios+i)"], 2:(inputs["G"]+1)]),
            )
        end
    end


    println(filename * " Successfully Read!")

end


function load_generators_variability!(
    setup::Dict,
    path::AbstractString,
    inputs::Dict,
    sc::Int64,
    tdr_exists::Bool
)

    # Hourly capacity factors
    data_directory = joinpath(path, setup["TimeDomainReductionFolder"])
    if setup["TimeDomainReduction"] == 1 && tdr_exists
        my_dir = joinpath(data_directory, "Generators_variability")
    else
        my_dir = joinpath(path, "Generators_variability")
    end
    filename = "Generators_variability_scenario_$sc.csv"
    gen_var = load_dataframe(joinpath(my_dir, filename))

    all_resources = inputs["RESOURCES"]

    existing_variability = names(gen_var)
    for r in all_resources
        if r ∉ existing_variability
            @info "assuming availability of 1.0 for resource $r."
            ensure_column!(gen_var, r, 1.0)
        end
    end

    # Reorder DataFrame to R_ID order (order provided in Generators_data.csv)
    select!(gen_var, [:Time_Index; Symbol.(all_resources)])

    # Maximum power output and variability of each energy resource
    inputs["pP_Max"] = transpose(Matrix{Float64}(gen_var[1:inputs["T"], 2:(inputs["G"]+1)]))

    println(filename * " Successfully Read!")
end
