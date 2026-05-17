#%%
import pandas as pd
import numpy as np
from scipy.optimize import curve_fit
import matplotlib.pyplot as plt
from wsimod.core import constants
from wsimod.arcs.arcs import Arc
from wsimod.nodes.catchment import Catchment
from wsimod.nodes.demand import ResidentialDemand
from wsimod.nodes.land import Land
from wsimod.nodes.nodes import Node
from wsimod.nodes.sewer import Sewer
from wsimod.nodes.storage import Groundwater, Reservoir
from wsimod.nodes.waste import Waste
from wsimod.nodes.wtw import FWTW, WWTW
from wsimod.orchestration.model import Model

constants.POLLUTANTS = ["temperature", "nitrate"]
constants.NON_ADDITIVE_POLLUTANTS = ["temperature"]
constants.ADDITIVE_POLLUTANTS = ["nitrate"]
constants.FLOAT_ACCURACY = 1e-9
constants.POLLUTANTS

#%%
# Data source (dates range: 2021-2025)
# - Seine's flow: Hydroportail, station F700000103 (Paris, Austerlitz), daily mean flow
#   (https://hydro.eaufrance.fr/stationhydro/F700000103/series)
# - Seine's temperature and nitrate concentration: Hub'eau, river water quality API, station 03081000 (Paris, 12th arrondissement)
#   (https://hubeau.eaufrance.fr/api/v2/qualite_rivieres/analyse_pc.csv?code_departement=75&code_parametre=1301%2C1340%2C1350%2C1337&code_station=03081000&date_debut_prelevement=2021-01-01&date_fin_maj=2025-12-31&size=20000&sort=desc)
# - Land's temperature: Open-Meteo.org, coordinates 48.822495,2.2881355 (Paris), timezone GMT+2
#   (https://open-meteo.com/en/docs/historical-weather-api?start_date=2021-01-01&end_date=2025-12-31&timezone=Europe%2FBerlin&latitude=48.8534&longitude=2.3488&hourly=&daily=temperature_2m_mean,et0_fao_evapotranspiration,precipitation_sum)
input_data = pd.read_csv("./data_v2/processed/processed_data.csv")

input_data = input_data.loc[input_data.variable.isin(["flow", "precipitation", "et0", "temperature", "nitrate"])]
input_data.loc[input_data.variable == "flow", "value"] *= constants.M3_S_TO_M3_DT
input_data.loc[input_data.variable == "precipitation", "value"] *= constants.MM_TO_M
input_data.loc[input_data.variable == "et0", "value"] *= constants.MM_TO_M
input_data.loc[input_data.variable == "nitrate", "value"] *= constants.MG_L_TO_KG_M3

# Une des valeurs est un peu aberrante par rapport aux autres, on la retire
input_data = input_data[(input_data.variable != "nitrate") | (input_data.value < 0.040)] 

input_data.date = pd.to_datetime(input_data.date)
data_input_dict = input_data.set_index(["variable", "date"]).value.to_dict()
data_input_dict = (
    input_data.groupby("site")
    .apply(lambda x: x.set_index(["variable", "date"]).value.to_dict())
    .to_dict()
)
print(pd.concat([input_data.head(5), input_data.sample(10), input_data.tail(5)]))

# Only keep the dates for which we have a value for each variable
dates = input_data.loc[input_data.variable == "precipitation", "date"]
for variable in ["flow", "et0", "nitrate", "temperature"]:# get common measure times across all stations
    dates = pd.merge(dates, input_data.loc[input_data.variable == variable, "date"], how='inner', on=['date']).date
dates = dates.unique()
dates = dates[dates.argsort()]
dates = [pd.Timestamp(t) for t in dates]
print(dates[1:5])

# def fill_missing_dates(dates_list, input_dict, parameter="temperature", n_harmonics=3, noise_std=1):
#     """Fill missing dates using Fourier series fit."""
    
#     # Extract existing data points
#     existing_dates = []
#     existing_values = []

#     for date in dates_list:
#         key = (parameter, date)
#         if key in input_dict:
#             existing_dates.append(date)
#             existing_values.append(input_dict[key])
    
