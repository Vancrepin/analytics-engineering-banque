-- ==========================================
-- Script d'initialisation du Data Warehouse
-- Exécuté automatiquement au 1er démarrage
-- ==========================================

-- Connexion à la base analytics_warehouse
\c analytics_warehouse;

-- ==========================================
-- CRÉATION DES SCHÉMAS (couches du warehouse)
-- ==========================================

-- Couche RAW : données brutes sources
CREATE SCHEMA IF NOT EXISTS raw;
COMMENT ON SCHEMA raw IS 'Données brutes non transformées - réplique exacte des sources';

-- Couche STAGING : données nettoyées et standardisées
CREATE SCHEMA IF NOT EXISTS staging;
COMMENT ON SCHEMA staging IS 'Données nettoyées, typées et standardisées';

-- Couche INTERMEDIATE : calculs intermédiaires
CREATE SCHEMA IF NOT EXISTS intermediate;
COMMENT ON SCHEMA intermediate IS 'Agrégations et calculs intermédiaires réutilisables';

-- Couche MARTS : modèles métier finaux
CREATE SCHEMA IF NOT EXISTS marts;
COMMENT ON SCHEMA marts IS 'Modèles métier prêts pour la visualisation';

-- ==========================================
-- CRÉATION DES TABLES RAW (structure initiale)
-- ==========================================

-- Table : Clients
CREATE TABLE IF NOT EXISTS raw.clients (
    client_id VARCHAR(50) PRIMARY KEY,
    date_creation TIMESTAMP,
    nom VARCHAR(100),
    prenom VARCHAR(100),
    email VARCHAR(150),
    telephone VARCHAR(20),
    date_naissance DATE,
    adresse TEXT,
    code_postal VARCHAR(10),
    ville VARCHAR(100),
    pays VARCHAR(50),
    segment_client VARCHAR(50),
    score_credit INTEGER,
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table : Transactions
CREATE TABLE IF NOT EXISTS raw.transactions (
    transaction_id VARCHAR(50) PRIMARY KEY,
    client_id VARCHAR(50),
    date_transaction DATE,
    heure_transaction TIME,
    montant DECIMAL(15,2),
    devise VARCHAR(3),
    type_transaction VARCHAR(50),
    canal VARCHAR(50),
    categorie VARCHAR(100),
    pays_beneficiaire VARCHAR(50),
    statut VARCHAR(50),
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (client_id) REFERENCES raw.clients(client_id)
);

-- Table : Contrats d'assurance
CREATE TABLE IF NOT EXISTS raw.contrats (
    contrat_id VARCHAR(50) PRIMARY KEY,
    client_id VARCHAR(50),
    produit_id VARCHAR(50),
    type_produit VARCHAR(50),
    date_souscription DATE,
    date_effet DATE,
    date_echeance DATE,
    prime_mensuelle DECIMAL(10,2),
    capital_assure DECIMAL(15,2),
    franchise DECIMAL(10,2),
    statut VARCHAR(50),
    mode_paiement VARCHAR(50),
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (client_id) REFERENCES raw.clients(client_id)
);

-- Table : Sinistres
CREATE TABLE IF NOT EXISTS raw.sinistres (
    sinistre_id VARCHAR(50) PRIMARY KEY,
    contrat_id VARCHAR(50),
    client_id VARCHAR(50),
    date_declaration DATE,
    date_survenance DATE,
    type_sinistre VARCHAR(100),
    montant_declare DECIMAL(12,2),
    montant_indemnise DECIMAL(12,2),
    statut VARCHAR(50),
    delai_traitement_jours INTEGER,
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (contrat_id) REFERENCES raw.contrats(contrat_id),
    FOREIGN KEY (client_id) REFERENCES raw.clients(client_id)
);

-- Table : Primes
CREATE TABLE IF NOT EXISTS raw.primes (
    prime_id VARCHAR(50) PRIMARY KEY,
    contrat_id VARCHAR(50),
    date_echeance DATE,
    montant_prime DECIMAL(10,2),
    date_paiement DATE,
    statut_paiement VARCHAR(50),
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (contrat_id) REFERENCES raw.contrats(contrat_id)
);

-- ==========================================
-- INDEX POUR OPTIMISER LES PERFORMANCES
-- ==========================================

-- Index sur les clés étrangères (améliore les jointures)
CREATE INDEX IF NOT EXISTS idx_transactions_client ON raw.transactions(client_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON raw.transactions(date_transaction);
CREATE INDEX IF NOT EXISTS idx_contrats_client ON raw.contrats(client_id);
CREATE INDEX IF NOT EXISTS idx_sinistres_contrat ON raw.sinistres(contrat_id);
CREATE INDEX IF NOT EXISTS idx_sinistres_client ON raw.sinistres(client_id);
CREATE INDEX IF NOT EXISTS idx_primes_contrat ON raw.primes(contrat_id);

-- ==========================================
-- GRANTS - Permissions pour l'utilisateur
-- ==========================================

GRANT USAGE ON SCHEMA raw TO analytics_user;
GRANT USAGE ON SCHEMA staging TO analytics_user;
GRANT USAGE ON SCHEMA intermediate TO analytics_user;
GRANT USAGE ON SCHEMA marts TO analytics_user;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA raw TO analytics_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA staging TO analytics_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA intermediate TO analytics_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA marts TO analytics_user;

-- Permissions pour les futures tables
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT ALL ON TABLES TO analytics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA staging GRANT ALL ON TABLES TO analytics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA intermediate GRANT ALL ON TABLES TO analytics_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA marts GRANT ALL ON TABLES TO analytics_user;

-- Message de confirmation
DO $$
BEGIN
    RAISE NOTICE '✅ Data Warehouse initialisé avec succès !';
    RAISE NOTICE '📊 Schémas créés : raw, staging, intermediate, marts';
    RAISE NOTICE '📋 Tables RAW créées : clients, transactions, contrats, sinistres, primes';
END $$;