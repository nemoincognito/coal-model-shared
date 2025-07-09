###########################################    START preamble: packages and paths ###############################
###    reading in of file also done in this section, this differs for local or cloud computing applications
# Packages
using JuMP
using DataFrames
import HiGHS
import SQLite
import Tables
import CSV
import XLSX
using Dates
const DBInterface = SQLite.DBInterface
using Alpine, Ipopt, CPLEX

### Define project paths
# Set base path, checks if I'm at home or at work
if isdir("C:/Users/jorri/OneDrive/Work") # basepath at home
    basepath = "C:/Users/jorri/OneDrive/Work"
elseif isdir("D:/OneDrive/Work") # basepath at work
    basepath = "D:/OneDrive/Work"
end
inputdatapath = "China Coal Import Markets Project -- SHARED/Data/coal-model-shared"
inputdatapath = joinpath(basepath, inputdatapath)
outputpath = joinpath(basepath, inputdatapath)
soloutputpath = joinpath(outputpath, "solutions")
thprefparaoutputpath = joinpath(outputpath, "pref para th")
ckprefparaoutputpath = joinpath(outputpath, "pref para ck")

###########################################    END preamble              ###############################
###########################################    START data import              ############################
### input file names
edges_file = joinpath(inputdatapath, "all edges vv plus costs and capa latest.xlsx")
coal_quality_file = joinpath(inputdatapath, "coal qualities summary latest.xlsx")
demand_file = joinpath(inputdatapath, "demand all latest.xlsx")
elec_capa_file = joinpath(inputdatapath, "electric capacities latest.xlsx")
port_capa_file = joinpath(inputdatapath, "port capacities latest.xlsx")
steel_capa_file = joinpath(inputdatapath, "steel prod capacities latest.xlsx")
mines_file = joinpath(inputdatapath, "prod capa cost price brand by mine latest.xlsx")
cv_blend_file = joinpath(inputdatapath, "cv blend ranges.xlsx")
mms_file = joinpath(inputdatapath, "max market share by demand node.xlsx")
chn_sb_imp_file = joinpath(inputdatapath, "max chn sb imports.xlsx")
mng_chn_edges_file = joinpath(inputdatapath, "mng chn import links.xlsx")
mng_chn_imp_cap_file = joinpath(inputdatapath, "max chn mng imports.xlsx")
pref_para_links_file  = joinpath(inputdatapath, "pref para links.xlsx")
pref_para_thermal_file  = joinpath(inputdatapath, "pref para thermal.xlsx")
pref_para_coking_file  = joinpath(inputdatapath, "pref para coking.xlsx")
pref_flow_thermal_file  = joinpath(inputdatapath, "pref flows thermal.xlsx")
pref_flow_coking_file  = joinpath(inputdatapath, "pref flows coking.xlsx")
### Read in data from file
df_nodes = DataFrame(XLSX.readtable(demand_file, 1,infer_eltypes=true))
df_edges = DataFrame(XLSX.readtable(edges_file, 1,infer_eltypes=true))
df_supply = DataFrame(XLSX.readtable(mines_file, 1,infer_eltypes=true))
df_demand = DataFrame(XLSX.readtable(demand_file, 1,infer_eltypes=true))
df_coaltypes = DataFrame(XLSX.readtable(coal_quality_file, 1,infer_eltypes=true))
df_elec_capa = DataFrame(XLSX.readtable(elec_capa_file, 1,infer_eltypes=true))
df_port_capa = DataFrame(XLSX.readtable(port_capa_file, 1,infer_eltypes=true))
df_steel_capa = DataFrame(XLSX.readtable(steel_capa_file, 1,infer_eltypes=true))
df_cv_blend_range = DataFrame(XLSX.readtable(cv_blend_file, 1,infer_eltypes=true))
df_mms = DataFrame(XLSX.readtable(mms_file, 1,infer_eltypes=true))
df_chn_max_sb_imp = DataFrame(XLSX.readtable(chn_sb_imp_file, 1,infer_eltypes=true))
df_mng_edges = DataFrame(XLSX.readtable(mng_chn_edges_file, 1,infer_eltypes=true))
df_mng_chn_imp_cap = DataFrame(XLSX.readtable(mng_chn_imp_cap_file, 1,infer_eltypes=true))
df_pref_para_links = DataFrame(XLSX.readtable(pref_para_links_file, 1,infer_eltypes=true))
df_pref_para_thermal = DataFrame(XLSX.readtable(pref_para_thermal_file, 1,infer_eltypes=true))
df_pref_para_coking = DataFrame(XLSX.readtable(pref_para_coking_file, 1,infer_eltypes=true))
df_pref_flow_thermal = DataFrame(XLSX.readtable(pref_flow_thermal_file, 1,infer_eltypes=true))
df_pref_flow_coking = DataFrame(XLSX.readtable(pref_flow_coking_file, 1,infer_eltypes=true))

###########################################    END data import              ############################
# Selected scenario settings
selected_year = 2020
selected_region = "Baseline"
selected_coaltype = "coking"
###########################################    START data prep              ##############################

