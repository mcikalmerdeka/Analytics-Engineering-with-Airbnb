# Script to test if the paths are correct
from pathlib import Path

airbnb_dbt_dir = Path(__file__).resolve().parent.parent.parent / "airbnb_dbt"
profiles_dir = Path(r"E:\Personal Projects\Analytics Engineering with Airbnb\Analytics-Engineering-with-Airbnb\Postgres Version")

print("Airbnb dbt project exists:", airbnb_dbt_dir.exists())  # Should be True
print("profiles.yml exists:", (profiles_dir / "profiles.yml").exists())  # Should be True