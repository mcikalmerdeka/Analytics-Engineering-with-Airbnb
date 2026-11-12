{% macro learn_variables() %}

-- jinja variables
    {% set your_name_jinja = "Cikal" %}
    {{ log("Hello " ~ your_name_jinja, info=True) }}

-- dbt variables
    {{ log("Hello dbt user " ~ var("user_name", "NO USERNAME IS SET!") ~ "!", info=True) }}

{% endmacro %}