# keep data for selected year only
df_nodes = filter(row -> row.year == selected_year, df_nodes)
df_edges = filter(row -> row.year == selected_year, df_edges)
df_supply = filter(row -> row.year == selected_year, df_supply)
df_demand = filter(row -> row.year == selected_year, df_demand)
df_elec_capa = filter(row -> row.year == selected_year, df_elec_capa)
df_port_capa = filter(row -> row.year == selected_year, df_port_capa)
df_steel_capa = filter(row -> row.year == selected_year, df_steel_capa)
df_cv_blend_range = filter(row -> row.year == selected_year, df_cv_blend_range)
df_chn_max_sb_imp = filter(row -> row.year == selected_year, df_chn_max_sb_imp)
df_mng_chn_imp_cap = filter(row -> row.year == selected_year, df_mng_chn_imp_cap)

##### Lists of links and nodes 
# including special types of links and nodes
# list of all coal types [coal_group]
coaltypelist = select(df_coaltypes, :coal_group)
# list of all nodes
nodelist = select(df_nodes, :node_id)
# list of all edges [origin, destination]
edgelist = select(df_edges, [:orig_node_id, :dest_node_id])
# edgedata (transport cost and capacity, as well as energy conversion efficiency per link (1 for all links apart from UHV transmisison line links and links between power plants units and demand nodes)
edge_data = select(df_edges, [:orig_node_id, :dest_node_id, :orig_node_type, :dest_node_type, :transp_cost_tot_usd, :transm_cost_usd_GJ, :cap_Mt, :conversion_eff, :origin_for_mms, :dest_for_mms])
df_elec_capa = select(df_elec_capa, [:orig_node_id, :dest_node_id, :cap_PJ_corrected])
edge_data = DataFrames.leftjoin(edge_data, df_elec_capa, on = [:orig_node_id, :dest_node_id],)
# list of all edges*resource types [origin, destination, coal_group]
flowslist = crossjoin(edgelist, coaltypelist, makeunique = true)
flowslist = leftjoin(flowslist, edge_data, on = [:orig_node_id, :dest_node_id]) 
# list of resources that can be supplied by any node. Includes all nodes*resource types, with mostly zeroes. Need thisfor constraint mass flow balance #2 [origin, resource_subtype]
supplylist = crossjoin(nodelist, coaltypelist, makeunique = true)
df_node_data = select(df_supply, [:node_id, :coal_group, :prod_capa_Mt, :total_gate_cost_usd_pt, :overhead_cost_usd_pt])
df_node_data = leftjoin(supplylist, df_node_data, on = [:node_id, :coal_group]) 
replace!(df_node_data.prod_capa_Mt, missing => 0)
replace!(df_node_data.total_gate_cost_usd_pt, missing => 0)
replace!(df_node_data.overhead_cost_usd_pt, missing => 0)
# add port and steelplant node capacities
df_port_capa = select(df_port_capa, [:node_id, :port_cap_Mt])
df_node_data = leftjoin(df_node_data, df_port_capa, on = [:node_id]) 
df_steel_capa = select(df_steel_capa, [:node_id, :steel_cap_Mt_corrected])
df_node_data = leftjoin(df_node_data, df_steel_capa, on = [:node_id]) 
# demand: calculate total thermal demand by node and keep relevant variables only
insertcols!(df_demand, :thermal_demand_PJ => df_demand.elec_demand_PJ + df_demand.other_demand_PJ)
df_demand = select(df_demand, [:node_id, :region, :thermal_demand_PJ, :steel_demand_Mt, :HCC_demand_Mt, :SCC_demand_Mt, :PCI_demand_Mt])

#=
# demand correction for identifying marginal costs in indvidual regions
replace!(df_demand.region, missing => "RoW")
if selected_coaltype == "thermal"
    df_demand[!,:thermal_demand_PJ] = ifelse.(df_demand[!,:region] .== selected_region, df_demand[!,:thermal_demand_PJ] .* 0.99, df_demand[!,:thermal_demand_PJ])    
end
if selected_coaltype == "coking"
    df_demand[!,:steel_demand_Mt] = ifelse.(df_demand[!,:region] .== selected_region, df_demand[!,:steel_demand_Mt] .* 0.99, df_demand[!,:steel_demand_Mt]) 
    df_demand[!,:HCC_demand_Mt] = ifelse.(df_demand[!,:region] .== selected_region, df_demand[!,:HCC_demand_Mt] .* 0.99, df_demand[!,:HCC_demand_Mt]) 
    df_demand[!,:SCC_demand_Mt] = ifelse.(df_demand[!,:region] .== selected_region, df_demand[!,:SCC_demand_Mt] .* 0.99, df_demand[!,:SCC_demand_Mt]) 
    df_demand[!,:PCI_demand_Mt] = ifelse.(df_demand[!,:region] .== selected_region, df_demand[!,:PCI_demand_Mt] .* 0.99, df_demand[!,:PCI_demand_Mt])     
end
=#

#=

################# MODEL INS OUTS AND CHANGES ############################
#=
Why am I doing this? So I can keep track of all the ins and outs and have a well configured function.

Ins: 
flowslist, df_pref_para_links, 
df_pref_para_thermal, 
df_pref_para_coking, 
df_node_data, 
df_coal_types, 
df_demand, 
edge_data, 
df_cv_blend_range, 
df_mms, 
df_mass_inflows_by_node_and_prod_type,
df_mng_chn_imp_cap

changes:
flowslist.mf #mass flow along each edge
df_node_data.supply_item_mass_by_node #how much to supply from where

Outs:
flowslist_select


=#

