#Function to get to the Settings folder for any partcular case
function get_settings_path(case::AbstractString)
    return joinpath(case, "Settings")
end

#Function to get into a particular yml file within the Settings folder
function get_settings_path(case::AbstractString, filename::AbstractString)
    return joinpath(get_settings_path(case), filename)
end

function get_default_output_folder(case::AbstractString)
    return joinpath(case, "Results")
end

@doc raw"""Run the GenX in the given folder
case - folder for the case
"""
function run_genx_case!(case::AbstractString)
    genx_settings = get_settings_path(case, "genx_settings.yml") #Settings YAML file path
    mysetup = configure_settings(genx_settings) # mysetup dictionary stores settings and GenX-specific parameters

    if mysetup["MultiStage"] == 0
        if mysetup["ForecastClusterTSData"] == 1
            generate_timeseries_data(
                case,
                get_settings_path(case),
                mysetup,
                number_of_scenarios,
                weather_scenarios,
                fuel_scenarios,
                myinputs,
                tdr_exists,
            )
        end
        if mysetup["Benders"] == 0
            run_genx_case_simple!(case, mysetup)
        else
            benders_settings_path = get_settings_path(case, "benders_settings.yml")
            mysetup_benders = configure_benders(benders_settings_path) 
            mysetup = merge(mysetup,mysetup_benders);
            run_genx_case_benders!(case, mysetup)
        end
    else
        run_genx_case_multistage!(case, mysetup)
    end
end

function time_domain_reduced_files_exist(tdrpath, number_of_scenarios, weather_scenarios)
    tdr_dict = Dict()
    tdr_true_false = true
    for i = 1:number_of_scenarios
        j, k = divrem(i, weather_scenarios)
        if k != 0
            tdr_load = isfile(joinpath(tdrpath, "Load_data", "Load_data_scenario_$k.csv"))
            tdr_genvar = isfile(
                joinpath(
                    tdrpath,
                    "Generators_variability",
                    "Generators_variability_scenario_$k.csv",
                ),
            )
            tdr_fuels = isfile(joinpath(tdrpath, "Fuels_data", "Fuels_data_scenario_$(j+1).csv"))
            tdr_dict[i] = tdr_load && tdr_genvar && tdr_fuels
        else
            tdr_load = isfile(joinpath(tdrpath, "Load_data", "Load_data_scenario_$weather_scenarios.csv"))
            tdr_genvar = isfile(
                joinpath(
                    tdrpath,
                    "Generators_variability",
                    "Generators_variability_scenario_$weather_scenarios.csv",
                ),
            )
            tdr_fuels = isfile(joinpath(tdrpath, "Fuels_data", "Fuels_data_scenario_$j.csv"))
            tdr_dict[i] = tdr_load && tdr_genvar && tdr_fuels
        end
        tdr_true_false = tdr_true_false && tdr_dict[i]
    end
    return (tdr_true_false)
end

function run_genx_case_simple!(case::AbstractString, mysetup::Dict)
    settings_path = get_settings_path(case)

    ### Cluster time series inputs if necessary and if specified by the user
    TDRpath = joinpath(case, mysetup["TimeDomainReductionFolder"])

    fuel_scenarios, weather_scenarios, number_of_scenarios, myinputs = generate_scenarios!(case, settings_path, mysetup)
    tdr_exists = false #default value
    if mysetup["TimeDomainReduction"] == 1
        for sc = 1:weather_scenarios
            prevent_doubled_timedomainreduction(case, sc)
        end
        tdr_exists = time_domain_reduced_files_exist(TDRpath, number_of_scenarios, weather_scenarios)
        if !tdr_exists
            println("Clustering Time Series Data (Grouped)...")
            for sc = 1:number_of_scenarios
                j, k = divrem(sc, weather_scenarios)
                if k != 0
                    cluster_inputs(case, settings_path, mysetup, number_of_scenarios, weather_scenarios, k, j+1, tdr_exists)
                else
                    cluster_inputs(case, settings_path, mysetup, number_of_scenarios, weather_scenarios, weather_scenarios, j, tdr_exists)
                end
            end
        else
            println("Time Series Data Already Clustered.")
        end
    end

    ### Configure solver
    println("Configuring Solver")
    OPTIMIZER = configure_solver(mysetup["Solver"], settings_path)

    #### Running a case

    ### Load inputs
    println("Loading Inputs")
    myinputs = load_inputs!(mysetup, case, number_of_scenarios, weather_scenarios, fuel_scenarios, myinputs, tdr_exists)

    println("Generating the Optimization Model")
    time_elapsed =
        @elapsed EP = generate_model(mysetup, myinputs, OPTIMIZER, number_of_scenarios)
    println("Time elapsed for model building is")
    println(time_elapsed)

    println("Solving Model")
    EP, solve_time = solve_model(EP, mysetup)
    myinputs["solve_time"] = solve_time # Store the model solve time in myinputs

    # Run MGA if the MGA flag is set to 1 else only save the least cost solution
    println("Writing Output")
    outputs_path = get_default_output_folder(case)
    elapsed_time = @elapsed write_outputs(EP, outputs_path, mysetup, myinputs)
    println("Time elapsed for writing is")
    println(elapsed_time)
    if mysetup["ModelingToGenerateAlternatives"] == 1
        println("Starting Model to Generate Alternatives (MGA) Iterations")
        mga(EP, case, mysetup, myinputs, outputs_path)
    end

    if mysetup["MethodofMorris"] == 1
        println("Starting Global sensitivity analysis with Method of Morris")
        morris(EP, case, mysetup, myinputs, outputs_path, OPTIMIZER)
    end
