{{
    config(
        materialized='table',
        tags=['marts', 'portefeuille']
    )
}}

/*
    Modèle MART : Performance détaillée des contrats
    
    Source : int_contrat_performance
*/

WITH contrat_perf AS (
    SELECT * FROM {{ ref('int_contrat_performance') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['contrat_key', 'CURRENT_DATE']) }} AS performance_key,
    
    contrat_key,
    contrat_id,
    client_key,
    client_id,
    type_produit_std,
    categorie_produit,
    anciennete_mois,
    
    -- Données financières
    prime_mensuelle,
    primes_collectees AS prime_totale_periode,
    primes_collectees AS prime_cumulee_ytd,  -- Simplifié
    taux_paiement AS taux_paiement_a_temps,
    nb_impayes,
    
    -- Sinistres
    nb_sinistres,
    montant_total_indemnise AS montant_sinistres_indemnises,
    
    -- Ratios clés
    ratio_sp_pct AS ratio_sinistres_primes,
    ratio_sp_pct AS ratio_combined,  -- Simplifié (normalement + frais)
    marge_technique,
    
    -- Performance
    statut_rentabilite,
    is_actif,
    anciennete_mois AS anciennete_contrat_mois,
    ltv_restante AS ltv_a_date,
    ltv_restante AS ltv_projetee,  -- Simplifié
    
    -- Période
    DATE_TRUNC('month', CURRENT_DATE) AS periode_mois,
    
    -- Métadonnées
    CURRENT_TIMESTAMP AS calculated_at
    
FROM contrat_perf