#     # Convert to numeric (days since start)
#     existing_numeric = np.array([(d - existing_dates[0]).days for d in existing_dates])
#     existing_values = np.array(existing_values)
#     time_span = existing_numeric[-1] - existing_numeric[0]
    
#     # Define Fourier series function
#     def fourier_series(t, *coeffs):
#         # coeffs = [mean, amp1, phase1, amp2, phase2, ...]
#         result = coeffs[0]  # mean value
#         for i in range(n_harmonics):
#             amp = coeffs[1 + 2*i]
#             phase = coeffs[1 + 2*i + 1]
#             # Use harmonics at 1x, 2x, 3x... the fundamental frequency
#             result += amp * np.sin(2 * np.pi * (i+1) * t / time_span + phase)
#         return result
    
#     # Initial guess for parameters
#     p0 = [np.mean(existing_values)] + [1, 0] * n_harmonics
    
#     # Fit the Fourier series
#     try:
#         popt, _ = curve_fit(fourier_series, existing_numeric, existing_values, p0=p0, maxfev=10000)
#     except RuntimeError as e:
#         print(f"Fitting failed: {e}. Try reducing n_harmonics.")
#         return input_dict
    
#     # Fill missing dates
#     for date in dates_list:
#         key = (parameter, date)
#         if key not in input_dict:
#             date_numeric = (date - existing_dates[0]).days
#             interpolated_value = fourier_series(date_numeric, *popt)
#             noise = np.random.normal(loc=0, scale=noise_std)
#             input_dict[key] = float(interpolated_value + noise)

# fill_missing_dates(dates, data_input_dict["seine"], parameter="temperature", n_harmonics=8, noise_std=0.2)
# fill_missing_dates(dates, data_input_dict["seine"], parameter="nitrate", n_harmonics=8, noise_std=5e-4)

#%%
# Plot precipitations, nitrate and temperatures

fig, ax = plt.subplots(3, sharex=True, figsize=(10,5))

precipitations = []
for date in dates:
    precipitations.append(data_input_dict["paris_land"][("precipitation", date)])
ax[0].bar(dates, precipitations, 5,color="blue", label="Précipitations (mm)")
ax[0].set_title("Daily precipitation")
ax[0].legend()
ax[0].xaxis_date()

seine_nitrates = []
for date in dates:
    seine_nitrates.append(data_input_dict["seine"][("nitrate", date)])
ax[1].plot(dates, seine_nitrates, marker = ".", linewidth=1, color="green", label="Nitrate (mg(NO3)/L)")
ax[1].set_title("Nitrate concentration")
ax[1].legend()

seine_temperatures = []
paris_land_temperatures = []
for date in dates:
    seine_temperatures.append(data_input_dict["seine"][("temperature", date)])
    paris_land_temperatures.append(data_input_dict["paris_land"][("temperature", date)])

ax[2].plot(dates, paris_land_temperatures, marker = ".", linewidth=1, color="orange", label="Land's temperature")
ax[2].plot(dates, seine_temperatures, marker=".", linewidth=1, color="red", label="Seine's temperature", zorder=2)
ax[2].set_title("Temperature")

fig.suptitle("Input variables on model's dates")
plt.legend()
plt.show()

#%%
abstraction = Node(name="abstraction")
downstream_mixer = Node(name="downstream_mixer")
seine_upstream = Catchment(name="river", data_input_dict=data_input_dict["seine"])

# FWTW parameters estimated by computing the sum of the capacities of Paris's main reservoirs and FWTW stations
# FWTW Stations:
# - Joinville: 300 000 m³/d
# - Orly: 300 000 m³/d
# - L'Häy-les-Roses: 145 000 m³/d
# - Saint-Cloud: 100 000 m³/d
# - Arcueil: 150 000 m³/d
# (NB. There are two other stations further upstream, in Longueville and in Sorques, with each a treatment throughput capacity of 50 000 m³/d. 
# Their production is then sent to the Arcueil station through two aqueducts: aqueduct of the Voulzie for the Longueville station, aqueduct of 
# the Loing for the Sorques station. We thus don't take them into account.)
# (Sources: https://https://www.eaudeparis.fr/distribuer-leau, https://www.youtube.com/watch?v=Rel9EGOmqNI)
# Freswhater reservoirs:
# - Lilas and Ménilmontant (receive the water from the Joinville station): respectively 208 000 m³ and 95 000 m³
# - L'Häy-les-Roses (receives the water from the Orly and L'Häy-les-Roses stations): 203 000 m³
# - Saint-Cloud (receives the water from the Saint-Cloud station): 426 000 m³
# - Montsouris (receives the water from the Arcueil station): 200 000 m³
# (Sources: https://www.eaudeparis.fr/des-reservoirs-pour-stocker-leau, http://keblo1515.free.fr/souterrinterdit/reservoirs.htm)
# Storage area estimated by assuming the reservoirs are around 25m heigh.

