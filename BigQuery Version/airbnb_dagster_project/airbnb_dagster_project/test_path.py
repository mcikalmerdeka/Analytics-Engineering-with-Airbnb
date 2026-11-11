# Script to test if the paths are correct
from pathlib import Path

project_root = Path(__file__).resolve().parents[2]
airbnb_dbt_dir = project_root / "airbnb_dbt"

print("Airbnb dbt project exists:", airbnb_dbt_dir.exists())
print("profiles.yml exists:", (project_root / "profiles.yml").exists())
