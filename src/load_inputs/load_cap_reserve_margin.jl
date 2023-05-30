@doc raw"""
	load_cap_reserve_margin(setup::Dict, path::AbstractString, inputs::Dict)

Read input parameters related to planning reserve margin constraints
"""
function load_cap_reserve_margin(setup::Dict, path::AbstractString, inputs_crm::Dict)
	# Definition of capacity reserve margin (crm) by locational deliverability area (LDA)
	inputs_crm["dfCapRes"] = DataFrame(CSV.File(joinpath(path, "Capacity_reserve_margin.csv"), header=true), copycols=true)

	# Ensure float format values:

	# Identifying # of planning reserve margin constraints for the system
	res = count(s -> startswith(String(s), "CapRes"), names(inputs_crm["dfCapRes"]))
	first_col = findall(s -> s == "CapRes_1", names(inputs_crm["dfCapRes"]))[1]
	last_col = findall(s -> s == "CapRes_$res", names(inputs_crm["dfCapRes"]))[1]
	inputs_crm["dfCapRes"] = Matrix{Float64}(inputs_crm["dfCapRes"][:,first_col:last_col])
	inputs_crm["NCapacityReserveMargin"] = res

	println("Capacity_reserve_margin.csv Successfully Read!")

	return inputs_crm
end

@doc raw"""
	load_cap_reserve_margin_trans(setup::Dict, inputs_crm::Dict, network_var::DataFrame)

Function for reading input parameters related to participation of transmission imports/exports in capacity reserve margin constraint.
"""
function load_cap_reserve_margin_trans(setup::Dict, inputs_crm::Dict, network_var::DataFrame)
	res = inputs_crm["NCapacityReserveMargin"]

	first_col_trans_derate = findall(s -> s == "DerateCapRes_1", names(network_var))[1]
	last_col_trans_derate = findall(s -> s == "DerateCapRes_$res", names(network_var))[1]
	dfDerateTransCapRes = network_var[:,first_col_trans_derate:last_col_trans_derate]
	inputs_crm["dfDerateTransCapRes"] = Matrix{Float64}(dfDerateTransCapRes[completecases(dfDerateTransCapRes),:])

	first_col_trans_excl = findall(s -> s == "CapRes_Excl_1", names(network_var))[1]
	last_col_trans_excl = findall(s -> s == "CapRes_Excl_$res", names(network_var))[1]
	dfTransCapRes_excl = network_var[:,first_col_trans_excl:last_col_trans_excl]
	inputs_crm["dfTransCapRes_excl"] = Matrix{Float64}(dfTransCapRes_excl[completecases(dfTransCapRes_excl),:])

	return inputs_crm
end