paris_fwtw = FWTW(
    service_reservoir_storage_capacity=1.1e6,
    service_reservoir_storage_area=6e4,
    service_reservoir_initial_storage=1e6,
    treatment_throughput_capacity=1e6,
    name="paris_fwtw",
)

land_inputs = data_input_dict["paris_land"]


# Nitrate deposition: order of magnitude of around 2e3 mg/m² of wet deposition (measured in the Netherlands)
# (Source: https://www-sciencedirect-com.extranet.enpc.fr/science/article/pii/S1352231011003864)
# However, using this value leads to aberrant results (more than 1 kgNO₃/m³ in the WWTW outlet).
# so using the value of the WSIMOD demo instead

pollutant_deposition = {
    "nitrate": 2e-9
}

# Areas estimated using https://atlas.co/tools/area-calculator/
# - Pervious surface: Bois de Vincennes & Bois de Boulogne (area of gardens is negligible: ~10⁶ m²), around 1.8 x 10⁸ m²
# - Impervious surface: rest of Paris, around 8 x 10⁸ m²
paris_land = Land(
    surfaces=[
        {
            "type_": "PerviousSurface",
            "area": 1.8e8, # 1.8m²
            "pollutant_load": pollutant_deposition,
            "surface": "rural",
            "initial_storage": 1.8e8 * 0.1 * 0.5, # default field capacity: 0.1 / default depth: 0.5m
        },
        {
            "type_": "ImperviousSurface",
            "area": 8e8,
            "pollutant_load": pollutant_deposition,
            "surface": "urban",
            "initial_storage": 8e8 * 0.05, # height of the ponding area * area
        },
    ], 
    data_input_dict=land_inputs,
    name="paris_land"
)

# Demand
# Population and per capita consumption found in "Ville de Paris, Rapport annuel 2024 sur le prix et la qualité du service public d'eau potable et d'assainissement"
# (https://cdn.paris.fr/paris/2025/11/28/rpqs-eau-2024-v4-GLFg.pdf)
# Nitrate load per capita: using the value of the WSIMOD Oxford demo since we couldn't find any other value elsewhere,
# except that the concentration of nitrates in the inlet of wastewater treatment stations is around 1 mg/L, vs. ~20-40 mg/L in 
# the outlet, after the nitrification process (ammonia -> nitrate)
# (Source: https://www.deswater.com/DWT_articles/vol_65_papers/65_2017_192.pdf)

paris = ResidentialDemand(
    name="paris",
    population=2.1e6,
    per_capita=0.12,
    pollutant_load={
        "temperature": 14,
        "nitrate": 150 * constants.MG_L_TO_KG_M3 * 0.12 # 150 mg/L
    },
    data_input_dict=land_inputs,
)

distribution = Node(name="paris_distribution")

# SIAAP network: 480 km of emissaries with a diameter of 2.5-6m.
# (Source: https://www.siaap.fr/metiers/transporter-stocker-et-gerer/)
# Estimating the capacity: 480 000 * (3m/2) * π = 2.2e6 m³ (using half this value since the SIAAP covers a far greater area than Paris itself.)

combined_sewer = Sewer(capacity=1e6, name="combined_sewer")

# SIAAP network: stormwater storage capacity of 990 000 m³ (using half this value since the SIAAP covers a far greater area than Paris itself.)
# (Source: https://www.siaap.fr/metier# s/transporter-stocker-et-gerer/)
# Storage area estimated by assuming the reservoirs are around 25m heigh.
# The throughput capacity was configured after running the model once to make it match the sum of residential wastewater and precipitation.
paris_wwtw = WWTW(
    stormwater_storage_capacity=5e5,
    stormwater_storage_area=2e4,
    treatment_throughput_capacity=9e5,
    name="paris_wwtw",
)

