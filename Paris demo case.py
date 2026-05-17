# %% [markdown]
# # WSIMOD model demonstration - Paris case study (.py)
# # Adapted from the paris case study [docs/demo/scripts](https://github.com/barneydobson/wsi/blob/main/docs/demo/scripts/paris_demo.py)
#
# 1. [Introduction](#we-will-cover-a-demo-wsimod-case-study)
#
# 2. [Data](#imports-and-forcing-data)
#
# 3. [Nodes](#create-nodes)
#
#     3.1 [Freshwater Treatment Works](#freshwater-treatment-works)
#
#     3.2 [Land](#land)
#
#     3.3 [Demand](#residential-demand)
#
#     3.4 [Reservoir](#reservoir)
#
#     3.5 [Distribution](#distribution)
#
#     3.6 [Wastewater Treatment Works](#wastewater-treatment-works)
#
#     3.7 [Sewers](#sewers)
#
#     3.8 [Groundwater](#groundwater)
#
#     3.9 [Node list](#create-a-nodelist)
#
# 4. [Arcs](#arcs)
#
#     4.1 [Arc parameters](#arc-parameters)
#
#     4.2 [Create the arcs](#create-arcs)
#
# 5. [Mapping](#mapping)
#
# 6. [Orchestration](#orchestration)
#
#     6.1 [Orchestrating an individual timestep](#orchestrating-an-individual-timestep)
#
#     6.2 [Ending a timestep](#ending-to-timestep)
#
# 7. [Model object](#model-object)
#
#     7.1 [Validation](#validation-plots)
# %% [markdown]
# ## We will cover a demo WSIMOD case study
#
# The glamorous town of paris will be our demo case study.
# Below, we will create these nodes and arcs, orchestrate them into a model, and run simulations.
#
# ![alt text](./../images/paris.svg)
#
# Although GIS is pretty, the schematic below is a more accurate representation of what will be created.
# WSIMOD treats everything as a node or an arc.
#
# ![alt text](./../images/schematic.svg)
#

# %% [markdown]
# ## Imports and forcing data

# %% [markdown]
# Import packages
# %%

import os

import pandas as pd

from wsimod.arcs.arcs import Arc
from wsimod.core import constants
from wsimod.nodes.catchment import Catchment
from wsimod.nodes.demand import ResidentialDemand
from wsimod.nodes.land import Land
from wsimod.nodes.nodes import Node
from wsimod.nodes.sewer import Sewer
from wsimod.nodes.storage import Groundwater, Reservoir
from wsimod.nodes.waste import Waste
from wsimod.nodes.wtw import FWTW, WWTW
from wsimod.orchestration.model import Model

os.environ["USE_PYGEOS"] = "0"
import geopandas as gpd
from matplotlib import pyplot as plt
from shapely.geometry import LineString

# %% [markdown]
# Load input data
# %%
# unit for the input data is as follows:
# flow: m3/s
# precipitation: mm/day
# et0: mm/day
# temperature: degree C
# Select the root path for the data folder. Use the appropriate value for your case.
data_folder = os.path.join(os.path.abspath("./../../../"), "docs", "demo", "data_paris")

input_fid = os.path.join(data_folder, "processed", "timeseries_data_paris.csv")
input_data = pd.read_csv(input_fid, sep=";")

#%%


input_data = input_data.loc[input_data.variable.isin(["flow", "precipitation", "et0", "temperature"])]
input_data.loc[input_data.variable == "flow", "value"] *= constants.M3_S_TO_M3_DT
input_data.loc[input_data.variable == "precipitation", "value"] *= constants.MM_TO_M
input_data.loc[input_data.variable == "et0", "value"] *= constants.MM_TO_M
input_data.date = pd.to_datetime(input_data.date)
data_input_dict = input_data.set_index(["variable", "date"]).value.to_dict()
data_input_dict = (
    input_data.groupby("site")
    .apply(lambda x: x.set_index(["variable", "date"]).value.to_dict())
    .to_dict()
)
print(input_data.sample(10))
# %% [markdown]

