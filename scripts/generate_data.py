"""
Script de génération de données fictives pour Banque & Assurance
Génère des données cohérentes et réalistes avec des patterns métier
"""

import os
import random
from datetime import datetime, timedelta
from faker import Faker
import pandas as pd
import numpy as np
from tqdm import tqdm

# Configuration
fake = Faker('fr_FR')  # Données en français
random.seed(42)
np.random.seed(42)

# Paramètres de génération
NB_CLIENTS = 5000
NB_TRANSACTIONS_PAR_CLIENT = (50, 200)  # min, max
NB_CONTRATS_PAR_CLIENT = (1, 4)
TAUX_SINISTRES = 0.15  # 15% des contrats ont au moins un sinistre

# Dates de référence
DATE_DEBUT = datetime(2022, 1, 1)
DATE_FIN = datetime(2024, 12, 31)


def generer_clients(nb_clients):
    """
    Génère les données clients avec segmentation réaliste
    """
    print(f"\n📊 Génération de {nb_clients} clients...")
    
    clients = []
    segments = ['Particulier', 'Professionnel', 'Premium', 'Jeune']
    poids_segments = [0.5, 0.25, 0.15, 0.1]
    
    for i in tqdm(range(nb_clients), desc="Clients"):
        # Date de création aléatoire
        date_creation = fake.date_time_between(
            start_date=DATE_DEBUT, 
            end_date=DATE_FIN
        )
        
        # Âge et segmentation cohérents
        age = random.randint(18, 75)
        date_naissance = datetime.now() - timedelta(days=age*365)
        
        segment = random.choices(segments, weights=poids_segments)[0]
        
        # Score crédit corrélé au segment
        if segment == 'Premium':
            score_credit = random.randint(750, 850)
        elif segment == 'Professionnel':
            score_credit = random.randint(650, 800)
        elif segment == 'Jeune':
            score_credit = random.randint(500, 700)
        else:
            score_credit = random.randint(550, 750)
        
        client = {
            'client_id': f'CLI_{i+1:06d}',
            'date_creation': date_creation,
            'nom': fake.last_name(),
            'prenom': fake.first_name(),
            'email': fake.email(),
            'telephone': fake.phone_number(),
            'date_naissance': date_naissance.date(),
            'adresse': fake.street_address(),
            'code_postal': fake.postcode(),
            'ville': fake.city(),
            'pays': 'France',
            'segment_client': segment,
            'score_credit': score_credit,
            'loaded_at': datetime.now()
        }
        clients.append(client)
    
    return pd.DataFrame(clients)


def generer_transactions(df_clients):
    """
    Génère les transactions bancaires avec patterns réalistes
    """
    print("\n💳 Génération des transactions...")
    
    transactions = []
    types_transaction = ['Virement', 'Prélèvement', 'Carte', 'Chèque', 'Espèces']
    canaux = ['Agence', 'Web', 'Mobile', 'ATM']
    categories = [
        'Alimentation', 'Transport', 'Logement', 'Loisirs', 'Santé',
        'Salaire', 'Épargne', 'Impôts', 'Assurance', 'Autres'
    ]
    
    transaction_id = 1
    
    for _, client in tqdm(df_clients.iterrows(), total=len(df_clients), desc="Transactions"):
        nb_trans = random.randint(*NB_TRANSACTIONS_PAR_CLIENT)
        date_client = client['date_creation']
        
        for _ in range(nb_trans):
            # Date de transaction entre date création client et aujourd'hui
            date_trans = fake.date_time_between(
                start_date=date_client,
                end_date=DATE_FIN
            )
            
            # Montant selon le segment client
            if client['segment_client'] == 'Premium':
                montant = random.uniform(50, 5000)
            elif client['segment_client'] == 'Professionnel':
                montant = random.uniform(100, 10000)
            else:
                montant = random.uniform(10, 2000)
            
            # 5% de transactions "anormales" (pour détection anomalies)
            if random.random() < 0.05:
                montant *= random.uniform(3, 10)  # Montant anormalement élevé
            
            # Heure : 80% en journée, 20% hors heures
            if random.random() < 0.8:
                heure = datetime.strptime(f"{random.randint(8, 19)}:{random.randint(0, 59)}", "%H:%M").time()
            else:
                heure = datetime.strptime(f"{random.randint(0, 7)}:{random.randint(0, 59)}", "%H:%M").time()
            
            # Pays : 95% France, 5% international
            pays = 'France' if random.random() < 0.95 else random.choice(['Espagne', 'Italie', 'Allemagne', 'Belgique'])
            
            transaction = {
                'transaction_id': f'TRX_{transaction_id:08d}',
                'client_id': client['client_id'],
                'date_transaction': date_trans.date(),
                'heure_transaction': heure,
                'montant': round(montant, 2),
                'devise': 'EUR',
                'type_transaction': random.choice(types_transaction),
                'canal': random.choice(canaux),
                'categorie': random.choice(categories),
                'pays_beneficiaire': pays,
                'statut': 'Validé' if random.random() < 0.98 else 'Refusé',
                'loaded_at': datetime.now()
            }
            transactions.append(transaction)
            transaction_id += 1
    
    return pd.DataFrame(transactions)