# Capacity set by multiplying the area by a height of 10m (as in the WSIMOD Oxford demo)
gw = Groundwater(capacity=9.8e9, area=9.8e8, name="gw", residence_time=20)

downstream_outlet = Waste(name="downstream_outlet")

nodelist = [
    seine_upstream,
    abstraction,
    paris,
    paris_fwtw,
    paris_wwtw,
    combined_sewer,
    paris_land,
    gw,
    downstream_mixer,
    downstream_outlet,
]

arclist = [
    Arc(in_port=seine_upstream, out_port=abstraction, name="seine_upstream_to_intake"),
    Arc(in_port=abstraction, out_port=downstream_mixer, name="abstraction_to_mixer"),
    Arc(
        in_port=abstraction,
        out_port=paris_fwtw,
        name="abstraction_to_reservoir",
        capacity=5e5,
    ),
    Arc(in_port=paris_fwtw, out_port=paris, name="fwtw_to_demand"),
    Arc(in_port=paris_fwtw, out_port=combined_sewer, name="fwtw_to_sewer"),
    Arc(in_port=paris, out_port=combined_sewer, name="demand_to_sewer"),
    Arc(in_port=paris_land, out_port=combined_sewer, name="land_to_sewer"),
    Arc(in_port=paris_land, out_port=gw, name="land_to_gw"),
    Arc(in_port=paris, out_port=gw, name="garden_to_gw"),
    Arc(in_port=gw, out_port=downstream_mixer, name="gw_to_mixer"),
    Arc(in_port=combined_sewer, out_port=paris_wwtw, preference=1e10, name="sewer_to_wwtw"),
    Arc(
        in_port=combined_sewer,
        out_port=downstream_mixer,
        preference=1e-10,
        name="sewer_overflow",
    ),
    Arc(in_port=paris_wwtw, out_port=downstream_mixer, name="wwtw_to_mixer"),
    Arc(in_port=downstream_mixer, out_port=downstream_outlet, name="mixer_to_waste")
]

my_model = Model()
my_model.add_instantiated_nodes(nodelist)
my_model.add_instantiated_arcs(arclist)
my_model.dates = dates

flows, tanks, _, surfaces = my_model.run()

#%%
# Plots arc flows
flows = pd.DataFrame(flows)
flows_plot = flows.copy()
flows_plot["nitrate"] /= flows_plot.flow

unique_arcs = flows['arc'].unique()
num_arcs = len(unique_arcs)
cols = 3
rows = (num_arcs + cols - 1) // cols

fig, axes = plt.subplots(rows, cols, figsize=(15, 4 * rows), constrained_layout=True)
axes = axes.flatten()

for i, arc_name in enumerate(unique_arcs):
    ax = axes[i]
    # filter data for this arc and set time as index for plotting
    arc_data = flows[flows['time'] > pd.to_datetime('2022-07-01')].loc[flows['arc'] == arc_name, ["flow", "time"]].set_index("time")
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

fig, axes = plt.subplots(rows, cols, figsize=(15, 4 * rows), constrained_layout=True)
axes = axes.flatten()

for i, arc_name in enumerate(unique_arcs):
    ax = axes[i]
    # filter data for this arc and set time as index for plotting
    arc_data = flows_plot[flows_plot['time'] > pd.to_datetime('2022-07-01')].loc[flows['arc'] == arc_name, ["nitrate", "time"]].set_index("time")
    ax.plot(arc_data.index, arc_data['nitrate'])
    ax.set_title(arc_name)
    ax.set_ylabel("Nitrate (kg/m³)")
    ax.grid(True, linestyle='--', alpha=0.7)
    # Rotate date labels for better readability
    ax.tick_params(axis='x', rotation=45)

# Turn off unused subplots
for i in range(num_arcs, len(axes)):
    axes[i].axis('off')

plt.show()

#%%
# Plot reservoirs' storage
tanks = pd.DataFrame(tanks)

unique_tanks = set(zip(tanks["node"], tanks["prop"]))