end


function run_genx_case_multistage!(case::AbstractString, mysetup::Dict)
    settings_path = get_settings_path(case)
    multistage_settings = get_settings_path(case, "multi_stage_settings.yml") # Multi stage settings YAML file path
    mysetup["MultiStageSettingsDict"] = YAML.load(open(multistage_settings))

    ### Cluster time series inputs if necessary and if specified by the user
    tdr_settings = get_settings_path(case, "time_domain_reduction_settings.yml") # Multi stage settings YAML file path
    TDRSettingsDict = YAML.load(open(tdr_settings))

    first_stage_path = joinpath(case, "Inputs", "Inputs_p1")
    TDRpath = joinpath(first_stage_path, mysetup["TimeDomainReductionFolder"])
    if mysetup["TimeDomainReduction"] == 1
        for sc = 1:number_of_scenarios
            prevent_doubled_timedomainreduction(first_stage_path, sc)
        end
        if !time_domain_reduced_files_exist(TDRpath, number_of_scenarios)
            if (mysetup["MultiStage"] == 1) &&
               (TDRSettingsDict["MultiStageConcatenate"] == 0)
                println("Clustering Time Series Data (Individually)...")
                for stage_id = 1:mysetup["MultiStageSettingsDict"]["NumStages"]
                    cluster_inputs(
                        case,
                        settings_path,
                        mysetup,
                        number_of_scenarios,
                        stage_id,
                    )
                end
            else
                println("Clustering Time Series Data (Grouped)...")
                cluster_inputs(case, settings_path, mysetup, number_of_scenarios)
            end
        else
            println("Time Series Data Already Clustered.")
        end
    end

    ### Configure solver
    println("Configuring Solver")
    OPTIMIZER = configure_solver(mysetup["Solver"], settings_path)

    model_dict = Dict()
    inputs_dict = Dict()

    for t = 1:mysetup["MultiStageSettingsDict"]["NumStages"]

        # Step 0) Set Model Year
        mysetup["MultiStageSettingsDict"]["CurStage"] = t

        # Step 1) Load Inputs
        inpath_sub = joinpath(case, "Inputs", string("Inputs_p", t))

        inputs_dict[t] = load_inputs!(mysetup, inpath_sub)
        inputs_dict[t] = configure_multi_stage_inputs(
            inputs_dict[t],
            mysetup["MultiStageSettingsDict"],
            mysetup["NetworkExpansion"],
        )

        # Step 2) Generate model
        model_dict[t] = generate_model(mysetup, inputs_dict[t], OPTIMIZER)
    end


    ### Solve model
    println("Solving Model")

    # Step 3) Run DDP Algorithm
    ## Solve Model
    model_dict, mystats_d, inputs_dict = run_ddp(model_dict, mysetup, inputs_dict)

    # Step 4) Write final outputs from each stage

    outpath = get_default_output_folder(case)

    if mysetup["OverwriteResults"] == 1
        # Overwrite existing results if dir exists
        # This is the default behaviour when there is no flag, to avoid breaking existing code
        if !(isdir(outpath))
            mkdir(outpath)
        end
    else
        # Find closest unused ouput directory name and create it
        outpath = choose_output_dir(outpath)
        mkdir(outpath)
    end

    for p = 1:mysetup["MultiStageSettingsDict"]["NumStages"]
        outpath_cur = joinpath(outpath, "Results_p$p")
        write_outputs(model_dict[p], outpath_cur, mysetup, inputs_dict[p])
    end

    # Step 5) Write DDP summary outputs

    write_multi_stage_outputs(mystats_d, outpath, mysetup, inputs_dict)
end

