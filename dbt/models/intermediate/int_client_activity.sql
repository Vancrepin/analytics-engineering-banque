{{
    config(
        materialized='view',
        tags=['intermediate', 'client']
    )
}}

/*
    Modèle INTERMEDIATE : Activité Client
    
    Objectif :
    - Agréger l'activité transactionnelle par client et par mois
    - Calculer les indicateurs d'engagement
    - Préparer pour l'analyse de churn
    
    Sources : stg_clients, stg_transactions, stg_contrats, stg_sinistres
*/

WITH clients AS (
    SELECT * FROM {{ ref('stg_clients') }}
),

transactions AS (
    SELECT * FROM {{ ref('stg_transactions') }}
),

contrats AS (
    SELECT * FROM {{ ref('stg_contrats') }}
),

sinistres AS (
    SELECT * FROM {{ ref('stg_sinistres') }}
),

-- Activité transactionnelle par client
trans_activity AS (
    SELECT
        client_key,
        COUNT(DISTINCT transaction_id) AS nb_transactions_total,
        SUM(montant_eur) AS montant_total_transactions,
        AVG(montant_eur) AS montant_moyen_transaction,
        MAX(date_transaction) AS date_derniere_transaction,
        MIN(date_transaction) AS date_premiere_transaction,
        
        -- Activité récente (30 derniers jours)
        COUNT(DISTINCT CASE 
            WHEN date_transaction >= CURRENT_DATE - INTERVAL '30 days' 
            THEN transaction_id 
        END) AS nb_transactions_30j,
        
        SUM(CASE 
            WHEN date_transaction >= CURRENT_DATE - INTERVAL '30 days' 
            THEN montant_eur 
            ELSE 0 
        END) AS montant_transactions_30j,
        
        -- Activité 90 derniers jours
        COUNT(DISTINCT CASE 
            WHEN date_transaction >= CURRENT_DATE - INTERVAL '90 days' 
            THEN transaction_id 
        END) AS nb_transactions_90j,
        
        SUM(CASE 
            WHEN date_transaction >= CURRENT_DATE - INTERVAL '90 days' 
            THEN montant_eur 
            ELSE 0 
        END) AS montant_transactions_90j,
        
        -- Répartition par canal
        COUNT(DISTINCT CASE WHEN canal_std = 'Web' THEN transaction_id END) AS nb_trans_web,
        COUNT(DISTINCT CASE WHEN canal_std = 'Mobile' THEN transaction_id END) AS nb_trans_mobile,
        COUNT(DISTINCT CASE WHEN canal_std = 'Agence' THEN transaction_id END) AS nb_trans_agence,
        
        -- Transactions suspectes
        COUNT(DISTINCT CASE WHEN is_nocturne THEN transaction_id END) AS nb_trans_nocturnes,
        COUNT(DISTINCT CASE WHEN is_international THEN transaction_id END) AS nb_trans_internationales
        
    FROM transactions
    GROUP BY client_key
),

-- Portefeuille de contrats par client
contrats_portfolio AS (
    SELECT
        client_key,
        COUNT(DISTINCT contrat_id) AS nb_contrats_total,
        COUNT(DISTINCT CASE WHEN is_actif THEN contrat_id END) AS nb_contrats_actifs,
        COUNT(DISTINCT CASE WHEN is_resilie THEN contrat_id END) AS nb_contrats_resilies,
        
        SUM(CASE WHEN is_actif THEN prime_mensuelle ELSE 0 END) AS prime_mensuelle_totale,
        SUM(CASE WHEN is_actif THEN capital_assure ELSE 0 END) AS capital_total_assure,
        
        -- Répartition par type de produit
        COUNT(DISTINCT CASE WHEN type_produit_std = 'Auto' AND is_actif THEN contrat_id END) AS nb_contrats_auto,
        COUNT(DISTINCT CASE WHEN type_produit_std = 'Habitation' AND is_actif THEN contrat_id END) AS nb_contrats_habitation,
        COUNT(DISTINCT CASE WHEN type_produit_std = 'Santé' AND is_actif THEN contrat_id END) AS nb_contrats_sante,
        COUNT(DISTINCT CASE WHEN type_produit_std = 'Vie' AND is_actif THEN contrat_id END) AS nb_contrats_vie,
        
        -- Ancienneté moyenne des contrats actifs
        AVG(CASE WHEN is_actif THEN anciennete_mois END) AS anciennete_moyenne_contrats_mois,
        
        -- Date de souscription du dernier contrat
        MAX(date_souscription) AS date_dernier_contrat
        
    FROM contrats
    GROUP BY client_key
),

