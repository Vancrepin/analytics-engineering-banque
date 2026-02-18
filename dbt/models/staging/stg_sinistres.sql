{{
    config(
        materialized='view',
        tags=['staging', 'sinistres']
    )
}}

WITH source AS (
    SELECT * FROM {{ source('raw', 'sinistres') }}
),

base AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['sinistre_id']) }} AS sinistre_key,
        sinistre_id,
        {{ dbt_utils.generate_surrogate_key(['contrat_id']) }} AS contrat_key,
        contrat_id,
        {{ dbt_utils.generate_surrogate_key(['client_id']) }} AS client_key,
        client_id,

        date_declaration,
        date_survenance,

        (date_declaration::date - date_survenance::date) AS delai_declaration_jours,

        TRIM(type_sinistre) AS type_sinistre_std,

        montant_declare,
        montant_indemnise,
        montant_declare - montant_indemnise AS montant_non_indemnise,

        CASE
            WHEN montant_declare > 0 THEN (montant_indemnise / montant_declare) * 100
            ELSE 0
        END AS taux_indemnisation_pct,

        CASE
            WHEN montant_declare < 500 THEN 'Petit'
            WHEN montant_declare < 2000 THEN 'Moyen'
            WHEN montant_declare < 10000 THEN 'Important'
            ELSE 'Majeur'
        END AS categorie_montant,

        UPPER(TRIM(statut)) AS statut_std,

        CASE WHEN UPPER(TRIM(statut)) = 'CLOS' THEN TRUE ELSE FALSE END AS is_clos,
        CASE WHEN UPPER(TRIM(statut)) IN ('REJETÉ','REJETE') THEN TRUE ELSE FALSE END AS is_rejete,
        CASE WHEN montant_indemnise > 0 THEN TRUE ELSE FALSE END AS is_indemnise,

        delai_traitement_jours,

        CASE
            WHEN delai_traitement_jours <= 7 THEN 'Rapide'
            WHEN delai_traitement_jours <= 30 THEN 'Normal'
            WHEN delai_traitement_jours <= 60 THEN 'Long'
            ELSE 'Tres_Long'
        END AS categorie_delai,

        loaded_at,
        CURRENT_TIMESTAMP AS updated_at
    FROM source
    WHERE sinistre_id IS NOT NULL
      AND contrat_id IS NOT NULL
      AND client_id IS NOT NULL
),

cleaned AS (
    SELECT
        *,
        CASE
            WHEN is_clos AND delai_traitement_jours <= 30 AND taux_indemnisation_pct >= 80
            THEN TRUE
            ELSE FALSE
        END AS is_traitement_satisfaisant
    FROM base
)

SELECT * FROM cleaned