num_tanks = len(unique_tanks)
cols = 3
rows = (num_tanks + cols - 1) // cols

fig, axes = plt.subplots(rows, cols, figsize=(15, 4 * rows), constrained_layout=True)
axes = axes.flatten()

for i, (node_name, prop) in enumerate(unique_tanks):
    ax = axes[i]
    # filter data for this arc and set time as index for plotting
    tank_data = tanks[tanks['time'] > pd.to_datetime('2022-07-01')].loc[(tanks['node'] == node_name) & (tanks['prop'] == prop), ["storage", "time"]].set_index("time")
    ax.plot(tank_data.index, tank_data['storage'])
    ax.set_title(f"{node_name} / {prop}")
    ax.set_ylabel("Storage (m³)")
    ax.grid(True, linestyle='--', alpha=0.7)
    # Rotate date labels for better readability
    ax.tick_params(axis='x', rotation=45)

# Turn off unused subplots
for i in range(num_tanks, len(axes)):
    axes[i].axis('off')

plt.show()

#%%
df_pollutants_validation = pd.read_csv("./data_v2/raw/pollutants_03082000_2021-2025.csv", sep=";")
temperatures_validation = []
nitrate_validation = []
for _, row in df_pollutants_validation.iterrows():
    date = row["date_prelevement"]
    match row["libelle_parametre"]:
        case "Température de l'Eau":
            temperatures_validation.append((pd.to_datetime(date), row["resultat"]))
        case "Nitrates":
            nitrate_validation.append((pd.to_datetime(date), row["resultat"] * constants.MG_L_TO_KG_M3))
        case _:
            continue

plt.title("Temperature (°C) (mixer_to_waste)")
plt.plot(flows_plot.loc[flows_plot.arc == "mixer_to_waste", ["temperature", "time"]].set_index("time"), color="b", label="model")
plt.scatter(*zip(*temperatures_validation), color="r", zorder=2, label="validation")
plt.tick_params(axis='x', rotation=45)
plt.legend()
plt.show()

plt.title("Nitrate (kg/m³) (mixer_to_waste)")
plt.plot(flows_plot.loc[flows_plot.arc == "mixer_to_waste", ["nitrate", "time"]].set_index("time"), color="b", label="model")
plt.scatter(*zip(*nitrate_validation), color="r", zorder=2, label="validation")
plt.tick_params(axis='x', rotation=45)
plt.legend()
plt.show()

#%%
abstraction = Node(name="abstraction")
downstream_mixer = Node(name="downstream_mixer")

# Input data collected from hydro.eaufrance.fr (Austerlitz station - code F700000103) for the flows
# and hubeau.eaufrance.fr (12th arrondissement station - code 03081000) for the water temperature and nitrate concentration
seine_upstream = Catchment(name="river", data_input_dict=data_input_dict["seine"])

# FWTW parameters estimated by computing the sum of the capacities of Paris's main reservoirs and FWTW stations
# FWTW Stations:
# - Joinville: 300 000 m³/d
# - Orly: 300 000 m³/d
# - L'Häy-les-Roses: 145 000 m³/d
# - Saint-Cloud: 100 000 m³/d
# - Arcueil: 150 000 m³/d
# (NB. There are two other stations further upstream, in Longueville and in Sorques, with each a treatment throughput capacity of 50 000 m³/d. 
# Their production is then sent to the Arcueil station through two aqueducts: aqueduct of the Voulzie for the Longueville station, aqueduct of 
# the Loing for the Sorques station. We thus don't take them into account.)
# (Sources: https://https://www.eaudeparis.fr/distribuer-leau, https://www.youtube.com/watch?v=Rel9EGOmqNI)
# Freswhater reservoirs:
# - Lilas and Ménilmontant (receive the water from the Joinville station): respectively 208 000 m³ and 95 000 m³
# - L'Häy-les-Roses (receives the water from the Orly and L'Häy-les-Roses stations): 203 000 m³
# - Saint-Cloud (receives the water from the Saint-Cloud station): 426 000 m³
# - Montsouris (receives the water from the Arcueil station): 200 000 m³
# (Sources: https://www.eaudeparis.fr/des-reservoirs-pour-stocker-leau, http://keblo1515.free.fr/souterrinterdit/reservoirs.htm)
# Storage area estimated by assuming the reservoirs are around 25m heigh.