def generer_contrats(df_clients):
    """
    Génère les contrats d'assurance
    """
    print("\n📋 Génération des contrats d'assurance...")
    
    contrats = []
    types_produits = ['Auto', 'Habitation', 'Santé', 'Vie', 'Épargne']
    statuts = ['Actif', 'Actif', 'Actif', 'Actif', 'Résilié']  # 80% actifs
    
    contrat_id = 1
    
    for _, client in tqdm(df_clients.iterrows(), total=len(df_clients), desc="Contrats"):
        nb_contrats = random.randint(*NB_CONTRATS_PAR_CLIENT)
        
        for _ in range(nb_contrats):
            date_souscription = fake.date_time_between(
                start_date=client['date_creation'],
                end_date=DATE_FIN
            )
            
            type_produit = random.choice(types_produits)
            
            # Primes et capitaux selon le type de produit
            if type_produit == 'Auto':
                prime = random.uniform(30, 150)
                capital = random.uniform(10000, 50000)
                franchise = random.choice([200, 300, 500, 1000])
            elif type_produit == 'Habitation':
                prime = random.uniform(20, 100)
                capital = random.uniform(50000, 300000)
                franchise = random.choice([300, 500, 1000])
            elif type_produit == 'Santé':
                prime = random.uniform(50, 200)
                capital = 0
                franchise = 0
            elif type_produit == 'Vie':
                prime = random.uniform(100, 500)
                capital = random.uniform(50000, 500000)
                franchise = 0
            else:  # Épargne
                prime = random.uniform(100, 1000)
                capital = random.uniform(10000, 100000)
                franchise = 0
            
            # Durée du contrat
            duree_mois = random.choice([12, 24, 36, 48, 60])
            date_effet = date_souscription
            date_echeance = date_souscription + timedelta(days=duree_mois*30)
            
            contrat = {
                'contrat_id': f'CTR_{contrat_id:06d}',
                'client_id': client['client_id'],
                'produit_id': f'PROD_{type_produit}_{random.randint(1, 5):02d}',
                'type_produit': type_produit,
                'date_souscription': date_souscription.date(),
                'date_effet': date_effet.date(),
                'date_echeance': date_echeance.date(),
                'prime_mensuelle': round(prime, 2),
                'capital_assure': round(capital, 2),
                'franchise': franchise,
                'statut': random.choice(statuts),
                'mode_paiement': random.choice(['Prélèvement', 'Virement', 'Carte']),
                'loaded_at': datetime.now()
            }
            contrats.append(contrat)
            contrat_id += 1
    
    return pd.DataFrame(contrats)


def generer_sinistres(df_contrats):
    """
    Génère les sinistres avec logique métier réaliste
    """
    print("\n🚨 Génération des sinistres...")
    
    sinistres = []
    sinistre_id = 1
    
    # Types de sinistres par produit
    types_sinistres = {
        'Auto': ['Accident', 'Vol', 'Bris de glace', 'Incendie', 'Vandalisme'],
        'Habitation': ['Dégât des eaux', 'Incendie', 'Vol', 'Catastrophe naturelle', 'Bris de glace'],
        'Santé': ['Hospitalisation', 'Soins dentaires', 'Optique', 'Consultation', 'Médicaments'],
        'Vie': ['Décès', 'Invalidité', 'Incapacité'],
        'Épargne': []  # Pas de sinistres
    }
    
    for _, contrat in tqdm(df_contrats.iterrows(), total=len(df_contrats), desc="Sinistres"):
        # Seulement les contrats actifs peuvent avoir des sinistres
        if contrat['statut'] != 'Actif':
            continue
        
        # Probabilité d'avoir un sinistre
        if random.random() > TAUX_SINISTRES:
            continue
        
        type_produit = contrat['type_produit']
        if type_produit not in types_sinistres or not types_sinistres[type_produit]:
            continue
        
        # Nombre de sinistres (1-3)
        nb_sinistres = random.choices([1, 2, 3], weights=[0.7, 0.25, 0.05])[0]
        
        for _ in range(nb_sinistres):
            # Date de survenance après la date d'effet
            date_min = max(contrat['date_effet'], DATE_DEBUT.date())
            date_max = min(contrat['date_echeance'], DATE_FIN.date())
            
            if date_min >= date_max:
                continue
            
            date_survenance = fake.date_between(start_date=date_min, end_date=date_max)
            date_declaration = date_survenance + timedelta(days=random.randint(0, 7))
            
            # Montant du sinistre
            montant_declare = random.uniform(
                contrat['franchise'] + 100,
                contrat['capital_assure'] * 0.3
            ) if contrat['capital_assure'] > 0 else random.uniform(100, 5000)
            
            # Montant indemnisé (franchise déduite + politique)
            if random.random() < 0.85:  # 85% acceptés
                montant_indemnise = max(0, montant_declare - contrat['franchise'])
                montant_indemnise *= random.uniform(0.8, 1.0)  # Parfois moins que déclaré
                statut = 'Clos'
            else:
                montant_indemnise = 0
                statut = 'Rejeté'
            
            delai_traitement = random.randint(5, 60)
            
            sinistre = {
                'sinistre_id': f'SIN_{sinistre_id:06d}',
                'contrat_id': contrat['contrat_id'],
                'client_id': contrat['client_id'],
                'date_declaration': date_declaration,
                'date_survenance': date_survenance,
                'type_sinistre': random.choice(types_sinistres[type_produit]),
                'montant_declare': round(montant_declare, 2),
                'montant_indemnise': round(montant_indemnise, 2),
                'statut': statut,
                'delai_traitement_jours': delai_traitement,
                'loaded_at': datetime.now()
            }
            sinistres.append(sinistre)
            sinistre_id += 1
    
    return pd.DataFrame(sinistres)