################################   START MODEL FORMULATION #############################################
# time stamp: start build    
start_build_time = now()
# Problem and solver definition
#cn_coal_model = Model(CPLEX.Optimizer)
cn_coal_model = Model(HiGHS.Optimizer)

# Problem variables
# Flows are defined as non-negative. This is needed to prevent unidirectional edges transporting goods both ways, and to have negative flows lead to negative tarnsport costs
flowslist.mf = @variable(cn_coal_model, mf[1:size(flowslist, 1)] >= 0) 
# join flow costs and coal type data
flowslist = leftjoin(flowslist, df_coaltypes, on = [:coal_group]) 
# calculate energy flows
# Only inflows should consider energy conversion efficiency for electrical transmission links. Outflows is just the total energy content
flowslist[!,:ener_inflow_by_coaltype] = flowslist[!,:mf ] .* flowslist[!,:CV_PJ_p_Mt_therm] .* flowslist[!,:conversion_eff]
flowslist[!,:ener_outflow_by_coaltype] = flowslist[!,:mf ] .* flowslist[!,:CV_PJ_p_Mt_therm]
# add preference parameters
df_pref_para = leftjoin(df_pref_para_links, df_pref_para_thermal, on = [:orig_grp, :dest_grp, :product_type]) 
df_pref_para = leftjoin(df_pref_para, df_pref_para_coking, on = [:orig_grp, :dest_grp, :product_type]) 
replace!(df_pref_para.pref_para_thermal, missing => 0)
replace!(df_pref_para.pref_para_coking, missing => 0)
df_pref_para.pref_para = df_pref_para.pref_para_thermal .+ df_pref_para.pref_para_coking

# and add to flowslist
df_pref_para = select(df_pref_para, [:orig_node_id, :dest_node_id, :product_type, :pref_para])
flowslist = leftjoin(flowslist, df_pref_para, on = [:orig_node_id, :dest_node_id, :product_type]) 
replace!(flowslist.pref_para, missing => 0)

### Constraint: Mass Balance pt1: 
# Nodes cannot supply coal types they do not have, i.e., smaller or equal to supply capacity
# Supply also must be >0 (prevents model suggesting negative supply at negative costs)
df_node_data.supply_item_mass_by_node = @variable(cn_coal_model, s[1:size(df_node_data, 1)] >= 0)
set_upper_bound.(df_node_data.supply_item_mass_by_node, df_node_data.prod_capa_Mt)
# create a binary variable that is 1 if there is any supply from a node, otherwise zero. Will be multiplied by fixed cost parameter for each mine
df_node_data.binary_supply = @variable(cn_coal_model, b[1:size(df_node_data, 1)], Bin)

# Create a constraint such that node supply has to be greater than the binary of supply being 0 for no supply and 1 for any supply
@constraint(cn_coal_model, df_node_data.supply_item_mass_by_node >= df_node_data.binary_supply)
# join coal type data
df_node_data = DataFrames.leftjoin(
    df_node_data,
    df_coaltypes,
    on = [:coal_group],
)
# create supply as energy content for use in energy balance constraint
df_node_data[!,:ener_supply_by_coaltype] = df_node_data[!,:supply_item_mass_by_node] .* df_node_data[!,:CV_PJ_p_Mt_therm]

### Constraint: Mass Balance pt2 and energy balance
## mass balance: supply + flow in <= flow out
# table with sum of mass flows by coaltype out of each node
df_mass_flow_out = DataFrames.DataFrame(
    (node_id = i.orig_node_id, coal_group = i.coal_group, outflow_mass = sum(df.mf)) for
    (i, df) in pairs(DataFrames.groupby(flowslist, [:orig_node_id, :coal_group]))
)
# table with sum of mass flows by coaltype into each node
df_mass_flow_in = DataFrames.DataFrame(
    (node_id = i.dest_node_id, coal_group = i.coal_group, inflow_mass = sum(df.mf)) for
    (i, df) in pairs(DataFrames.groupby(flowslist, [:dest_node_id, :coal_group]))
)
# join mass in and outflows into node_data df
df_node_data = DataFrames.leftjoin(
    df_node_data,
    df_mass_flow_in,
    on = [:node_id, :coal_group],
)
df_node_data = DataFrames.leftjoin(
    df_node_data,
    df_mass_flow_out,
    on = [:node_id, :coal_group],
)
# join demand
df_node_data = DataFrames.leftjoin(
    df_node_data,
    df_demand,
    on = [:node_id],
)
replace!(df_node_data.thermal_demand_PJ, missing => 0)
replace!(df_node_data.steel_demand_Mt, missing => 0)
replace!(df_node_data.HCC_demand_Mt, missing => 0)
replace!(df_node_data.SCC_demand_Mt, missing => 0)
replace!(df_node_data.PCI_demand_Mt, missing => 0)

# constraint: mass balance by coaltype for all nodes
# Note demand is dealt with elsewhere: demand is in energy content, not mass, for thermal coal
# We have several different types of coking coal to deal with as well meaning adding demand here is just not the most straghtforward
# there is no outflow possible from any final demand node so this does not cause trouble with that
@constraint(
    cn_coal_model,
    [r in eachrow(df_node_data)],
    coalesce(r.supply_item_mass_by_node, 0.0) + coalesce(r.inflow_mass, 0.0) >=
    coalesce(r.outflow_mass, 0.0),
);