-- Sinistralité par client
sinistres_history AS (
    SELECT
        client_key,
        COUNT(DISTINCT sinistre_id) AS nb_sinistres_total,
        SUM(montant_declare) AS montant_total_sinistres_declares,
        SUM(montant_indemnise) AS montant_total_indemnise,
        
        -- Sinistres récents (12 derniers mois)
        COUNT(DISTINCT CASE 
            WHEN date_declaration >= CURRENT_DATE - INTERVAL '12 months' 
            THEN sinistre_id 
        END) AS nb_sinistres_12m,
        
        COUNT(DISTINCT CASE WHEN is_rejete THEN sinistre_id END) AS nb_sinistres_rejetes,
        
        AVG(delai_traitement_jours) AS delai_moyen_traitement,
        MAX(date_declaration) AS date_dernier_sinistre
        
    FROM sinistres
    GROUP BY client_key
),

-- Assemblage final
final AS (
    SELECT
        c.client_key,
        c.client_id,
        c.segment_client,
        c.age,
        c.anciennete_mois AS anciennete_client_mois,
        
        -- Activité transactionnelle
        COALESCE(t.nb_transactions_total, 0) AS nb_transactions_total,
        COALESCE(t.montant_total_transactions, 0) AS montant_total_transactions,
        COALESCE(t.montant_moyen_transaction, 0) AS montant_moyen_transaction,
        COALESCE(t.nb_transactions_30j, 0) AS nb_transactions_30j,
        COALESCE(t.montant_transactions_30j, 0) AS montant_transactions_30j,
        COALESCE(t.nb_transactions_90j, 0) AS nb_transactions_90j,
        COALESCE(t.montant_transactions_90j, 0) AS montant_transactions_90j,
        
        -- Jours depuis dernière interaction
        CASE 
            WHEN t.date_derniere_transaction IS NOT NULL 
            THEN CURRENT_DATE - t.date_derniere_transaction 
            ELSE NULL 
        END AS days_since_last_transaction,
        
        -- Portefeuille contrats
        COALESCE(cp.nb_contrats_total, 0) AS nb_contrats_total,
        COALESCE(cp.nb_contrats_actifs, 0) AS nb_contrats_actifs,
        COALESCE(cp.nb_contrats_resilies, 0) AS nb_contrats_resilies,
        COALESCE(cp.prime_mensuelle_totale, 0) AS prime_mensuelle_totale,
        COALESCE(cp.capital_total_assure, 0) AS capital_total_assure,
        
        -- Diversification produits
        COALESCE(cp.nb_contrats_auto, 0) AS nb_contrats_auto,
        COALESCE(cp.nb_contrats_habitation, 0) AS nb_contrats_habitation,
        COALESCE(cp.nb_contrats_sante, 0) AS nb_contrats_sante,
        COALESCE(cp.nb_contrats_vie, 0) AS nb_contrats_vie,
        
        -- Sinistralité
        COALESCE(s.nb_sinistres_total, 0) AS nb_sinistres_total,
        COALESCE(s.nb_sinistres_12m, 0) AS nb_sinistres_12m,
        COALESCE(s.montant_total_indemnise, 0) AS montant_total_indemnise,
        COALESCE(s.nb_sinistres_rejetes, 0) AS nb_sinistres_rejetes,
        
        -- Ratio sinistres/primes (indicateur de rentabilité client)
        CASE 
            WHEN COALESCE(cp.prime_mensuelle_totale, 0) > 0 
            THEN COALESCE(s.montant_total_indemnise, 0) / (cp.prime_mensuelle_totale * 12)
            ELSE 0 
        END AS ratio_sinistres_primes_client,
        
        -- Indicateurs d'engagement
        CASE 
            WHEN COALESCE(t.nb_transactions_30j, 0) > 0 
                 AND COALESCE(cp.nb_contrats_actifs, 0) > 0 
            THEN 'Actif'
            WHEN COALESCE(t.nb_transactions_90j, 0) > 0 
                 OR COALESCE(cp.nb_contrats_actifs, 0) > 0 
            THEN 'Modere'
            ELSE 'Dormant'
        END AS statut_engagement,
        
        -- Valeur client (LTV simplifiée)
        (COALESCE(cp.prime_mensuelle_totale, 0) * 12 * 3) - 
        COALESCE(s.montant_total_indemnise, 0) AS ltv_estimee_3ans,
        
        -- Canal préféré
        CASE 
            WHEN t.nb_trans_mobile >= t.nb_trans_web AND t.nb_trans_mobile >= t.nb_trans_agence THEN 'Mobile'
            WHEN t.nb_trans_web >= t.nb_trans_mobile AND t.nb_trans_web >= t.nb_trans_agence THEN 'Web'
            WHEN t.nb_trans_agence >= t.nb_trans_mobile AND t.nb_trans_agence >= t.nb_trans_web THEN 'Agence'
            ELSE 'Mixte'
        END AS canal_prefere,
        
        -- Métadonnées
        CURRENT_TIMESTAMP AS calculated_at
        
    FROM clients c
    LEFT JOIN trans_activity t ON c.client_key = t.client_key
    LEFT JOIN contrats_portfolio cp ON c.client_key = cp.client_key
    LEFT JOIN sinistres_history s ON c.client_key = s.client_key
)

SELECT * FROM final