def generer_primes(df_contrats):
    """
    Génère les échéances de primes
    """
    print("\n💰 Génération des primes...")
    
    primes = []
    prime_id = 1
    
    for _, contrat in tqdm(df_contrats.iterrows(), total=len(df_contrats), desc="Primes"):
        date_debut = contrat['date_effet']
        date_fin = min(contrat['date_echeance'], DATE_FIN.date())
        
        # Générer une prime par mois
        date_courante = date_debut
        while date_courante <= date_fin:
            # Date de paiement : quelques jours après l'échéance (ou en retard)
            if random.random() < 0.9:  # 90% payés à temps
                date_paiement = date_courante + timedelta(days=random.randint(0, 5))
                statut = 'Payé'
            elif random.random() < 0.95:  # 5% en retard
                date_paiement = date_courante + timedelta(days=random.randint(6, 30))
                statut = 'Retard'
            else:  # 5% impayés
                date_paiement = None
                statut = 'Impayé'
            
            prime = {
                'prime_id': f'PRM_{prime_id:08d}',
                'contrat_id': contrat['contrat_id'],
                'date_echeance': date_courante,
                'montant_prime': contrat['prime_mensuelle'],
                'date_paiement': date_paiement,
                'statut_paiement': statut,
                'loaded_at': datetime.now()
            }
            primes.append(prime)
            prime_id += 1
            
            # Passer au mois suivant
            date_courante = date_courante + timedelta(days=30)
    
    return pd.DataFrame(primes)


def sauvegarder_csv(df, nom_table):
    """
    Sauvegarde un DataFrame en CSV
    """
    os.makedirs('./data/raw', exist_ok=True)
    filepath = f'./data/raw/{nom_table}.csv'
    df.to_csv(filepath, index=False, encoding='utf-8')
    print(f"✅ {nom_table}.csv créé ({len(df):,} lignes)")
    return filepath


def main():
    """
    Fonction principale
    """
    print("=" * 60)
    print("🏦 GÉNÉRATION DE DONNÉES - BANQUE & ASSURANCE")
    print("=" * 60)
    
    # 1. Générer les clients
    df_clients = generer_clients(NB_CLIENTS)
    sauvegarder_csv(df_clients, 'clients')
    
    # 2. Générer les transactions
    df_transactions = generer_transactions(df_clients)
    sauvegarder_csv(df_transactions, 'transactions')
    
    # 3. Générer les contrats
    df_contrats = generer_contrats(df_clients)
    sauvegarder_csv(df_contrats, 'contrats')
    
    # 4. Générer les sinistres
    df_sinistres = generer_sinistres(df_contrats)
    sauvegarder_csv(df_sinistres, 'sinistres')
    
    # 5. Générer les primes
    df_primes = generer_primes(df_contrats)
    sauvegarder_csv(df_primes, 'primes')
    
    print("\n" + "=" * 60)
    print("✅ GÉNÉRATION TERMINÉE !")
    print("=" * 60)
    print(f"📊 Clients      : {len(df_clients):,}")
    print(f"💳 Transactions : {len(df_transactions):,}")
    print(f"📋 Contrats     : {len(df_contrats):,}")
    print(f"🚨 Sinistres    : {len(df_sinistres):,}")
    print(f"💰 Primes       : {len(df_primes):,}")
    print("\n📁 Fichiers sauvegardés dans ./data/raw/")


if __name__ == "__main__":
    main()
    