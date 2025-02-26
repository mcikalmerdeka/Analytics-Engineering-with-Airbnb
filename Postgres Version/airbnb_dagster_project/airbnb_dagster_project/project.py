# from pathlib import Path

# from dagster_dbt import DbtProject

# airbnb_dbt_project = DbtProject(
#     project_dir=Path(__file__).joinpath("..", "..", "..", "airbnb_dbt").resolve(),
#     packaged_project_dir=Path(__file__).joinpath("..", "..", "dbt-project").resolve(),
# )
# airbnb_dbt_project.prepare_if_dev()


from pathlib import Path
from dagster_dbt import DbtProject

# Define paths explicitly for Windows
airbnb_dbt_dir = Path(__file__).resolve().parent.parent.parent / "airbnb_dbt"
profiles_dir = Path(r"E:\Personal Projects\Analytics Engineering with Airbnb\Analytics-Engineering-with-Airbnb\Postgres Version")

airbnb_dbt_project = DbtProject(
    project_dir=airbnb_dbt_dir,
    profiles_dir=profiles_dir,  # Explicitly set the profiles_dir
    packaged_project_dir=Path(__file__).resolve().parent.parent / "dbt-project",
)

airbnb_dbt_project.prepare_if_dev()