# %% [markdown]
# We select dates that are available in the input data

# %%


dates = input_data.date.unique()
dates = dates[dates.argsort()]
dates = [pd.Timestamp(x) for x in dates]
print(dates[0:10])
# %% [markdown]
# We can specify the pollutants.
# In this example we choose based on what pollutants we have input data for.
# %%


constants.POLLUTANTS = ["temperature"]
constants.NON_ADDITIVE_POLLUTANTS = ["temperature"]
constants.ADDITIVE_POLLUTANTS = []
constants.FLOAT_ACCURACY = 1e-11
print(constants.POLLUTANTS)


# %% [markdown]
# ## Create nodes

# %% [markdown]
# For [waste nodes](./../../../reference-other/#wsimod.nodes.waste.Waste),
# no parameters are needed, they are just the model outlet
# %%
downstream_outlet = Waste(name="downstream_outlet")

# %% [markdown]
# For junctions and abstraction locations, we can simply use the default
# [nodes](./../../../reference-nodes/#wsimod.nodes.nodes)
# %%
abstraction = Node(name="abstraction")
water_intake = Node(name="water_intake_seine")
downstream_mixer = Node(name="downstream_mixer")
# %% [markdown]
# For [catchment nodes](./../../../reference-other/#wsimod.nodes.catchment.Catchment),
# we only need to specify the input data (as a dictionary format).
# %%
seine_upstream = Catchment(name="river", data_input_dict=data_input_dict["river"])

# %% [markdown]
# We can see that, even though we provided mimimal information (name and input data) each node comes with many predefined functions.
# %%
print(dir(seine_upstream))

# %% [markdown]
# ### Freshwater treatment works
# Each type of node uses different parameters (see [API reference](./../../../../reference)).
# Below we create a [freshwater treatment works (FWTW)](./../../../reference-wtw/#wsimod.nodes.wtw.FWTW)

# %%
# TODO: change this to Paris FWTW parameters when you have them
paris_fwtw = FWTW(
    service_reservoir_storage_capacity=1e5,
    service_reservoir_storage_area=2e4,
    treatment_throughput_capacity=4.5e4,
    name="paris_fwtw",
)

# %% [markdown]
# Each node type has different types of functionality available
# %%

print(dir(paris_fwtw))

# %% [markdown]
# The FWTW node has a tank representing the service reservoirs, we can see that it has been initialised empty.

# %%

print(paris_fwtw.service_reservoir_tank.storage)

# %% [markdown]
# If we try to pull water from the FWTW, it responds that there is no water to pull.

# %%

print(paris_fwtw.pull_check({"volume": 10}))

# %% [markdown]
# If we add in some water, we see the pull check responds that water is available.

# %%

paris_fwtw.service_reservoir_tank.storage["volume"] += 25
print(paris_fwtw.pull_check({"volume": 10}))

# %% [markdown]
# When we set a pull request, we see that we successfully receive the water and the tank is updated.

# %%


reply = paris_fwtw.pull_set({"volume": 10})
print(reply)
print(paris_fwtw.service_reservoir_tank.storage)

# %% [markdown]
# ### Land
# We will now create a [land node](./../../../reference-land/#wsimod.nodes.land.Land),
# it is a bit involved so you might want to skip ahead to [demand](#Residential-demand),
# or check out the [land node tutorial](./../land_demo)
# %% [markdown]
# Data inputs are a single dictionary

# %%

land_inputs = data_input_dict["paris_land"]

# %% [markdown]
# Plot land inputs (precipitation, et0, temperature), the model takes units of m or deg C
# %%
fig, axes = plt.subplots(3, 1, figsize=(10, 10), sharex=True)
for i, var in enumerate(["precipitation", "et0", "temperature"]):
    var_data = input_data[(input_data.site == "paris_land") & (input_data.variable == var)]
    axes[i].plot(var_data.date, var_data.value)
    axes[i].set_title(var)
    axes[i].set_ylabel("Value")
    axes[i].grid(True, linestyle='--', alpha=0.7)
    axes[i].tick_params(axis='x', rotation=45)
