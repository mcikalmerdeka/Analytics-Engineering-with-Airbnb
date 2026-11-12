SELECT *
FROM {{ ref('fct_reviews') }}
WHERE review_date > DATE '2021-11-19'
