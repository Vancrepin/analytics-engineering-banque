{{
    config(
        materialized='table',
        tags=['marts', 'churn', 'dimensions']
    )
}}

/*
    Dimension : Segmentation des clients
*/

WITH churn_data AS (
    SELECT * FROM {{ ref('fct_churn_predictions') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['client_key']) }} AS segment_key,
    client_key,
    client_id,
    
    -- Segmentation par valeur
    CASE 
        WHEN prime_mensuelle_totale >= 300 THEN 'Platinum'
        WHEN prime_mensuelle_totale >= 150 THEN 'Gold'
        WHEN prime_mensuelle_totale >= 75 THEN 'Silver'
        ELSE 'Bronze'
    END AS segment_valeur,
    
    -- Segmentation par comportement
    statut_engagement AS segment_comportement,
    
    -- Segmentation par risque de churn
    segment_risque AS segment_risque_churn,
    
    -- LTV
    ltv_estimee_3ans AS ltv_estimee,
    
    -- Date de segmentation
    CURRENT_DATE AS date_segmentation,
    CURRENT_TIMESTAMP AS updated_at
    
FROM churn_data