# constraint: energy balance for both Chinese and international demand nodes
# select only rows with any thermal demand here to save some calculations and memory
df_energy_demand = select(filter(row -> row.thermal_demand_PJ >0, df_demand), [:node_id, :thermal_demand_PJ])
# and sum supply/inflows/outflows again, over different coaltypes. For inflows, consider energy conversion effciency
df_ener_supply = DataFrames.DataFrame(
    (node_id = i.node_id, supply_ener = sum(df.ener_supply_by_coaltype)) for
    (i, df) in pairs(DataFrames.groupby(df_node_data, [:node_id]))
)
df_ener_flow_in = DataFrames.DataFrame(
    (node_id = i.dest_node_id, inflow_ener = sum(df.ener_inflow_by_coaltype)) for
    (i, df) in pairs(DataFrames.groupby(flowslist, [:dest_node_id]))
)
df_ener_flow_out = DataFrames.DataFrame(
    (node_id = i.orig_node_id, outflow_ener = sum(df.ener_outflow_by_coaltype)) for
    (i, df) in pairs(DataFrames.groupby(flowslist, [:orig_node_id]))
)
# join supply, inflows, outflows
df_energy_demand = DataFrames.leftjoin(
    df_energy_demand,
    df_ener_supply,
    on = [:node_id],
)
df_energy_demand = DataFrames.leftjoin(
    df_energy_demand,
    df_ener_flow_in,
    on = [:node_id],
)
df_energy_demand = DataFrames.leftjoin(
    df_energy_demand,
    df_ener_flow_out,
    on = [:node_id],
)
# and now create energy balance constraint: supply + flow in <= flow out + demand
@constraint(
    cn_coal_model,
    [r in eachrow(df_energy_demand)],
    coalesce(r.supply_ener, 0.0) + coalesce(r.inflow_ener, 0.0) >=
    coalesce(r.outflow_ener, 0.0) + coalesce(r.thermal_demand_PJ, 0.0),
);

### Coking coal block 1
# combine HCC demand in Chinese and foreign nodes
# Chinese demand is included as steel demand, which can be translated to 0.563 Mt of HCC demand
df_node_data[!,:HCC_demand_Mt] = df_node_data[!,:steel_demand_Mt] .* 0.563 .+ df_node_data[!,:HCC_demand_Mt] 

# constraint: HCC demand in Chinese intenational nodes must be met
# select only rows with any coking coal demand here to save some calculations and memory
df_HCC_demand = filter(row -> row.HCC_demand_Mt >0 && row.coal_group=="HCC_XXX", df_node_data)
@constraint(
    cn_coal_model,
    [r in eachrow(df_HCC_demand)],
    coalesce(r.supply_item_mass_by_node, 0.0) + coalesce(r.inflow_mass, 0.0) >=
    coalesce(r.outflow_mass, 0.0) + coalesce(r.HCC_demand_Mt, 0.0),
);
# constraint: SCC demand in intenational nodes must be met
# select only rows with any coking coal demand here to save some calculations and memory
df_SCC_demand = filter(row -> row.SCC_demand_Mt >0 && row.coal_group=="SCC_XXX", df_node_data)

@constraint(
    cn_coal_model,
    [r in eachrow(df_SCC_demand)],
    coalesce(r.supply_item_mass_by_node, 0.0) + coalesce(r.inflow_mass, 0.0) >=
    coalesce(r.outflow_mass, 0.0) + coalesce(r.SCC_demand_Mt, 0.0),
);
# constraint: PCI demand in intenational nodes must be met
# select only rows with any coking coal demand here to save some calculations and memory
df_PCI_demand = filter(row -> row.PCI_demand_Mt >0 && row.coal_group=="PCI_XXX", df_node_data)
@constraint(
    cn_coal_model,
    [r in eachrow(df_PCI_demand)],
    coalesce(r.supply_item_mass_by_node, 0.0) + coalesce(r.inflow_mass, 0.0) >=
    coalesce(r.outflow_mass, 0.0) + coalesce(r.PCI_demand_Mt, 0.0),
);

### Coking coal block 2: make sure Chinese steel mills use a predefined recipe or mix of HCC, SCC and PCI
# specifically 0.563 t of HCC, 0.182 t of SCC, and 0.191 t of PCI
df_chn_steelplant_flows_HCC = select(filter(row -> row.orig_node_type == "stpt" && row.dest_node_type=="stdc" && row.coal_group=="HCC_XXX", flowslist), :orig_node_id, :dest_node_id, :mf)
df_chn_steelplant_flows_SCC = select(filter(row -> row.orig_node_type == "stpt" && row.dest_node_type=="stdc" && row.coal_group=="SCC_XXX", flowslist), :orig_node_id, :dest_node_id, :mf)
df_chn_steelplant_flows_PCI = select(filter(row -> row.orig_node_type == "stpt" && row.dest_node_type=="stdc" && row.coal_group=="PCI_XXX", flowslist), :orig_node_id, :dest_node_id, :mf)
rename!(df_chn_steelplant_flows_HCC,:mf => :massflow_HCC)
rename!(df_chn_steelplant_flows_SCC,:mf => :massflow_SCC)
rename!(df_chn_steelplant_flows_PCI,:mf => :massflow_PCI)
# put flows of HCC SCC and PCI together 
df_chn_steelplant_flows = DataFrames.leftjoin(
    df_chn_steelplant_flows_HCC,
    df_chn_steelplant_flows_SCC,
    on = [:orig_node_id, :dest_node_id],
)
df_chn_steelplant_flows = DataFrames.leftjoin(
    df_chn_steelplant_flows,
    df_chn_steelplant_flows_PCI,
    on = [:orig_node_id, :dest_node_id],
)
# and define constraint saying all Chinese steel plants must also send 0.182 / 0.563 t SCC to the steel demand center for every ton of HCC they send to this demand center
@constraint(
    cn_coal_model,
    [r in eachrow(df_chn_steelplant_flows)],
    coalesce(r.massflow_SCC, 0.0) / 0.182 >=
    coalesce(r.massflow_HCC, 0.0) / 0.563,
);
# and define constraint saying all Chinese steel plants must also send 0.191 / 0.563 t PCI to the steel demand center for every ton of HCC they send to this demand center
@constraint(
    cn_coal_model,
    [r in eachrow(df_chn_steelplant_flows)],
    coalesce(r.massflow_PCI, 0.0) / 0.191 >=
    coalesce(r.massflow_HCC, 0.0) / 0.563,
);

