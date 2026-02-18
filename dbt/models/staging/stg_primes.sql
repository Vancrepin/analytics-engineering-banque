{{
    config(
        materialized='view',
        tags=['staging', 'primes']
    )
}}

WITH source AS (
    SELECT * FROM {{ source('raw', 'primes') }}
),

base AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['prime_id']) }} AS prime_key,
        prime_id,
        {{ dbt_utils.generate_surrogate_key(['contrat_id']) }} AS contrat_key,
        contrat_id,

        date_echeance,
        date_paiement,

        CASE
            WHEN date_paiement IS NOT NULL
            THEN (date_paiement::date - date_echeance::date)
            ELSE (CURRENT_DATE - date_echeance::date)
        END AS retard_jours,

        montant_prime,

        UPPER(TRIM(statut_paiement)) AS statut_paiement_std,

        CASE
            WHEN UPPER(TRIM(statut_paiement)) IN ('PAYÉ','PAYE') THEN TRUE
            ELSE FALSE
        END AS is_paye,

        CASE
            WHEN UPPER(TRIM(statut_paiement)) IN ('IMPAYÉ','IMPAYE') THEN TRUE
            ELSE FALSE
        END AS is_impaye,

        CASE
            WHEN UPPER(TRIM(statut_paiement)) = 'RETARD' THEN TRUE
            ELSE FALSE
        END AS is_retard,

        CASE
            WHEN date_paiement IS NOT NULL
                 AND (date_paiement::date - date_echeance::date) <= 5
            THEN TRUE
            ELSE FALSE
        END AS is_paiement_a_temps,

        DATE_TRUNC('month', date_echeance::date) AS periode_mois,
        EXTRACT(YEAR FROM date_echeance::date) AS annee,
        EXTRACT(MONTH FROM date_echeance::date) AS mois,

        loaded_at,
        CURRENT_TIMESTAMP AS updated_at
    FROM source
    WHERE prime_id IS NOT NULL
      AND contrat_id IS NOT NULL
      AND date_echeance IS NOT NULL
),

cleaned AS (
    SELECT
        *,
        CASE
            WHEN retard_jours IS NULL OR retard_jours <= 0 THEN 'A_temps'
            WHEN retard_jours <= 15 THEN 'Retard_Court'
            WHEN retard_jours <= 30 THEN 'Retard_Moyen'
            ELSE 'Retard_Long'
        END AS categorie_retard
    FROM base
)

SELECT * FROM cleaned
