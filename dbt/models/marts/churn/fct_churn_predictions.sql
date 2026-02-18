{{
    config(
        materialized='table',
        tags=['marts', 'churn']
    )
}}

WITH client_activity AS (
    SELECT * FROM {{ ref('int_client_activity') }}
),

-- 1) Calcul des facteurs (alias OK ici)
churn_factors AS (
    SELECT
        client_key,
        client_id,
        segment_client,
        age,
        anciennete_client_mois,

        -- Activité transactionnelle
        nb_transactions_total,
        nb_transactions_30j,
        nb_transactions_90j,
        montant_transactions_30j,
        days_since_last_transaction,

        -- Portefeuille contrats
        nb_contrats_total,
        nb_contrats_actifs,
        nb_contrats_resilies,
        prime_mensuelle_totale,

        -- Sinistralité
        nb_sinistres_total,
        nb_sinistres_12m,
        nb_sinistres_rejetes,

        -- Engagement
        statut_engagement,
        ltv_estimee_3ans,

        -- 1. Baisse d'activité transactionnelle (30 points max)
        CASE
            WHEN nb_transactions_90j = 0 THEN 30
            WHEN nb_transactions_30j = 0 AND nb_transactions_90j > 0 THEN 20
            WHEN nb_transactions_30j < (nb_transactions_90j * 0.5) THEN 15
            ELSE 0
        END AS score_baisse_activite,

        -- 2. Inactivité (20 points max)
        CASE
            WHEN days_since_last_transaction > 180 THEN 20
            WHEN days_since_last_transaction > 90 THEN 15
            WHEN days_since_last_transaction > 60 THEN 10
            WHEN days_since_last_transaction > 30 THEN 5
            ELSE 0
        END AS score_inactivite,

        -- 3. Résiliation de contrats (20 points max)
        CASE
            WHEN nb_contrats_actifs = 0 AND nb_contrats_resilies > 0 THEN 20
            WHEN nb_contrats_resilies >= 2 THEN 15
            WHEN nb_contrats_resilies = 1 THEN 10
            ELSE 0
        END AS score_resiliation,

        -- 4. Insatisfaction sinistres (15 points max)
        CASE
            WHEN nb_sinistres_rejetes >= 2 THEN 15
            WHEN nb_sinistres_rejetes = 1 THEN 10
            WHEN nb_sinistres_12m > 3 THEN 5
            ELSE 0
        END AS score_insatisfaction_sinistres,

        -- 5. Faible valeur client (15 points max)
        CASE
            WHEN prime_mensuelle_totale = 0 THEN 15
            WHEN prime_mensuelle_totale < 50 THEN 10
            WHEN prime_mensuelle_totale < 100 THEN 5
            ELSE 0
        END AS score_faible_valeur

    FROM client_activity
),

-- 2) Calcul du score global (maintenant les alias existent)
churn_scoring AS (
    SELECT
        *,
        LEAST(
            100,
            score_baisse_activite
            + score_inactivite
            + score_resiliation
            + score_insatisfaction_sinistres
            + score_faible_valeur
        ) AS score_churn
    FROM churn_factors
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['client_key']) }} AS prediction_key,

        client_key,
        client_id,
        segment_client,
        age,
        anciennete_client_mois,

        -- Métriques d'activité
        nb_transactions_30j,
        nb_transactions_90j,
        days_since_last_transaction,
        nb_contrats_actifs,
        nb_contrats_resilies,
        prime_mensuelle_totale,
        nb_sinistres_rejetes,
        statut_engagement,
        ltv_estimee_3ans,

        -- Scores détaillés
        score_baisse_activite,
        score_inactivite,
        score_resiliation,
        score_insatisfaction_sinistres,
        score_faible_valeur,
        score_churn,

        -- Probabilités de churn
        CASE
            WHEN score_churn >= 80 THEN 0.90
            WHEN score_churn >= 60 THEN 0.70
            WHEN score_churn >= 40 THEN 0.50
            WHEN score_churn >= 20 THEN 0.30
            ELSE 0.10
        END AS probabilite_churn_30j,

        CASE
            WHEN score_churn >= 70 THEN 0.95
            WHEN score_churn >= 50 THEN 0.75
            WHEN score_churn >= 30 THEN 0.55
            WHEN score_churn >= 15 THEN 0.35
            ELSE 0.15
        END AS probabilite_churn_90j,

        -- Segment de risque
        CASE
            WHEN score_churn >= 70 THEN 'Critique'
            WHEN score_churn >= 50 THEN 'Eleve'
            WHEN score_churn >= 30 THEN 'Moyen'
            ELSE 'Faible'
        END AS segment_risque,

        -- Facteur principal
        CASE
            WHEN score_inactivite >= GREATEST(score_baisse_activite, score_resiliation, score_insatisfaction_sinistres, score_faible_valeur)
                THEN 'Inactivite'
            WHEN score_baisse_activite >= GREATEST(score_inactivite, score_resiliation, score_insatisfaction_sinistres, score_faible_valeur)
                THEN 'Baisse_Activite'
            WHEN score_resiliation >= GREATEST(score_inactivite, score_baisse_activite, score_insatisfaction_sinistres, score_faible_valeur)
                THEN 'Resiliation'
            WHEN score_insatisfaction_sinistres >= GREATEST(score_inactivite, score_baisse_activite, score_resiliation, score_faible_valeur)
                THEN 'Insatisfaction'
            ELSE 'Faible_Valeur'
        END AS facteur_principal,

        -- Action recommandée
        CASE
            WHEN score_churn >= 70 AND nb_contrats_actifs > 0 THEN 'Contact_Urgent_Retention'
            WHEN score_churn >= 70 AND nb_contrats_actifs = 0 THEN 'Tentative_Reactivation'
            WHEN score_churn >= 50 THEN 'Offre_Personnalisee'
            WHEN score_churn >= 30 THEN 'Campagne_Engagement'
            ELSE 'Suivi_Normal'
        END AS action_recommandee,

        CASE
            WHEN score_churn >= 80 AND prime_mensuelle_totale > 200 THEN 1
            WHEN score_churn >= 70 THEN 2
            WHEN score_churn >= 50 THEN 3
            WHEN score_churn >= 30 THEN 4
            ELSE 5
        END AS priorite_contact,

        CURRENT_DATE AS date_prediction,
        CURRENT_TIMESTAMP AS predicted_at

    FROM churn_scoring
)

SELECT * FROM final
