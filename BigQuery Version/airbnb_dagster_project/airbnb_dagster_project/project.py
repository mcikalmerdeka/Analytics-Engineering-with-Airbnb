from pathlib import Path

from dagster_dbt import DbtProject

# Postgres Version/ is three levels up from this file:
# Postgres Version/airbnb_dagster_project/airbnb_dagster_project/project.py
project_root = Path(__file__).resolve().parents[2]

airbnb_dbt_project = DbtProject(
    project_dir=project_root / "airbnb_dbt",
    profiles_dir=project_root,
)

airbnb_dbt_project.prepare_if_dev()
