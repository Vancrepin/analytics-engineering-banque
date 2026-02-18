{{
    config(
        materialized='table',
        tags=['marts', 'portefeuille']
    )
}}

WITH contrats AS (
    SELECT * FROM {{ ref('stg_contrats') }}
),

clients AS (
    SELECT * FROM {{ ref('stg_clients') }}
),

-- Agrégation sinistres au niveau contrat
sinistres_by_contrat AS (
    SELECT
        contrat_key,
        COUNT(DISTINCT sinistre_id) AS nb_sinistres,
        SUM(montant_declare) AS total_sinistres_declares,
        SUM(montant_indemnise) AS total_sinistres_indemnises,
        AVG(montant_indemnise) AS cout_moyen_sinistre
    FROM {{ ref('stg_sinistres') }}
    GROUP BY contrat_key
),

-- Agrégation primes au niveau contrat
primes_by_contrat AS (
    SELECT
        contrat_key,
        SUM(CASE WHEN is_paye THEN montant_prime ELSE 0 END) AS total_primes_collectees
    FROM {{ ref('stg_primes') }}
    GROUP BY contrat_key
),

base_contrat AS (
    SELECT
        DATE_TRUNC('month', CURRENT_DATE) AS periode_mois,
        c.contrat_key,
        c.contrat_id,
        c.is_actif,
        c.type_produit_std AS type_produit,
        COALESCE(cl.segment_client, 'Unknown') AS segment_client
    FROM contrats c
    LEFT JOIN clients cl ON c.client_key = cl.client_key
),

aggregated AS (
    SELECT
        periode_mois,
        type_produit,
        segment_client,

        -- Volumes
        COUNT(DISTINCT CASE WHEN is_actif THEN contrat_id END) AS nb_contrats_actifs,
        SUM(COALESCE(s.nb_sinistres, 0)) AS nb_sinistres,

        -- Fréquence = nb sinistres / nb contrats actifs
        SUM(COALESCE(s.nb_sinistres, 0))::FLOAT /
        NULLIF(COUNT(DISTINCT CASE WHEN is_actif THEN contrat_id END), 0) AS frequence_sinistres,

        -- Montants
        SUM(COALESCE(p.total_primes_collectees, 0)) AS total_primes_collectees,
        SUM(COALESCE(s.total_sinistres_declares, 0)) AS total_sinistres_declares,
        SUM(COALESCE(s.total_sinistres_indemnises, 0)) AS total_sinistres_indemnises,

        -- Coût moyen sinistre (pondéré)
        CASE
            WHEN SUM(COALESCE(s.nb_sinistres, 0)) > 0
            THEN SUM(COALESCE(s.total_sinistres_indemnises, 0)) / SUM(COALESCE(s.nb_sinistres, 0))
            ELSE NULL
        END AS cout_moyen_sinistre,

        -- Ratios S/P
        (SUM(COALESCE(s.total_sinistres_indemnises, 0)) /
         NULLIF(SUM(COALESCE(p.total_primes_collectees, 0)), 0) * 100) AS ratio_sp_periode,

        (SUM(COALESCE(s.total_sinistres_indemnises, 0)) /
         NULLIF(SUM(COALESCE(p.total_primes_collectees, 0)), 0) * 100) AS ratio_sp_ytd,

        (SUM(COALESCE(s.total_sinistres_indemnises, 0)) /
         NULLIF(SUM(COALESCE(p.total_primes_collectees, 0)), 0) * 100) AS ratio_sp_12m_glissant

    FROM base_contrat bc
    LEFT JOIN sinistres_by_contrat s ON bc.contrat_key = s.contrat_key
    LEFT JOIN primes_by_contrat p ON bc.contrat_key = p.contrat_key
    GROUP BY periode_mois, type_produit, segment_client
)

SELECT
    {{ dbt_utils.generate_surrogate_key(["CAST(periode_mois AS TEXT)", "type_produit", "segment_client"]) }} AS sinistralite_key,

    periode_mois,
    type_produit,
    segment_client,

    nb_contrats_actifs,
    nb_sinistres,
    frequence_sinistres,

    total_primes_collectees,
    total_sinistres_declares,
    total_sinistres_indemnises,
    cout_moyen_sinistre,

    ratio_sp_periode,
    ratio_sp_ytd,
    ratio_sp_12m_glissant,

    NULL::NUMERIC AS evolution_vs_mois_precedent,
    NULL::NUMERIC AS evolution_vs_annee_precedente,

    CURRENT_TIMESTAMP AS calculated_at
FROM aggregated