### Constraint: transport capacity of each edge cannot be exceeded
# Total flows of all types of coal over each edge cannot exceed the edges' transport capacity
# sum all flows per link
df_massflow_by_link = DataFrames.DataFrame(
    (orig_node_id = i.orig_node_id, dest_node_id = i.dest_node_id, massflow_over_link_tot = sum(df.mf)) for
    (i, df) in pairs(DataFrames.groupby(flowslist, [:orig_node_id, :dest_node_id]))
)
# hook up with edge data for edge capacity
df_massflow_by_link = DataFrames.leftjoin(
    edge_data,
    df_massflow_by_link,
    on = [:orig_node_id, :dest_node_id],
)
# minimise dataframe size to all info needed
df_massflow_by_link = select(dropmissing(df_massflow_by_link, :cap_Mt),:orig_node_id, :dest_node_id, :cap_Mt, :massflow_over_link_tot)
# and set constraint: total flow over each link cannot exceed link capacity
@constraint(
    cn_coal_model,
    [r in eachrow(df_massflow_by_link)],
    r.massflow_over_link_tot <= r.cap_Mt,
);

### Constraint: transmission capacity of electrical edges cannot be exceeded
# Note that transmisison capacities are only limited for edges from power plant unit to elec demand center and for UHV lines
# Each edge basically has physical (Mt) and energy flows (GJ) capacities, but only one is constrained for any edge
# Total flows of all types of coal multiplied with energy content over each edge cannot exceed the edges' transmission capacity
# This simultaneously deals with power plant generation capacity as outgoing edges are constrained in transmission capacity
# sum all flows per link
df_enerflow_by_link = DataFrames.DataFrame(
    (orig_node_id = i.orig_node_id, dest_node_id = i.dest_node_id, enerflow_over_link_tot = sum(df.ener_inflow_by_coaltype)) for
    (i, df) in pairs(DataFrames.groupby(flowslist, [:orig_node_id, :dest_node_id]))
)
# hook up with edge data for edge capacity
df_enerflow_by_link = DataFrames.leftjoin(
    edge_data,
    df_enerflow_by_link,
    on = [:orig_node_id, :dest_node_id],
)
# minimise dataframe size to all info needed
df_enerflow_by_link = select(dropmissing(df_enerflow_by_link, :cap_PJ_corrected),:orig_node_id, :dest_node_id, :cap_PJ_corrected, :enerflow_over_link_tot)
# and set constraint: total flow over each link cannot exceed link electrical transmission capacity
@constraint(
    cn_coal_model,
    [r in eachrow(df_enerflow_by_link)],
    r.enerflow_over_link_tot <= r.cap_PJ_corrected,
);

### Constraint: port capacity of each node cannot be exceeded
# Constraint defined as maximum amount of coal (Mt) leaving a port cannot exceed its annual capacity
df_port_nodes = select(dropmissing(df_node_data, :port_cap_Mt),:node_id, :outflow_mass, :port_cap_Mt)
@constraint(
    cn_coal_model,
    [r in eachrow(df_port_nodes)],
    r.outflow_mass <= r.port_cap_Mt,
);
### Constraint: steel plant capacity of each node cannot be exceeded
# Constraint defined as maximum amount of HCC leaving a steel plant exceed its annual steelmaking capacity * 0.563
# 0.563 is the amount of HCC per ton of steel needed
df_steelplant_nodes = select(filter(row -> row.coal_group=="HCC_XXX", df_node_data), :node_id, :coal_group, :outflow_mass, :steel_cap_Mt_corrected)
df_steelplant_nodes = select(dropmissing(df_steelplant_nodes, :steel_cap_Mt_corrected),:node_id, :outflow_mass, :steel_cap_Mt_corrected)
@constraint(
    cn_coal_model,
    [r in eachrow(df_steelplant_nodes)],
    r.outflow_mass <= r.steel_cap_Mt_corrected * 0.563,
);