plt.tight_layout()
plt.show()
# %% [markdown]
# Create two surfaces as a list of dicts
# TODO: change to real Paris land parameters
# %%
surface = [
    {
        "type_": "PerviousSurface",
        "area": 2e7,    # unit in m2
        "surface": "rural",
        "field_capacity": 0.3,
        "depth": 0.5,
        "initial_storage": 2e7 * 0.3 * 0.5,
    },
    {
        "type_": "ImperviousSurface",
        "area": 1e8,
        "surface": "urban",
        "initial_storage": 5e7,
    },
]


# %% [markdown]
# Create the land node from these surfaces and the input data
# %%
paris_land = Land(surfaces=surface, name="paris_land", data_input_dict=land_inputs)

# %% [markdown]
# We can see the land node has various tanks that have been initialised empty

# %%

print(paris_land.surface_runoff.storage)
print(paris_land.subsurface_runoff.storage)
print(paris_land.percolation.storage)
# %% [markdown]
# We can see the surfaces have also been initialised, although they are not empty because we provided 'initial_storage' parameters.

# %%
rural_surface = paris_land.get_surface("rural")
urban_surface = paris_land.get_surface("urban")
print("{0}-{1}".format("rural", rural_surface.storage))
print("{0}-{1}".format("urban", urban_surface.storage))



paris = ResidentialDemand(
    name="paris",
    population=2.1e6,
    per_capita=0.15,
    pollutant_load={
        "temperature": 14,
    },
    data_input_dict=land_inputs,
)

# %% [markdown]
# We can run a timestep of the land node with the 'run' command

# %%
paris_land.t = pd.to_datetime("2022-12-22")

paris_land.run()

# %% [markdown]
# We can see that the land and surface tanks have been updated

# %%
print(paris_land.surface_runoff.storage)
print(paris_land.subsurface_runoff.storage)
print(paris_land.percolation.storage)

print("{0}-{1}".format("rural", rural_surface.storage))
print("{0}-{1}".format("urban", urban_surface.storage))

# %% [markdown]
# ### Residential demand
# The [residential demand](./../../../reference-other/#wsimod.nodes.demand.ResidentialDemand)
# node requires population, per capita demand and a pollutant_load dictionary that defines
# how much (weight in kg) pollution is generated per person per day.

# %%
paris = ResidentialDemand(
    name="paris",
    population=2e5,
    per_capita=0.15,
    pollutant_load={
        "temperature": 14,
    },
    data_input_dict=land_inputs,
)
# pollutant_load calculated based on expected effluent at WWTW


# %% [markdown]
# ### Reservoir
# A [reservoir node](./../../../reference-storage/#wsimod.nodes.storage.Reservoir)
# is used to make abstractions from rivers and supply FWTWs

# %%
# TODO: need to change these parameters to match the Paris reservoir
paris_reservoir = Reservoir(
    name="paris_reservoir", capacity=1e7, initial_storage=1e7, area=1.5e6, datum=62
)

# %% [markdown]
# ### Distribution
# We use a generic [Node](./../../../reference-nodes/#wsimod.nodes.nodes.Node) as a junction to represent the distribution network between the FWTW and households

# %%

distribution = Node(name="paris_distribution")

# %% [markdown]
# ### Wastewater treatment works
# [Wastewater treatment works (WWTW)](./../../../reference-wtw/#wsimod.nodes.wtw.WWTW)
# are nodes that can store sewage water temporarily in storm tanks, and reduce the pollution
# amounts in water before releasing them onwards to rivers.

# %%
# TODO: change these parameters to match the Paris WWTW
paris_wwtw = WWTW(
    stormwater_storage_capacity=2e4,
    stormwater_storage_area=2e4,
    treatment_throughput_capacity=5e4,
    name="paris_wwtw",
)

