{{
    config(
        materialized='view',
        tags=['intermediate', 'contrats', 'portefeuille']
    )
}}

WITH contrats AS (
    SELECT * FROM {{ ref('stg_contrats') }}
),

sinistres AS (
    SELECT * FROM {{ ref('stg_sinistres') }}
),

primes AS (
    SELECT * FROM {{ ref('stg_primes') }}
),

-- 1) Agrégation "brute" des sinistres (sans calculs dépendant d'autres agrégats)
sinistres_agg_base AS (
    SELECT
        contrat_key,
        COUNT(DISTINCT sinistre_id) AS nb_sinistres,
        SUM(montant_declare) AS montant_total_sinistres_declares,
        SUM(montant_indemnise) AS montant_total_indemnise,
        AVG(montant_indemnise) AS montant_moyen_indemnise,
        MAX(date_declaration) AS date_dernier_sinistre,
        AVG(delai_traitement_jours) AS delai_moyen_traitement,

        -- pour calculer une "fréquence annuelle" proprement
        MIN(date_survenance) AS date_premier_sinistre,

        -- Taux d'acceptation
        COUNT(CASE WHEN is_clos AND NOT is_rejete THEN 1 END)::FLOAT /
        NULLIF(COUNT(*), 0) AS taux_acceptation
    FROM sinistres
    GROUP BY contrat_key
),

-- 2) Calculs dérivés (pas d'agrégats imbriqués)
sinistres_agg AS (
    SELECT
        *,
        CASE
            WHEN date_premier_sinistre IS NULL THEN 0
            ELSE
                nb_sinistres::FLOAT
                / NULLIF(
                    (EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_premier_sinistre::date))::FLOAT
                     + EXTRACT(MONTH FROM AGE(CURRENT_DATE, date_premier_sinistre::date))::FLOAT / 12.0),
                    0
                )
        END AS frequence_sinistres_annuelle
    FROM sinistres_agg_base
),

-- Agrégation des primes par contrat
primes_agg AS (
    SELECT
        contrat_key,
        COUNT(DISTINCT prime_id) AS nb_echeances,
        SUM(montant_prime) AS montant_total_primes,
        SUM(CASE WHEN is_paye THEN montant_prime ELSE 0 END) AS montant_primes_payees,
        COUNT(CASE WHEN is_impaye THEN 1 END) AS nb_impayes,
        COUNT(CASE WHEN is_retard THEN 1 END) AS nb_retards,

        COUNT(CASE WHEN is_paye THEN 1 END)::FLOAT /
        NULLIF(COUNT(*), 0) AS taux_paiement,

        COUNT(CASE WHEN is_paiement_a_temps THEN 1 END)::FLOAT /
        NULLIF(COUNT(*), 0) AS taux_paiement_a_temps
    FROM primes
    GROUP BY contrat_key
),

final AS (
    SELECT
        c.contrat_key,
        c.contrat_id,
        c.client_key,
        c.client_id,
        c.type_produit_std,
        c.categorie_produit,
        c.date_souscription,
        c.date_effet,
        c.date_echeance,
        c.anciennete_mois,
        c.prime_mensuelle,
        c.capital_assure,
        c.is_actif,

        -- Primes collectées
        COALESCE(p.montant_total_primes, 0) AS primes_collectees,
        COALESCE(p.montant_primes_payees, 0) AS primes_payees,
        COALESCE(p.nb_impayes, 0) AS nb_impayes,
        COALESCE(p.taux_paiement, 1) AS taux_paiement,

        -- Sinistres
        COALESCE(s.nb_sinistres, 0) AS nb_sinistres,
        COALESCE(s.montant_total_indemnise, 0) AS montant_total_indemnise,
        COALESCE(s.frequence_sinistres_annuelle, 0) AS frequence_sinistres,
        COALESCE(s.delai_moyen_traitement, 0) AS delai_moyen_traitement,

        -- Ratio S/P
        CASE
            WHEN COALESCE(p.montant_primes_payees, 0) > 0
            THEN (COALESCE(s.montant_total_indemnise, 0) / p.montant_primes_payees) * 100
            ELSE 0
        END AS ratio_sp_pct,

        -- Fréquence par année basée sur ancienneté contrat
        COALESCE(s.nb_sinistres, 0)::FLOAT /
        NULLIF(c.anciennete_mois / 12.0, 0) AS frequence_par_annee,

        -- Coût moyen par sinistre
        CASE
            WHEN COALESCE(s.nb_sinistres, 0) > 0
            THEN COALESCE(s.montant_total_indemnise, 0) / s.nb_sinistres
            ELSE 0
        END AS cout_moyen_sinistre,

        -- Marge technique
        COALESCE(p.montant_primes_payees, 0) -
        COALESCE(s.montant_total_indemnise, 0) AS marge_technique,

        -- LTV restante
        (c.prime_mensuelle *
         GREATEST(0, EXTRACT(MONTH FROM AGE(c.date_echeance, CURRENT_DATE)))) -
        (COALESCE(s.montant_moyen_indemnise, 0) *
         COALESCE(s.frequence_sinistres_annuelle, 0)) AS ltv_restante,

        -- Rentabilité
        CASE
            WHEN COALESCE(p.montant_primes_payees, 0) -
                 COALESCE(s.montant_total_indemnise, 0) > c.prime_mensuelle * 12
            THEN 'Tres_Profitable'
            WHEN COALESCE(p.montant_primes_payees, 0) >
                 COALESCE(s.montant_total_indemnise, 0)
            THEN 'Profitable'
            WHEN COALESCE(p.montant_primes_payees, 0) =
                 COALESCE(s.montant_total_indemnise, 0)
            THEN 'Equilibre'
            ELSE 'Deficitaire'
        END AS statut_rentabilite,

        -- Qualité de paiement
        CASE
            WHEN COALESCE(p.nb_impayes, 0) = 0 AND COALESCE(p.taux_paiement_a_temps, 1) > 0.9
            THEN 'Excellent'
            WHEN COALESCE(p.nb_impayes, 0) <= 1
            THEN 'Bon'
            WHEN COALESCE(p.nb_impayes, 0) <= 3
            THEN 'Moyen'
            ELSE 'Mauvais'
        END AS qualite_paiement,

        -- Sinistralité
        CASE
            WHEN COALESCE(s.nb_sinistres, 0) = 0 THEN 'Sans_Sinistre'
            WHEN
                CASE
                    WHEN COALESCE(p.montant_primes_payees, 0) > 0
                    THEN (COALESCE(s.montant_total_indemnise, 0) / p.montant_primes_payees) * 100
                    ELSE 0
                END < 50
            THEN 'Faible'
            WHEN
                CASE
                    WHEN COALESCE(p.montant_primes_payees, 0) > 0
                    THEN (COALESCE(s.montant_total_indemnise, 0) / p.montant_primes_payees) * 100
                    ELSE 0
                END < 75
            THEN 'Normale'
            WHEN
                CASE
                    WHEN COALESCE(p.montant_primes_payees, 0) > 0
                    THEN (COALESCE(s.montant_total_indemnise, 0) / p.montant_primes_payees) * 100
                    ELSE 0
                END < 100
            THEN 'Elevee'
            ELSE 'Critique'
        END AS niveau_sinistralite,

        CURRENT_TIMESTAMP AS calculated_at
    FROM contrats c
    LEFT JOIN sinistres_agg s ON c.contrat_key = s.contrat_key
    LEFT JOIN primes_agg p ON c.contrat_key = p.contrat_key
)

SELECT * FROM final