### CV blend range mimima and maxima
# sum inflow*CV and sum inflows. Then set constraints as cv max => inflow*CV / sum inflows and cv min <= inflow*CV / sum inflows
# this works because no powerplant or international thermal demand node will see inflows of anything but thermal coal
df_node_data[!,:CV_x_Mt] = df_node_data[!,:CV_bin_kcal_kg] .* df_node_data[!,:inflow_mass] 
# sum inflows and inflows * CV value
df_cv_inflows_by_node = DataFrames.DataFrame(
    (node_id = i.node_id, CV_x_Mt = sum(df.CV_x_Mt)) for
    (i, df) in pairs(DataFrames.groupby(df_node_data, [:node_id]))
)
df_mass_inflows_by_node = DataFrames.DataFrame(
    (node_id = i.node_id, inflow_mass = sum(df.inflow_mass)) for
    (i, df) in pairs(DataFrames.groupby(df_node_data, [:node_id]))
)
# join with blend range max/min sheet
df_cv_blend_range = DataFrames.leftjoin(df_cv_blend_range, df_cv_inflows_by_node, on = [:node_id],)
df_cv_blend_range = DataFrames.leftjoin(df_cv_blend_range, df_mass_inflows_by_node, on = [:node_id],)
# and set constraints. Have to multiply right side with r.inflow_mass here as dividing lefthand by r.inflow_mass is not a allowed operation
@constraint(
    cn_coal_model,
    [r in eachrow(df_cv_blend_range)],
    r.CV_x_Mt >= r.minCVavg * r.inflow_mass,
);
@constraint(
    cn_coal_model,
    [r in eachrow(df_cv_blend_range)],
    r.CV_x_Mt <= r.maxCVavg * r.inflow_mass,
);

### Constraint: max market shares from international suppliers for key international demand nodes
# this limits how much of either thermal or met coal any of these countries can import form a single origin, limiting dependency
# grab only relevant flows
df_mms_flows = DataFrames.leftjoin(df_mms, flowslist, on = [:node_id => :dest_node_id, :product_type],)
# sum both total inflows bynode * product type as well total inflows by node * product type * origin
df_mass_inflows_by_node_and_prod_type = DataFrames.DataFrame(
    (node_id = i.node_id, product_type = i.product_type, inflow_mass_type = sum(df.mf)) for
    (i, df) in pairs(DataFrames.groupby(df_mms_flows, [:node_id, :product_type]))
)
df_mass_inflows_by_node_prod_type_and_org = DataFrames.DataFrame(
    (node_id = i.node_id, product_type = i.product_type, origin_for_mms = i.origin_for_mms, inflow_mass_type_org = sum(df.mf)) for
    (i, df) in pairs(DataFrames.groupby(df_mms_flows, [:node_id, :product_type, :origin_for_mms]))
)
# hook up with df with nodes that have max markets share limits
df_mms = DataFrames.leftjoin(df_mms, df_mass_inflows_by_node_and_prod_type, on = [:node_id, :product_type],)
df_mms = DataFrames.leftjoin(df_mms, df_mass_inflows_by_node_prod_type_and_org, on = [:node_id, :product_type],)
# and define constraint
@constraint(
    cn_coal_model,
    [r in eachrow(df_mms)],
    r.inflow_mass_type_org <= r.inflow_mass_type * r.max_ms,
);

### Constraint: max Chinese seaborne imports (defined in Mt not shares)
# grab only relevant flows
df_chn_imports = select(dropmissing(flowslist, :dest_for_mms), :dest_node_id, :mf, :product_type, :dest_for_mms)

# sum all Chinese seaborne import flows
df_chn_imports = DataFrames.DataFrame(
    (product_type = i.product_type, chn_sb_imports_Mt = sum(df.mf)) for
    (i, df) in pairs(DataFrames.groupby(df_chn_imports, [:product_type]))
)
# join with data on max seaborne import levels
df_chn_max_sb_imp = DataFrames.leftjoin(df_chn_max_sb_imp, df_chn_imports, on = [:product_type],)
# and set constraint
@constraint(
    cn_coal_model,
    [r in eachrow(df_chn_max_sb_imp)],
    r.chn_sb_imports_Mt <= r.max_imp,
);

### Constraint: max Chinese imports from Mongolia (defined in Mt not shares)
# grab only relevant flows (preselected in build files created with R)
df_chn_mng_imports = DataFrames.leftjoin(df_mng_edges, flowslist, on = [:orig_node_id, :dest_node_id],)
# sum all Chinese imports from Mongolia
df_chn_mng_imports.fake_group_var .= "smth" #just a helper var to help with summing
df_chn_mng_imports = DataFrames.DataFrame(
    (fake_group_var = i.fake_group_var, chn_mng_imports_Mt = sum(df.mf)) for
    (i, df) in pairs(DataFrames.groupby(df_chn_mng_imports, [:fake_group_var]))
)
# join with data on max mongolian seaborne import levels
df_mng_chn_imp_cap = DataFrames.crossjoin(df_mng_chn_imp_cap, df_chn_mng_imports)
# and set constraint
@constraint(
    cn_coal_model,
    [r in eachrow(df_mng_chn_imp_cap)],
    r.chn_mng_imports_Mt <= r.max_mng_imp,
);