# %% [markdown]
# ### Sewers
# [Sewer nodes](./../../../reference-sewer/#wsimod.nodes.sewer.Sewer) enable water to transition
# between households and WWTWs, and between impervious surfaces and rivers or WWTWs.
# They use a timearea diagram to represent travel time, which assigns a specified percentage
# of water to take a specified duration to pass through the sewer node.
# %%
# TODO: change these parameters to match the Paris sewer system
combined_sewer = Sewer(
    capacity=4e6, pipe_timearea={0: 0.8, 1: 0.15, 2: 0.05}, name="combined_sewer"
)

# %% [markdown]
# ### Groundwater
# [Groundwater nodes](./../../../reference-storage/#wsimod.nodes.storage.Groundwater)
# implement a simple residence time to determine baseflow

# %%
# TODO: change these parameters to match the Paris groundwater situation
gw = Groundwater(capacity=3.2e9, area=3.2e8, name="gw", residence_time=20)


# %% [markdown]
# ### Create a nodelist
# To keep all the nodes in one place, we put them into a list
# %%
nodelist = [
    downstream_outlet,
    seine_upstream,
    paris,
    distribution,
    paris_reservoir,
    paris_fwtw,
    paris_wwtw,
    combined_sewer,
    paris_land,
    gw,
    abstraction,
    water_intake,
    downstream_mixer,
]

print(nodelist)

# %% [markdown]
# ## Arcs
# [Arcs](./../../../reference-arc/#wsimod.arcs.arcs.Arc) link nodes.
# An example arc is the link between a FWTW and the distribution node
# %%

# Standard simple arcs
fwtw_to_distribution = Arc(
    in_port=paris_fwtw, out_port=distribution, name="fwtw_to_distribution"
)
print(fwtw_to_distribution)

# %% [markdown]
# As with nodes, even though we only gave it a few parameters, the arc comes with a lot built in
# %%
print(dir(fwtw_to_distribution))

# %% [markdown]
# We can see that the arc links the two nodes
# %%


print(fwtw_to_distribution.in_port)


# %%


print(fwtw_to_distribution.out_port)

# %% [markdown]
# And that it has updated the nodes that it is connecting.
# %%
print(paris_fwtw.out_arcs)

# %%
print(distribution.in_arcs)

# %% [markdown]
# We use arcs to send checks and requests..
# %%
print(fwtw_to_distribution.send_pull_check({"volume": 20}))


# %%
reply = fwtw_to_distribution.send_pull_request({"volume": 20})
print(reply)

# %% [markdown]
# They convey this information to the nodes that they connect to, which update their state variables
# %%


print(paris_fwtw.service_reservoir_tank.storage)

# %% [markdown]
# In turn, the arcs update their own state variables.
# %%


print(fwtw_to_distribution.flow_in)
print(fwtw_to_distribution.flow_out)

# %% [markdown]
# ## Arc parameters
# Besides the in/out ports and names, arcs can have a parameter for their capacity, to limit the flow that may pass through it each timestep.
# A typical example would be on river abstractions to a reservoir
# %%
abstraction_to_reservoir = Arc(
    in_port=abstraction,
    out_port=paris_reservoir,
    name="abstraction_to_reservoir",
    capacity=5e4, # TODO: change this parameter to match the Paris abstraction capacity, currently =*10 of oxford
)

# %% [markdown]
# A bit more sophisticated is the 'preference' parameter.
# We use preference to express where we would prefer the model to send water.
# In this example, the sewer can send water to both the treatment plant and directly into the river.
# Of course we would always to prefer to send water to the plant, so we give it a very high preference.
# Discharging into the river should only be done if there is no capacity left at the WWTW, so we give the arc a very low preference.
# %%
# TODO: change these parameters to match the Paris sewer system and WWTW capacity
sewer_to_wwtw = Arc(
    in_port=combined_sewer, out_port=paris_wwtw, preference=1e10, name="sewer_to_wwtw"
)
sewer_overflow = Arc(
    in_port=combined_sewer,
    out_port=downstream_mixer,
    preference=1e-10,
    name="sewer_overflow",
)