paris_fwtw = FWTW(
    service_reservoir_storage_capacity=1.1e6,
    service_reservoir_storage_area=6e4,
    service_reservoir_initial_storage=1e6,
    treatment_throughput_capacity=1e6,
    name="paris_fwtw",
)

land_inputs = data_input_dict["paris_land"]


# Nitrate deposition: order of magnitude of around 2e3 mg/m² of wet deposition (measured in the Netherlands)
# (Source: https://www-sciencedirect-com.extranet.enpc.fr/science/article/pii/S1352231011003864)
# However, using this value leads to aberrant results (more than 1 kgNO₃/m³ in the WWTW outlet).
# so using the value of the WSIMOD demo instead

pollutant_deposition = {
    "nitrate": 2e-9
}

# Areas estimated using https://atlas.co/tools/area-calculator/
# - Pervious surface: Bois de Vincennes & Bois de Boulogne (area of gardens is negligible: ~10⁶ m²), around 1.8 x 10⁸ m²
# - Impervious surface: rest of Paris, around 8 x 10⁸ m²
paris_land = Land(
    surfaces=[
        {
            "type_": "PerviousSurface",
            "area": 1.8e8, # 1.8m²
            "pollutant_load": pollutant_deposition,
            "surface": "rural",
            "initial_storage": 1.8e8 * 0.1 * 0.5, # default field capacity: 0.1 / default depth: 0.5m
        },
        {
            "type_": "ImperviousSurface",
            "area": 8e8,
            "pollutant_load": pollutant_deposition,
            "surface": "urban",
            "initial_storage": 8e8 * 0.05, # height of the ponding area * area
        },
    ], 
    data_input_dict=land_inputs,
    name="paris_land"
)

# Demand
# Population and per capita consumption found in "Ville de Paris, Rapport annuel 2024 sur le prix et la qualité du service public d'eau potable et d'assainissement"
# (https://cdn.paris.fr/paris/2025/11/28/rpqs-eau-2024-v4-GLFg.pdf)
# Nitrate load per capita: using the value of the WSIMOD Oxford demo since we couldn't find any other value elsewhere,
# except that the concentration of nitrates in the inlet of wastewater treatment stations is around 1 mg/L, vs. ~20-40 mg/L in 
# the outlet, after the nitrification process (ammonia -> nitrate)
# (Source: https://www.deswater.com/DWT_articles/vol_65_papers/65_2017_192.pdf)

paris = ResidentialDemand(
    name="paris",
    population=2.1e6,
    per_capita=0.12,
    pollutant_load={
        "temperature": 14,
        "nitrate": 150 * constants.MG_L_TO_KG_M3 * 0.12 # 150 mg/L
    },
    data_input_dict=land_inputs,
)

distribution = Node(name="paris_distribution")

# SIAAP network: 480 km of emissaries with a diameter of 2.5-6m.
# (Source: https://www.siaap.fr/metiers/transporter-stocker-et-gerer/)
# Estimating the capacity: 480 000 * (3m/2) * π = 2.2e6 m³ (using half this value since the SIAAP covers a far greater area than Paris itself.)

combined_sewer = Sewer(capacity=1e6, name="combined_sewer")

# SIAAP network: stormwater storage capacity of 990 000 m³ (using half this value since the SIAAP covers a far greater area than Paris itself.)
# (Source: https://www.siaap.fr/metier# s/transporter-stocker-et-gerer/)
# Storage area estimated by assuming the reservoirs are around 25m heigh.
# The throughput capacity was configured after running the model once to make it match the sum of residential wastewater and precipitation.
paris_wwtw = WWTW(
    stormwater_storage_capacity=1,
    stormwater_storage_area=1,
    treatment_throughput_capacity=1,
    name="paris_wwtw",
)

# Capacity set by multiplying the area by a height of 10m (as in the WSIMOD Oxford demo)
gw = Groundwater(capacity=9.8e9, area=9.8e8, name="gw", residence_time=20)

downstream_outlet = Waste(name="downstream_outlet")