function run_genx_case_benders!(case::AbstractString, mysetup::Dict)
    settings_path = get_settings_path(case)    
    ### Cluster time series inputs if necessary and if specified by the user
    TDRpath = joinpath(case, mysetup["TimeDomainReductionFolder"])

    fuel_scenarios, weather_scenarios, number_of_scenarios, myinputs = generate_scenarios!(case, settings_path, mysetup)
    tdr_exists = false #default value

    if mysetup["TimeDomainReduction"] == 1
        for sc = 1:weather_scenarios
            prevent_doubled_timedomainreduction(case, sc)
        end
        tdr_exists = time_domain_reduced_files_exist(TDRpath, number_of_scenarios, weather_scenarios)
        if !tdr_exists
            println("Clustering Time Series Data (Grouped)...")
            for sc = 1:number_of_scenarios
                j, k = divrem(sc, weather_scenarios)
                if k != 0
                    cluster_inputs(case, settings_path, mysetup, number_of_scenarios, weather_scenarios, k, j+1, tdr_exists)
                else
                    cluster_inputs(case, settings_path, mysetup, number_of_scenarios, weather_scenarios, weather_scenarios, j, tdr_exists)
                end
            end
        else
            println("Time Series Data Already Clustered.")
        end
    end

    mysetup["settings_path"] = settings_path;

    ### Load inputs
    println("Loading Inputs")
    myinputs = load_inputs!(mysetup, case, number_of_scenarios, weather_scenarios, fuel_scenarios, myinputs, tdr_exists);
    for sc in 1:number_of_scenarios
        myinputs_decomp["inputs_scenario_$sc"] = separate_inputs_subperiods(myinputs);
    end
    

    benders_inputs = generate_benders_inputs(mysetup,myinputs,myinputs_decomp)

    planning_problem, planning_sol,LB_hist,UB_hist,cpu_time,feasibility_hist  = benders(benders_inputs,mysetup);

    println("Benders decomposition took $(cpu_time[end]) seconds to run")

    println("Writing Output")

    if mysetup["BD_Stab_Method"]=="int_level_set" 
        outputs_path = joinpath(case, "results_benders_int_level_set")
    else
        outputs_path = joinpath(case, "results_benders")
    end

    if mysetup["OverwriteResults"] == 1
		# Overwrite existing results if dir exists
		# This is the default behaviour when there is no flag, to avoid breaking existing code
		if !(isdir(outputs_path))
		    mkdir(outputs_path)
		end
	else
		# Find closest unused ouput directory name and create it
		outputs_path = choose_output_dir(outputs_path)
		mkdir(outputs_path)
	end
    
    elapsed_time = @elapsed write_benders_output(LB_hist,UB_hist,cpu_time,feasibility_hist,outputs_path,mysetup,myinputs,planning_problem);

end

function generate_timeseries_data(
    case::AbstractString,
    settings_path::AbstractString,
    mysetup::Dict,
    number_of_scenarios::Int,
    weather_scenarios::Int,
    fuel_scenarios::Int,
    myinputs::Dict,
    tdr_exists::Bool,
)
    filenames = ["data$(i).csv" for i in 1:22] # Create list of filenames
    try
        data = read_and_preprocess_data(filenames)
    catch e
        println("Error reading data: ", e)
        exit(1)
    end

    forecast, decomp = forecast_timeseries(data)

    # Plotting
    plot(decomp, title = "Time Series Decomposition")
    savefig("decomposition.png")

    plot(forecast, title = "Forecasted Time Series")
    savefig("forecast.png")

    #Statistical Analysis
    println("Mean of Forecast: ", mean(forecast.Value))
    println("Standard Deviation of Forecast: ", std(forecast.Value))

    # Example of hypothesis testing (comparing last year of historical data to the forecast)
    last_year_data = last(decomp.seasonal, 8760).Value + last(decomp.trend, 8760).Value + last(decomp.resid, 8760).Value
    forecast_data = forecast.Value
    println("Performing a Mann-Whitney U test...")
    mw_test = MannWhitneyUTest(last_year_data, forecast_data)
    println(mw_test)
    if pvalue(mw_test) < 0.05
        println("The distributions are significantly different.")
    else
        println("The distributions are not significantly different.")
    end

    # Example of calculating prediction intervals (simplified)
    residuals_std = std(decomp.resid.Value)
    upper_bound = forecast.Value .+ 1.96 * residuals_std # 95% Confidence
    lower_bound = forecast.Value .- 1.96 * residuals_std # 95% Confidence
    plot!(forecast.Time, upper_bound, label="Upper Bound", color="green", linestyle=:dash)
    plot!(forecast.Time, lower_bound, label="Lower Bound", color="green", linestyle=:dash)

    savefig("forecast_with_intervals.png")
end