# %% [markdown]
# ## Create arcs
# Arcs are a bit less interesting than nodes because they generally don't capture complicated physical behaviours.
# So we just create all of them below.
# %%


seine_upstream_to_intake = Arc(
    in_port=seine_upstream, out_port=water_intake, name="seine_upstream_to_intake"
)


intake_to_abstraction = Arc(
    in_port=water_intake, out_port=abstraction, name="intake_to_abstraction"
)


abstraction_to_mixer = Arc(
    in_port=abstraction, out_port=downstream_mixer, name="abstraction_to_mixer"
)

wwtw_to_mixer = Arc(in_port=paris_wwtw, out_port=downstream_mixer, name="wwtw_to_mixer")

mixer_to_waste = Arc(
    in_port=downstream_mixer, out_port=downstream_outlet, name="mixer_to_waste"
)

distribution_to_demand = Arc(
    in_port=distribution, out_port=paris, name="distribution_to_demand"
)

reservoir_to_fwtw = Arc(in_port=paris_reservoir, out_port=paris_fwtw, name="reservoir_to_fwtw")

fwtw_to_sewer = Arc(in_port=paris_fwtw, out_port=combined_sewer, name="fwtw_to_sewer")

demand_to_sewer = Arc(in_port=paris, out_port=combined_sewer, name="demand_to_sewer")

land_to_sewer = Arc(in_port=paris_land, out_port=combined_sewer, name="land_to_sewer")

land_to_gw = Arc(in_port=paris_land, out_port=gw, name="land_to_gw")

garden_to_gw = Arc(in_port=paris, out_port=gw, name="garden_to_gw")

gw_to_mixer = Arc(in_port=gw, out_port=downstream_mixer, name="gw_to_mixer")

# %% [markdown]
# Again, we keep all the arcs in a tidy list together.

# %%
arclist = [
    seine_upstream_to_intake,
    intake_to_abstraction,
    abstraction_to_mixer,
    wwtw_to_mixer,
    sewer_overflow,
    mixer_to_waste,
    abstraction_to_reservoir,
    distribution_to_demand,
    demand_to_sewer,
    land_to_sewer,
    sewer_to_wwtw,
    fwtw_to_sewer,
    fwtw_to_distribution,
    reservoir_to_fwtw,
    land_to_gw,
    garden_to_gw,
    gw_to_mixer,
]


# %% [markdown]
# ## Mapping
# Remember, WSIMOD is an integrated model.
# Because it covers so many different things, it is very easy to make mistakes.
# Thus it is always good practice to plot your data!
#
# Below we load the node location data and create arcs from the information in the arclist.
# %%
# TODO: geojson file for Paris case
# location_fn = os.path.join(data_folder, "raw", "points_locations.geojson")
# nodes_gdf = gpd.read_file(location_fn).set_index("name")
# arcs_gdf = []
#
# for arc in arclist:
#     arcs_gdf.append(
#         {
#             "name": arc.name,
#             "geometry": LineString(
#                 [
#                     nodes_gdf.loc[arc.in_port.name, "geometry"],
#                     nodes_gdf.loc[arc.out_port.name, "geometry"],
#                 ]
#             ),
#         }
#     )
#
# arcs_gdf = gpd.GeoDataFrame(arcs_gdf, crs=nodes_gdf.crs)
# %% [markdown]
# Because we converted the information as GeoDataFrames, we can simply plot them below
# %%

# f, ax = plt.subplots()
# arcs_gdf.plot(ax=ax)
# nodes_gdf.plot(color="r", ax=ax, zorder=10)
# plt.show()

# %% [markdown]
# ## Orchestration
# Orchestration is making the simulation happen by calling functions in the nodes.
# These functions simulate physical behaviour within the node, and cause pulls/pushes to happen which in turn triggers physical behaviour in other nodes.
#
# ### Orchestrating an individual timestep
#
# We will start below by manually orchestrating a single timestep.
#
# We start by setting the date, so that every node knows what forcing data to read for this timestep.

