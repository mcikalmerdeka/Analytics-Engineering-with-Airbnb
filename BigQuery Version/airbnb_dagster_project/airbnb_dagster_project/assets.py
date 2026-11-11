from dagster import AssetExecutionContext
from dagster_dbt import DbtCliResource, dbt_assets

from .project import airbnb_dbt_project


@dbt_assets(manifest=airbnb_dbt_project.manifest_path)
def airbnb_dbt_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()
    