# define model objective
@objective(
    cn_coal_model,
    Min,
    sum(((r.total_gate_cost_usd_pt-r.overhead_cost_usd_pt) * r.supply_item_mass_by_node + r.overhead_cost_usd_pt * r.prod_capa_Mt * r.binary_supply) * 1e6 for r in eachrow(df_node_data)) +
    sum(r.transp_cost_tot_usd * r.mf  * 1e6 for r in eachrow(flowslist)) + 
    sum(r.pref_para * r.mf  * 1e6 for r in eachrow(flowslist)) + 
    sum(r.transm_cost_usd_GJ * 1e6 * r.mf  * 1e6 * r.CV_PJ_p_Mt_therm for r in eachrow(flowslist))
);
# time stamp: finish build    
end_build_time = now()
# And optimize the model:
optimize!(cn_coal_model)
end_solve_time = now()
#build_time = end_build_time - start_build_time
#solve_time = end_solve_time - end_build_time
total_time = end_solve_time - start_build_time
print(total_time)

############################## END MODEL BUILD #####################################

# put it in one df. Could have been done earlier probably. Dont care
# hook up supply to flows sheet
df_node_data.supply_item_mass_by_node = value.(df_node_data.supply_item_mass_by_node)
df_node_data_select = select(filter(row -> row.supply_item_mass_by_node >0, df_node_data), :node_id, :coal_group, :total_gate_cost_usd_pt)
flowslist = DataFrames.leftjoin(flowslist, df_node_data_select, on = [:orig_node_id => :node_id, :coal_group],)
# hook up regions
df_node_regions = unique(select(df_node_data, :node_id, :region))
flowslist = DataFrames.leftjoin(flowslist, df_node_regions, on = [:dest_node_id => :node_id],)
# print solution to file
# Write solution to
solutionxlsxfilename = string("solution latest.xlsx")
solutionxlsxfile = joinpath(outputpath, solutionxlsxfilename)
flowslist.mf = value.(flowslist.mf)
flowslist_select = select(filter(row -> row.mf !=0, flowslist), :orig_node_id, :dest_node_id, :region, :coal_group, :product_type, :mf, :total_gate_cost_usd_pt, :transp_cost_tot_usd, :CV_PJ_p_Mt_therm, :transm_cost_usd_GJ)
XLSX.writetable(solutionxlsxfile, collect(eachcol(flowslist_select)), names(flowslist_select), overwrite=true)

### adjust coking coal pref para
# find largest deviation for coking coal
df_coking_calib = leftjoin(flowslist_select, df_pref_para_links, on = [:orig_node_id, :dest_node_id, :product_type])
df_coking_calib = select(filter(row -> row.product_type =="Metallurgical", df_coking_calib), [:orig_node_id, :dest_node_id, :orig_grp, :dest_grp, :product_type, :mf])
df_coking_calib = dropmissing(df_coking_calib, :orig_grp)
# sum all flows per link
df_coking_calib = DataFrames.DataFrame(
    (orig_grp = i.orig_grp, dest_grp = i.dest_grp, mf = sum(df.mf)) for
    (i, df) in pairs(DataFrames.groupby(df_coking_calib, [:orig_grp, :dest_grp]))
)
# add observed values
df_coking_calib = leftjoin(df_pref_flow_coking, df_coking_calib, on = [:orig_grp, :dest_grp])
replace!(df_coking_calib.mf, missing => 0)
df_coking_calib.mf = round.(df_coking_calib.mf; digits = 3)
df_coking_calib.flow_diff = df_coking_calib.mf .- df_coking_calib.pref_flow_Mt
df_coking_calib.flow_diff_abs = abs.(df_coking_calib.flow_diff)
df_coking_calib.max .= maximum(df_coking_calib.flow_diff_abs)
coking_max_dev = maximum(df_coking_calib.flow_diff_abs)
# dumb mess because ifelse statement are completely impossible
df_coking_calib[!,:pref_para_adj] .= 0.1
df_coking_calib[!,:pref_para_multiplier] .= 1
df_coking_calib[!,:pref_para_converged] .= 1
df_coking_calib[df_coking_calib.flow_diff_abs .!= df_coking_calib.max, :pref_para_adj] .= 0
df_coking_calib[df_coking_calib.flow_diff .<= 0, :pref_para_multiplier] .= -1
df_coking_calib[df_coking_calib.max .<= 2, :pref_para_converged] .= 0 # once differenes are below 2 Mt, stop adjusting pref para
df_coking_calib.pref_para_adj = df_coking_calib.pref_para_adj .* df_coking_calib.pref_para_multiplier .* df_coking_calib.pref_para_converged
df_coking_calib = select(df_coking_calib, [:orig_grp, :dest_grp, :product_type, :pref_para_adj])
# and now hook up with pref para df to create new dataframe
df_pref_para_coking  = leftjoin(df_pref_para_coking, df_coking_calib, on = [:orig_grp, :dest_grp, :product_type])
df_pref_para_coking.pref_para_coking = df_pref_para_coking.pref_para_coking .+ df_pref_para_coking.pref_para_adj
df_pref_para_coking = select(df_pref_para_coking, [:orig_grp, :dest_grp, :product_type, :pref_para_coking])
# and save to file
prefparaxlsxfilename = string("pref para coking.xlsx")
prefparaxlsxfile = joinpath(outputpath, prefparaxlsxfilename)
XLSX.writetable(prefparaxlsxfile, collect(eachcol(df_pref_para_coking)), names(df_pref_para_coking), overwrite=true)
# copy of solution file with a datestamp
prefparaxlsxfilename = string("pref para coking ", round(coking_max_dev, digits=2), " Mt ", Dates.format(now(), "yyyy-mm-dd HH-MM-SS"), ".xlsx")
prefparaxlsxfile = joinpath(ckprefparaoutputpath, prefparaxlsxfilename)
XLSX.writetable(prefparaxlsxfile, collect(eachcol(df_pref_para_coking)), names(df_pref_para_coking), overwrite=true)

