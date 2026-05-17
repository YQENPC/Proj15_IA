import pandas as pd
from tqdm import tqdm

def process_water_data():
    flows_filepath = "./data_v2/raw/flows_F700000103_2021-2025.csv"
    pollutants_filepath = "./data_v2/raw/pollutants_03081000_2021-2025.csv"
    weather_filepath = "./data_v2/raw/weather_Paris_2021-2025.csv"

    timeseries_data = []

    # Flows
    df_flows = pd.read_csv(flows_filepath, sep=",")
    for _, row in tqdm(df_flows.iterrows()):
        date = row["Date (TU)"].split("T")[0]
        timeseries_data.append({
            "site": "seine",
            "date": date,
            "variable": "flow",
            "value": row["Valeur (en m³/s)"]
        })

    # Weather
    df_weather = pd.read_csv(weather_filepath, sep=",", skiprows=3)
    for _, row in tqdm(df_weather.iterrows()):
        date = row["time"].split("T")[0]
        timeseries_data.append({
            "site": "paris_land",
            "date": date,
            "variable": "temperature",
            "value": row["temperature_2m_mean (°C)"]
        })
        timeseries_data.append({
            "site": "paris_land",
            "date": date,
            "variable": "precipitation",
            "value": row["precipitation_sum (mm)"]
        })
        timeseries_data.append({
            "site": "paris_land",
            "date": date,
            "variable": "et0",
            "value": row["et0_fao_evapotranspiration (mm)"]
        })

    # Pollutants
    df_pollutants = pd.read_csv(pollutants_filepath, sep=";")
    for _, row in tqdm(df_pollutants.iterrows()):
        date = row["date_prelevement"]
        match row["libelle_parametre"]:
            case "Température de l'Eau":
                timeseries_data.append({
                    "site": "seine",
                    "date": date,
                    "variable": "temperature",
                    "value": row["resultat"]
                })
            case "Phosphore total":
                timeseries_data.append({
                    "site": "seine",
                    "date": date,
                    "variable": "phosphorus",
                    "value": row["resultat"]
                })
            case "Nitrates":
                timeseries_data.append({
                    "site": "seine",
                    "date": date,
                    "variable": "nitrate",
                    "value": row["resultat"]
                })
            case _:
                print("Unknown parameter:", row["libelle_parametre"])
    

    timeseries_df = pd.DataFrame(timeseries_data)
    timeseries_df.to_csv("./data_v2/processed/processed_data.csv", index=False)

# Execute the function
if __name__ == "__main__":
    process_water_data()