# %%
date = dates[0]

for node in nodelist:
    node.t = date

print(date)
print(paris_fwtw.t)

# %% [markdown]
# We can see the service reservoirs are empty but the supply reservoir is not!
# %%

print(paris_fwtw.service_reservoir_tank.storage)
print(paris_reservoir.tank.storage)
# %% [markdown]
# If we call the FWTW's treat_water function it will pull water from the supply reservoir and update its service reservoirs
# %%

paris_fwtw.treat_water()

print(paris_fwtw.service_reservoir_tank.storage)
print(paris_reservoir.tank.storage)

# %% [markdown]
# This information is tracked in the arcs that enter the FWTW
# %%


print(paris_fwtw.in_arcs)


# %%


print(reservoir_to_fwtw.flow_in)
print(reservoir_to_fwtw.flow_out)

# %% [markdown]
# Although none of that water has yet entered the distribution network (only some small flow from the earlier demonstration)
# %%


print(fwtw_to_distribution.flow_in)

# %% [markdown]
# That is because no water consumption demand had yet been generated.
#
# If we call the demand node's create_demand function we see that the distribution arc becomes utilised.
# %%

paris.create_demand()
print(fwtw_to_distribution.flow_in)

# %% [markdown]
# We also see that this gets pushed onwards into the sewer system

# %%
print(demand_to_sewer.flow_in)


# %% [markdown]
# Many nodes have functions intended to be called during orchestration.
# These functions are described in the documentation.
# For example, we see in the [Land node](./../../../reference-land/#wsimod.nodes.land.Land) API reference that the 'run' function is intended to be called from orchestration.
# %%
paris_land.run()

# %% [markdown]
# Below we call the functions for other nodes
# %%

# Discharge GW
gw.distribute()

# Discharge sewers (pushed to other sewers or WWTW)
combined_sewer.make_discharge()

# Run WWTW model
paris_wwtw.calculate_discharge()

# Make abstractions
paris_reservoir.make_abstractions()

# Discharge WW
paris_wwtw.make_discharge()

# Route catchments
seine_upstream.route()

# %% [markdown]
# ## Ending a timestep
# Because mistakes happen, it is essential to carry out mass balance testing.
# Each node has a mass balance function that can be called.
# We see a mass balance violation resulting from the demonstration with the FWTW earlier.
# %%

for node in nodelist:
    in_, ds_, out_ = node.node_mass_balance()


# %% [markdown]
# We should also call the end_timestep function in nodes and arcs.
# This is important for mass balance testing and capturing the behaviour of some dynamic processes in nodes.

# %%

for node in nodelist:
    node.end_timestep()

for arc in arclist:
    arc.end_timestep()

# %% [markdown]
# ## Model object
# Of course it would be a massive pain to manually orchestrate every timestep.
# So instead we store node and arc information in a [model object](./../../../reference-model/#wsimod.orchestration.model.Model)
# that will do the orchestration for us.
#
# Because we have already created the nodes/arcs above, we simply need to add the instantiated lists above.

# %%

my_model = Model()
my_model.add_instantiated_nodes(nodelist)
my_model.add_instantiated_arcs(arclist)
my_model.dates = dates

# %% [markdown]
# The model object lets us reinitialise the nodes/arcs, and run all of the orchestration with a 'run' function.
# %%

my_model.reinit()

flows, _, _, _ = my_model.run()

# %% [markdown]
# The model outputs flows as a dictionary which can be converted to a dataframe
# %%

flows = pd.DataFrame(flows)

print(flows.sample(10))

# %% [markdown]
# ## Validation plots
# Validation removed as pollutant data is not being simulated.
# We will plot all the flow at the model outlet instead.
# %%
unique_arcs = flows['arc'].unique()
num_arcs = len(unique_arcs)
cols = 3
rows = (num_arcs + cols - 1) // cols

fig, axes = plt.subplots(rows, cols, figsize=(15, 4 * rows), constrained_layout=True)
axes = axes.flatten()