### adjust thermal coal pref para
# find largest deviation for thermal coal
df_thermal_calib = leftjoin(flowslist_select, df_pref_para_links, on = [:orig_node_id, :dest_node_id, :product_type])
df_thermal_calib = select(filter(row -> row.product_type =="Thermal", df_thermal_calib), [:orig_node_id, :dest_node_id, :orig_grp, :dest_grp, :product_type, :mf])
df_thermal_calib = dropmissing(df_thermal_calib, :orig_grp)
# sum all flows per link
df_thermal_calib = DataFrames.DataFrame(
    (orig_grp = i.orig_grp, dest_grp = i.dest_grp, mf = sum(df.mf)) for
    (i, df) in pairs(DataFrames.groupby(df_thermal_calib, [:orig_grp, :dest_grp]))
)
# add observed values
df_thermal_calib = leftjoin(df_pref_flow_thermal, df_thermal_calib, on = [:orig_grp, :dest_grp])
replace!(df_thermal_calib.mf, missing => 0)
df_thermal_calib.mf = round.(df_thermal_calib.mf; digits = 3)
# recalibrate for thermal coal CV differences
df_thermal_factor=groupby(df_thermal_calib, :dest_grp)
df_thermal_factor=combine(df_thermal_factor, :mf => sum, :pref_flow_Mt => sum)
df_thermal_factor.th_factor = df_thermal_factor.pref_flow_Mt_sum ./ df_thermal_factor.mf_sum
df_thermal_factor[df_thermal_factor.dest_grp .== "China", :th_factor] .= 1
df_thermal_factor = select(df_thermal_factor, [:dest_grp, :th_factor])
# rejoin with calib df
df_thermal_calib = leftjoin(df_thermal_calib, df_thermal_factor, on = [:dest_grp])
df_thermal_calib.mf = df_thermal_calib.mf .* df_thermal_calib.th_factor
df_thermal_calib.flow_diff = df_thermal_calib.mf .- df_thermal_calib.pref_flow_Mt
df_thermal_calib.flow_diff_abs = abs.(df_thermal_calib.flow_diff)
df_thermal_calib.max .= maximum(df_thermal_calib.flow_diff_abs)
thermal_max_dev = maximum(df_thermal_calib.flow_diff_abs)
# dumb mess because ifelse statement are completely impossible
df_thermal_calib[!,:pref_para_adj] .= 0.1
df_thermal_calib[!,:pref_para_multiplier] .= 1
df_thermal_calib[!,:pref_para_converged] .= 1
df_thermal_calib[df_thermal_calib.flow_diff_abs .!= df_thermal_calib.max, :pref_para_adj] .= 0
df_thermal_calib[df_thermal_calib.flow_diff .<= 0, :pref_para_multiplier] .= -1
df_thermal_calib[df_thermal_calib.max .<= 5, :pref_para_converged] .= 0 # once differenes are below 2 Mt, stop adjusting pref para
df_thermal_calib.pref_para_adj = df_thermal_calib.pref_para_adj .* df_thermal_calib.pref_para_multiplier .* df_thermal_calib.pref_para_converged
df_thermal_calib = select(df_thermal_calib, [:orig_grp, :dest_grp, :product_type, :pref_para_adj])
# and now hook up with pref para df to create new dataframe
df_pref_para_thermal  = leftjoin(df_pref_para_thermal, df_thermal_calib, on = [:orig_grp, :dest_grp, :product_type])
df_pref_para_thermal.pref_para_thermal = df_pref_para_thermal.pref_para_thermal .+ df_pref_para_thermal.pref_para_adj
df_pref_para_thermal = select(df_pref_para_thermal, [:orig_grp, :dest_grp, :product_type, :pref_para_thermal])
# and save to file
prefparaxlsxfilename = string("pref para thermal.xlsx")
prefparaxlsxfile = joinpath(outputpath, prefparaxlsxfilename)
XLSX.writetable(prefparaxlsxfile, collect(eachcol(df_pref_para_thermal)), names(df_pref_para_thermal), overwrite=true)
# copy of solution file with a datestamp
prefparaxlsxfilename = string("pref para thermal ", round(thermal_max_dev, digits=2), " Mt ", Dates.format(now(), "yyyy-mm-dd HH-MM-SS"), ".xlsx")
prefparaxlsxfile = joinpath(thprefparaoutputpath, prefparaxlsxfilename)
XLSX.writetable(prefparaxlsxfile, collect(eachcol(df_pref_para_thermal)), names(df_pref_para_thermal), overwrite=true)
# copy of solution file with a datestamp and values of thermla and coking gap 
solutionxlsxfilename = string("sol ", round(thermal_max_dev, digits=2), " Mt th ", round(coking_max_dev, digits=2), " Mt ck ", Dates.format(now(), "yyyy-mm-dd HH-MM-SS"), ".xlsx")
solutionxlsxfile = joinpath(soloutputpath, solutionxlsxfilename)
XLSX.writetable(solutionxlsxfile, collect(eachcol(flowslist_select)), names(flowslist_select), overwrite=true)