nodelist = [
    seine_upstream,
    abstraction,
    paris,
    paris_fwtw,
    paris_wwtw,
    combined_sewer,
    paris_land,
    gw,
    downstream_mixer,
    downstream_outlet,
]

arclist = [
    Arc(in_port=seine_upstream, out_port=abstraction, name="seine_upstream_to_intake"),
    Arc(in_port=abstraction, out_port=downstream_mixer, name="abstraction_to_mixer"),
    Arc(
        in_port=abstraction,
        out_port=paris_fwtw,
        name="abstraction_to_reservoir",
        capacity=5e5,
    ),
    Arc(in_port=paris_fwtw, out_port=paris, name="fwtw_to_demand"),
    Arc(in_port=paris_fwtw, out_port=combined_sewer, name="fwtw_to_sewer"),
    Arc(in_port=paris, out_port=combined_sewer, name="demand_to_sewer"),
    Arc(in_port=paris_land, out_port=combined_sewer, name="land_to_sewer"),
    Arc(in_port=paris_land, out_port=gw, name="land_to_gw"),
    Arc(in_port=paris, out_port=gw, name="garden_to_gw"),
    Arc(in_port=gw, out_port=downstream_mixer, name="gw_to_mixer"),
    Arc(in_port=combined_sewer, out_port=paris_wwtw, preference=1e10, name="sewer_to_wwtw"),
    Arc(
        in_port=combined_sewer,
        out_port=downstream_mixer,
        preference=1e-10,
        name="sewer_overflow",
    ),
    Arc(in_port=paris_wwtw, out_port=downstream_mixer, name="wwtw_to_mixer"),
    Arc(in_port=downstream_mixer, out_port=downstream_outlet, name="mixer_to_waste")
]

my_model = Model()
my_model.add_instantiated_nodes(nodelist)
my_model.add_instantiated_arcs(arclist)
my_model.dates = dates

flows_without_wwtw, _, _, _ = my_model.run()

#%%
flows_with_wwtw = flows
flows_with_wwtw_plot = flows_with_wwtw.copy()
flows_with_wwtw_plot["nitrate"] /= flows_with_wwtw_plot.flow

flows_without_wwtw = pd.DataFrame(flows_without_wwtw)
flows_without_wwtw_plot = flows_without_wwtw.copy()
flows_without_wwtw_plot["nitrate"] /= flows_without_wwtw_plot.flow

df_pollutants_validation = pd.read_csv("./data_v2/raw/pollutants_03082000_2021-2025.csv", sep=";")
nitrate_validation = []
for _, row in df_pollutants_validation.iterrows():
    date = row["date_prelevement"]
    match row["libelle_parametre"]:
        case "Nitrates":
            nitrate_validation.append((pd.to_datetime(date), row["resultat"] * constants.MG_L_TO_KG_M3))
        case _:
            continue

df_pollutants_input = pd.read_csv("./data_v2/raw/pollutants_03081000_2021-2025.csv", sep=";")
nitrate_input = []
for _, row in df_pollutants_input.iterrows():
    date = row["date_prelevement"]
    match row["libelle_parametre"]:
        case "Nitrates":
            nitrate_input.append((pd.to_datetime(date), row["resultat"] * constants.MG_L_TO_KG_M3))
        case _:
            continue

plt.title("Nitrate (kg/m³)")
plt.plot(flows_without_wwtw_plot.loc[flows_plot.arc == "mixer_to_waste", ["nitrate", "time"]].set_index("time"), label="downtream (model without wwtw)", linewidth=0.5, zorder=1)
plt.plot(flows_with_wwtw_plot.loc[flows_plot.arc == "mixer_to_waste", ["nitrate", "time"]].set_index("time"), label="downtream (model with wwtw)", linewidth=0.5, zorder=2)
plt.plot(flows_with_wwtw_plot.loc[flows_plot.arc == "seine_upstream_to_intake", ["nitrate", "time"]].set_index("time"), label="upstream (Austerlitz station)", linewidth=0.5, zorder=1, marker="x", color="black")
plt.scatter(*zip(*nitrate_validation), zorder=3, label="downstream (Suresne station)", s=50, marker=".")

plt.tick_params(axis='x', rotation=45)
plt.ylim([0.010, 0.045])
plt.legend()
plt.show()