for i, arc_name in enumerate(unique_arcs):
    ax = axes[i]
    # filter data for this arc and set time as index for plotting
    arc_data = flows.loc[flows['arc'] == arc_name, ["flow", "time"]].set_index("time")
    ax.plot(arc_data.index, arc_data['flow'])
    ax.set_title(arc_name)
    ax.set_ylabel("Flow (m3/d)")
    ax.grid(True, linestyle='--', alpha=0.7)
    # Rotate date labels for better readability
    ax.tick_params(axis='x', rotation=45)

# Turn off unused subplots
for i in range(num_arcs, len(axes)):
    axes[i].axis('off')

plt.show()
# %% [markdown]
# ## Plotting all arcs and nodes 
# the following code allows you to plot all the arcs and nodes in the model, 
# when you add new nodes, it helps to understand if the flow paths are correct.

# %%
import networkx as nx

G = nx.DiGraph()

# Define color palette based on node types from schematic.svg
type_colors = {
    'Catchment': '#ff99ff',
    'Waste': '#e3e300',
    'Node': '#33ff33',
    'FWTW': '#33ffff',
    'Land': '#009900',
    'Demand': '#ffb570',
    'ResidentialDemand': '#ffb570',
    'Reservoir': '#7f00ff',
    'WWTW': '#ff0080',
    'Sewer': '#7ea6e0',
    'Groundwater': '#ff0000'
}

# Define layers for left-to-right multipartite layout
def get_layer(node):
    node_type = type(node).__name__
    name = node.name.lower()
    if node_type == 'Catchment':
        return 0
    elif 'intake' in name or (node_type == 'Node' and 'distribution' not in name and 'mixer' not in name and 'abstraction' not in name):
        return 1
    elif 'abstraction' in name:
        return 2
    elif node_type == 'Reservoir' or 'distribution' in name:
        return 3
    elif node_type in ['FWTW', 'Demand', 'ResidentialDemand']:
        return 4
    elif node_type in ['Groundwater', 'Land']:
        return 5
    elif node_type in ['Sewer', 'WWTW']:
        return 6
    elif node_type == 'Waste' or 'mixer' in name:
        return 7
    return 1

for node in nodelist:
    node_type = type(node).__name__
    color = type_colors.get(node_type, 'lightblue')
    # Special case for abstraction nodes which are colored differently in the schematic
    if 'abstraction' in node.name:
        color = '#0000cc'
    G.add_node(node.name, color=color, layer=get_layer(node))

for arc in arclist:
    G.add_edge(arc.in_port.name, arc.out_port.name, label=arc.name)

node_colors = [nx.get_node_attributes(G, 'color')[node] for node in G.nodes()]

plt.figure(figsize=(16, 10))
# Use multipartite layout specifying the layer attribute
pos = nx.multipartite_layout(G, subset_key="layer", align='vertical') 

# Stagger the y-coordinates to prevent horizontal edges from crossing nodes
layers = {}
for node, data in G.nodes(data=True):
    layer = data.get('layer', 0)
    if layer not in layers:
        layers[layer] = []
    layers[layer].append(node)

for layer, nodes in layers.items():
    nodes.sort(key=lambda n: pos[n][1])  # Sort by existing vertical order
    n = len(nodes)
    for i, node in enumerate(nodes):
        y_val = (i - (n - 1) / 2.0) * 2.0  # Spread out nodes vertically
        
        # Stagger based on odd/even layers, shifting by 0.5
        if layer % 2 == 1:
            y_val += 0.5
            
        pos[node] = (pos[node][0], y_val)

nx.draw(G, pos, with_labels=True, node_color=node_colors, 
        node_size=2500, font_size=10, font_weight='bold', 
        arrows=True, edge_color='gray', arrowsize=20)

edge_labels = nx.get_edge_attributes(G, 'label')
nx.draw_networkx_edge_labels(G, pos, edge_labels=edge_labels, font_size=8)
plt.title("Model Node Linkages (Arcs)")
plt.show()

# %%

