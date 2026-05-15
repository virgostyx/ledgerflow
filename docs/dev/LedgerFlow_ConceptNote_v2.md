
| ◈ LEDGERFLOW Application comptable belge — Rails 8 *Concept Note Technique & Fonctionnelle  |  Version 2.0* |
| :---: |

| Champ | Détail |
| :---- | :---- |
| Nom de l'application | LedgerFlow |
| Destinataire | Assistant de codage (Claude Code / IA) |
| Version du document | 2.0 — Révisée et finalisée |
| Application parente | BudgetFlow (Rails 8, Tailwind, ViewComponent) |
| Intégration | API REST avec tokens JWT — applications séparées |
| Stack CSS | Tailwind CSS — light UI, accents indigo \+ émeraude |
| Composants UI | ViewComponent — granularité atomique (atoms → organisms) |
| Méthodologie | TDD strict — RSpec, chaque feature précédée de ses tests |
| Conformité légale | PCMN ASBL/Fondation, TVA belge, BNB, Peppol/UBL 2026 |
| Statut | CONFIDENTIEL — Usage interne CaC Management BV |

| ▶ | *Ce document est la spécification complète de LedgerFlow. Il doit être lu intégralement avant toute implémentation. Toutes les décisions d'architecture, de design UI, d'organisation des composants, de structure des tests et d'intégration avec BudgetFlow sont prescriptives et non-négociables.* |
| :---- | :---- |

# **1\. Vision et positionnement**

## **1.1 Contexte organisationnel**

LedgerFlow est l'application comptable officielle d'une fondation belge gérant des projets de développement international financés par l'Union Européenne. Elle remplace WinBooks, outil jugé coûteux, monolithique et incompatible avec les flux de gestion de projets existants dans BudgetFlow.

LedgerFlow est une application Rails 8 autonome, distincte de BudgetFlow, qui communique avec elle exclusivement via une API REST sécurisée par tokens JWT. Les deux applications partagent une identité visuelle cohérente (light UI, Tailwind, ViewComponent) mais des bases de données et des processus serveur indépendants.

## **1.2 Principes directeurs absolus**

| ▶ | *Ces six principes gouvernent toutes les décisions d'implémentation. En cas de doute ou de conflit, revenir à ces principes.* |
| :---- | :---- |

| \# | Principe | Implication concrète |
| :---- | :---- | :---- |
| 1 | TDD strict | Chaque classe est précédée de ses specs. Aucun code sans test rouge d'abord. |
| 2 | DRY absolu | Toute logique dupliquée devient un service, un composant ou un concern. |
| 3 | Immuabilité comptable | Écriture validée \= jamais modifiée, jamais supprimée. Contre-passation uniquement. |
| 4 | Précision décimale | Jamais de Float pour les montants. Toujours BigDecimal / decimal(15,2) PostgreSQL. |
| 5 | Séparation des responsabilités | Modèle \= données. Service \= logique. Composant \= rendu. Contrôleur \= orchestration minimale. |
| 6 | Cohérence BudgetFlow | Même palette, mêmes conventions ViewComponent, même structure Tailwind. |

# **2\. Identité visuelle — LedgerFlow**

| ▶ | *L'assistant de codage doit implémenter ces tokens de design comme première étape, avant tout composant. Ils servent de référence pour l'ensemble de l'UI et garantissent la cohérence avec BudgetFlow.* |
| :---- | :---- |

## **2.1 Palette de couleurs Tailwind**

| Token | Classe Tailwind | Hex | Rôle |
| :---- | :---- | :---- | :---- |
| Primaire | indigo-700 / indigo-600 | \#3730A3 / \#4F46E5 | Navigation, boutons primaires, titres |
| Primaire clair | indigo-100 / violet-50 | \#E0E7FF / \#F5F3FF | Fonds callouts, badges, hover states |
| Accent succès | emerald-600 / emerald-100 | \#059669 / \#D1FAE5 | Validations, soldes positifs, statut OK |
| Danger | red-700 / red-100 | \#B91C1C / \#FEE2E2 | Erreurs, soldes négatifs, alertes critiques |
| Avertissement | amber-700 / amber-100 | \#B45309 / \#FEF3C7 | Brouillons, échéances proches, warnings |
| Neutre foncé | gray-700 / gray-900 | \#374151 / \#111827 | Texte principal, labels |
| Neutre clair | gray-100 / gray-50 | \#F3F4F6 / \#F9FAFB | Fonds alternés tableaux, sidebar |
| Blanc | white | \#FFFFFF | Fond général, cartes |

## **2.2 Typographie**

* Police : Inter (Google Fonts) — cohérente avec BudgetFlow

* Taille base : text-sm (14px) pour les tableaux et données comptables

* Taille corps : text-base (16px) pour les formulaires

* Titres de section : text-lg font-semibold text-indigo-700

* Montants comptables : font-mono text-sm — toujours alignés à droite

* Montants négatifs : text-red-600 font-medium

* Montants positifs : text-emerald-600 font-medium

## **2.3 Layout général de l'application**

LedgerFlow adopte un layout light UI à deux colonnes, identique à BudgetFlow :

| SIDEBAR (w-64, bg-white, border-r) • Logo LedgerFlow (◈ \+ texte indigo) • Exercice fiscal actif (badge pill) • Navigation principale (icônes Heroicons) • Indicateur de rôle utilisateur • Lien vers BudgetFlow (externe) • Déconnexion (bas de sidebar) | CONTENU PRINCIPAL (flex-1, bg-gray-50) • Header : fil d'Ariane \+ actions contextuelles • Zone principale : Turbo Frames • Notifications flash (Turbo Stream) • Footer : version \+ statut API BudgetFlow |
| :---- | :---- |

## **2.4 Navigation principale**

| Section | Icône Heroicon | Route | Rôles autorisés |
| :---- | :---- | :---- | :---- |
| Tableau de bord | chart-bar | / | Tous |
| Journaux & Écritures | book-open | /journal\_entries | accountant, admin |
| Factures | document-text | /invoices | manager, accountant, admin |
| Trésorerie | banknotes | /bank\_reconciliation | accountant, admin |
| TVA | calculator | /vat\_declarations | accountant, admin |
| Rapports | chart-pie | /reports | Tous |
| Paramètres | cog-6-tooth | /settings | admin uniquement |

# **3\. Architecture orientée objet — Couches et responsabilités**

| ▶ | *L'architecture suit une séparation stricte des responsabilités en six couches. Chaque couche a un rôle unique et ne doit pas empiéter sur les autres. Cette règle est la garantie de la maintenabilité à long terme.* |
| :---- | :---- |

## **3.1 Vue d'ensemble des couches**

| Couche | Répertoire | Responsabilité unique | Ne doit PAS |
| :---- | :---- | :---- | :---- |
| Models | app/models/ | Structure des données, associations, validations DB, scopes | Contenir de la logique métier complexe |
| Services | app/services/ | Logique métier, orchestration LightService, calculs | Toucher aux vues ou aux params HTTP |
| Queries | app/queries/ | Requêtes AR complexes, extractions analytiques | Modifier des données |
| Presenters | app/presenters/ | Formatage d'affichage (montants, dates, statuts) | Faire des requêtes DB |
| ViewComponents | app/components/ | Rendu HTML réutilisable, encapsulation UI | Contenir de la logique métier |
| Controllers | app/controllers/ | Authentification, params, orchestration minimale | Contenir logique métier ou requêtes complexes |

## **3.2 Couche Models — Règles de conception**

### **3.2.1 Conventions**

* Tous les modèles comptables dans le namespace Accounting::

* Chaque modèle inclut uniquement : associations, validations, scopes, enums, callbacks légers

* Les callbacks lourds (post\!, reverse\!) sont délégués à des services

* Pas de logique de présentation dans les modèles (utiliser Presenter)

### **3.2.2 Concerns partagés**

\# app/models/concerns/accounting/

Auditable          \# PaperTrail \+ audit\_log custom

Immutable          \# Bloque update/destroy sur posted

MonetaryPrecision  \# Validation BigDecimal, pas de Float

FiscalYearScoped   \# Scopes par exercice

Statusable         \# Machine à états partagée (AASM)

## **3.3 Couche Services — Architecture LightService**

### **3.3.1 Convention de nommage**

\# Organizers (orchestrent plusieurs actions)

Accounting::PostJournalEntry       \# Valider une écriture

Accounting::ReverseJournalEntry    \# Contre-passer

Accounting::PostInvoice            \# Valider \+ comptabiliser une facture

Accounting::CloseFiscalYear        \# Clôture d'exercice

Accounting::GenerateVatReturn      \# Calcul déclaration TVA

Accounting::ReconcileBankTransaction \# Lettrage bancaire

\# Actions (une responsabilité unique)

Accounting::Actions::ValidateBalance

Accounting::Actions::AssignSequenceNumber

Accounting::Actions::LockEntry

Accounting::Actions::UpdateAccountBalances

Accounting::Actions::WriteAuditLog

Accounting::Actions::BroadcastTurboUpdate

Peppol::Actions::BuildUblXml

Peppol::Actions::SendToDigiteal

Peppol::Actions::HandleDeliveryStatus

### **3.3.2 Contrat d'une Action LightService**

\# Chaque action DOIT respecter ce contrat

class Accounting::Actions::ValidateBalance

  include LightService::Action

  expects :entry          \# input déclaré explicitement

  promises :entry         \# output déclaré explicitement

  executed do |ctx|

    debit  \= ctx.entry.lines.sum(:debit)

    credit \= ctx.entry.lines.sum(:credit)

    unless (debit \- credit).abs \<= BigDecimal('0.01')

      ctx.fail\_with\_rollback\!(

        I18n.t('accounting.errors.unbalanced\_entry',

               debit: debit, credit: credit)

      )

    end

  end

end

## **3.4 Couche Queries — Query Objects**

### **3.4.1 Pourquoi des Query Objects**

Les requêtes complexes (grand livre, balance, analytique projet) sont extraites des modèles et des contrôleurs dans des objets dédiés. Chaque Query Object est testable indépendamment, réutilisable et composable.

\# Convention : app/queries/accounting/

class Accounting::TrialBalanceQuery

  def initialize(fiscal\_year:, as\_of: nil)

    @fiscal\_year \= fiscal\_year

    @as\_of \= as\_of || fiscal\_year.end\_date

  end

  def call

    Accounting::Account

      .with\_balance\_for(@fiscal\_year, as\_of: @as\_of)

      .order(:code)

  end

end

* TrialBalanceQuery — balance des comptes à une date

* GeneralLedgerQuery — grand livre par compte et période

* AnalyticProjectQuery — charges/produits par projet BudgetFlow

* VatGridQuery — montants par grille TVA pour une période

* InvoiceAgingQuery — balance âgée clients/fournisseurs

## **3.5 Couche Presenters — Formatage**

\# app/presenters/accounting/

class Accounting::MoneyPresenter

  def initialize(amount, currency: 'EUR', locale: :fr)

    @amount \= amount

    @currency \= currency

    @locale \= locale

  end

  def format           \# '1 234,56 €'

  def format\_signed    \# '+1 234,56 €' ou '-1 234,56 €'

  def css\_class        \# 'text-emerald-600' ou 'text-red-600'

  def zero?            \# true/false

end

* MoneyPresenter — formatage montants (EUR, multi-devises)

* DatePresenter — dates belges (dd/mm/yyyy), périodes TVA

* StatusPresenter — libellés et couleurs Tailwind par statut

* AccountPresenter — affichage code+libellé PCMN

* InvoicePresenter — résumé facture pour listes et PDF

## **3.6 Couche ViewComponent — Architecture atomique**

### **3.6.1 Trois niveaux (Atomic Design adapté Rails)**

| Niveau | Répertoire | Exemples | Caractéristiques |
| :---- | :---- | :---- | :---- |
| Atoms | app/components/ui/ | ButtonComponent, BadgeComponent, InputComponent, SelectComponent, AlertComponent, AvatarComponent, SpinnerComponent | Aucune logique métier. Purement visuel. Slot-based. |
| Molecules | app/components/accounting/ | MoneyDisplayComponent, StatusBadgeComponent, AccountSelectComponent, JournalEntryRowComponent, InvoiceCardComponent, BalanceIndicatorComponent | Combinent des Atoms. Peuvent recevoir des Presenters. |
| Organisms | app/components/layouts/ | JournalEntryFormComponent, InvoiceTableComponent, TrialBalanceComponent, DashboardKpiComponent, ReconciliationPanelComponent | Composants complets, propres à une feature. |

### **3.6.2 Convention de structure d'un composant**

\# app/components/ui/badge\_component.rb

class Ui::BadgeComponent \< ViewComponent::Base

  VARIANTS \= {

    default: 'bg-gray-100 text-gray-700',

    success: 'bg-emerald-100 text-emerald-700',

    warning: 'bg-amber-100 text-amber-700',

    danger:  'bg-red-100 text-red-700',

    primary: 'bg-indigo-100 text-indigo-700',

  }.freeze

  def initialize(label:, variant: :default, size: :sm)

    @label   \= label

    @variant \= variant

    @size    \= size

  end

  def css\_classes

    "\#{VARIANTS\[@variant\]} inline-flex items-center

     px-2.5 py-0.5 rounded-full text-xs font-medium"

  end

end

\<%\# app/components/ui/badge\_component.html.erb %\>

\<span class="\<%= css\_classes %\>"\>\<%= @label %\>\</span\>

### **3.6.3 Composant Molecule — MoneyDisplayComponent**

class Accounting::MoneyDisplayComponent \< ViewComponent::Base

  def initialize(amount:, currency: 'EUR', show\_sign: false)

    @presenter \= Accounting::MoneyPresenter.new(

      amount, currency: currency

    )

    @show\_sign \= show\_sign

  end

  def formatted   \= @show\_sign ? @presenter.format\_signed

                               : @presenter.format

  def css\_class   \= @presenter.css\_class

end

### **3.6.4 Composant Organism — BalanceIndicatorComponent (Stimulus)**

class Accounting::BalanceIndicatorComponent \< ViewComponent::Base

  def initialize(entry:)

    @entry \= entry

  end

  \# Rendu : badge vert/rouge \+ montant déséquilibre

  \# Mis à jour en temps réel par Stimulus journal-entry-form

end

### **3.6.5 Tests ViewComponent — Convention TDD**

\# spec/components/ui/badge\_component\_spec.rb

RSpec.describe Ui::BadgeComponent, type: :component do

  it 'renders with default variant' do

    render\_inline(described\_class.new(label: 'Brouillon'))

    expect(page).to have\_css('span.bg-gray-100', text: 'Brouillon')

  end

  it 'renders with success variant' do

    render\_inline(described\_class.new(label: 'Validé', variant: :success))

    expect(page).to have\_css('span.bg-emerald-100')

  end

  it 'renders with danger variant' do

    render\_inline(described\_class.new(label: 'Erreur', variant: :danger))

    expect(page).to have\_css('span.bg-red-100')

  end

end

# **4\. Structure complète du projet Rails**

## **4.1 Arborescence**

ledgerflow/

├── app/

│   ├── components/              \# ViewComponents

│   │   ├── ui/                  \# Atoms

│   │   │   ├── button\_component.rb

│   │   │   ├── badge\_component.rb

│   │   │   ├── input\_component.rb

│   │   │   ├── select\_component.rb

│   │   │   ├── alert\_component.rb

│   │   │   ├── card\_component.rb

│   │   │   ├── modal\_component.rb

│   │   │   └── spinner\_component.rb

│   │   ├── accounting/          \# Molecules

│   │   │   ├── money\_display\_component.rb

│   │   │   ├── status\_badge\_component.rb

│   │   │   ├── account\_select\_component.rb

│   │   │   ├── journal\_entry\_row\_component.rb

│   │   │   ├── invoice\_card\_component.rb

│   │   │   └── balance\_indicator\_component.rb

│   │   └── layouts/             \# Organisms

│   │       ├── journal\_entry\_form\_component.rb

│   │       ├── invoice\_table\_component.rb

│   │       ├── trial\_balance\_component.rb

│   │       ├── dashboard\_kpi\_component.rb

│   │       └── reconciliation\_panel\_component.rb

│   ├── controllers/

│   │   ├── application\_controller.rb

│   │   ├── sessions\_controller.rb      \# Devise override

│   │   ├── registrations\_controller.rb \# Devise override

│   │   └── accounting/

│   │       ├── dashboard\_controller.rb

│   │       ├── journal\_entries\_controller.rb

│   │       ├── invoices\_controller.rb

│   │       ├── bank\_reconciliation\_controller.rb

│   │       ├── vat\_declarations\_controller.rb

│   │       ├── reports\_controller.rb

│   │       └── fiscal\_years\_controller.rb

│   ├── javascript/

│   │   └── controllers/         \# Stimulus

│   │       ├── journal\_entry\_form\_controller.js

│   │       ├── account\_search\_controller.js

│   │       ├── money\_input\_controller.js

│   │       ├── reconciliation\_controller.js

│   │       └── flash\_controller.js

│   ├── models/

│   │   ├── concerns/accounting/

│   │   │   ├── auditable.rb

│   │   │   ├── immutable.rb

│   │   │   ├── monetary\_precision.rb

│   │   │   └── statusable.rb

│   │   └── accounting/

│   │       ├── account.rb

│   │       ├── fiscal\_year.rb

│   │       ├── journal.rb

│   │       ├── journal\_entry.rb

│   │       ├── journal\_entry\_line.rb

│   │       ├── partner.rb

│   │       ├── invoice.rb

│   │       ├── invoice\_line.rb

│   │       ├── bank\_account.rb

│   │       ├── bank\_transaction.rb

│   │       ├── vat\_declaration.rb

│   │       └── audit\_log.rb

│   ├── presenters/accounting/

│   │   ├── money\_presenter.rb

│   │   ├── date\_presenter.rb

│   │   ├── status\_presenter.rb

│   │   ├── account\_presenter.rb

│   │   └── invoice\_presenter.rb

│   ├── queries/accounting/

│   │   ├── trial\_balance\_query.rb

│   │   ├── general\_ledger\_query.rb

│   │   ├── analytic\_project\_query.rb

│   │   ├── vat\_grid\_query.rb

│   │   └── invoice\_aging\_query.rb

│   └── services/

│       ├── accounting/

│       │   ├── actions/          \# LightService Actions

│       │   ├── post\_journal\_entry.rb

│       │   ├── reverse\_journal\_entry.rb

│       │   ├── post\_invoice.rb

│       │   ├── close\_fiscal\_year.rb

│       │   ├── generate\_vat\_return.rb

│       │   └── reconcile\_bank\_transaction.rb

│       └── peppol/

│           ├── actions/

│           ├── send\_invoice.rb

│           └── receive\_invoice.rb

├── config/

│   ├── routes.rb

│   └── initializers/

│       ├── budgetflow\_api.rb    \# Config JWT \+ URL BudgetFlow

│       └── peppol.rb            \# Config Digiteal API

├── db/

│   ├── migrate/

│   └── seeds/

│       ├── pcmn\_asbl.json       \# 782 comptes PCMN

│       └── journals.json        \# Journaux prédéfinis

└── spec/

    ├── components/              \# Tests ViewComponent

    ├── models/accounting/

    ├── services/accounting/

    ├── queries/accounting/

    ├── presenters/accounting/

    ├── requests/accounting/     \# Controller specs

    ├── system/                  \# Tests Capybara

    └── support/

        ├── shared\_contexts/

        ├── shared\_examples/

        └── factories/

# **5\. Landing page et authentification Devise**

## **5.1 Landing page publique**

LedgerFlow dispose d'une landing page publique accessible sans authentification. Elle présente l'application et oriente les visiteurs vers la connexion.

### **5.1.1 Structure de la landing page**

* Route : GET / (root\_path) → LandingController\#index

* Layout dédié : layouts/landing.html.erb (sans sidebar, sans auth)

* Sections : Hero, Fonctionnalités, Conformité légale, Appel à l'action

* CTA principal : bouton 'Se connecter' → /users/sign\_in

### **5.1.2 Design de la landing page**

* Hero : fond blanc, titre LedgerFlow en indigo-700, sous-titre gray-500

* Badge : 'Conforme PCMN • TVA belge • Peppol 2026' en indigo-100/indigo-700

* Grille de 3 fonctionnalités avec icônes Heroicons et description

* Footer : copyright fondation \+ lien BudgetFlow

## **5.2 Authentification Devise — Configuration complète**

### **5.2.1 Modules Devise à activer**

\# app/models/user.rb

class User \< ApplicationRecord

  devise :database\_authenticatable,

         :registerable,

         :recoverable,      \# Mot de passe oublié

         :rememberable,     \# 'Se souvenir de moi'

         :validatable,      \# Validations email \+ password

         :lockable,         \# Verrouillage après 5 tentatives

         :timeoutable,      \# Session expire après 8h

         :trackable         \# Historique connexions

  enum role: { admin: 0, accountant: 1, manager: 2,

               auditor: 3, budget\_user: 4 }

  \# Paramètres de sécurité

  \# timeout\_in : 8.hours (config/initializers/devise.rb)

  \# maximum\_attempts : 5

  \# unlock\_strategy : :email

end

### **5.2.2 Pages Devise à personnaliser (ViewComponent \+ Tailwind)**

| Page Devise | Route | Contenu |
| :---- | :---- | :---- |
| Sign In | /users/sign\_in | Formulaire email/password \+ 'Se souvenir' \+ lien mot de passe oublié |
| Sign Out | DELETE /users/sign\_out | Redirection vers landing avec flash de confirmation |
| Forgot password | /users/password/new | Formulaire email avec instructions |
| Reset password | /users/password/edit | Formulaire nouveau mot de passe \+ confirmation |
| Account locked | /users/unlock/new | Explication verrouillage \+ renvoi email |
| Session timeout | Redirect auto | Flash warning 'Session expirée, reconnectez-vous' |

### **5.2.3 Layout des pages d'authentification**

\<%\# app/views/layouts/devise.html.erb %\>

\<\!DOCTYPE html\>

\<html\>

  \<head\>

    \<title\>LedgerFlow\</title\>

    \<%= csrf\_meta\_tags %\>

    \<%= stylesheet\_link\_tag 'application' %\>

  \</head\>

  \<body class="min-h-screen bg-gray-50 flex"\>

    \<div class="flex flex-col items-center justify-center

                flex-1 px-4 py-12"\>

      \<\!-- Logo centré \--\>

      \<div class="mb-8 text-center"\>

        \<span class="text-4xl text-indigo-700"\>◈\</span\>

        \<h1 class="text-2xl font-bold text-indigo-700"\>LedgerFlow\</h1\>

        \<p class="text-sm text-gray-500"\>Comptabilité conforme • Belgique\</p\>

      \</div\>

      \<\!-- Card formulaire \--\>

      \<div class="bg-white shadow-sm ring-1 ring-gray-200

                  rounded-xl p-8 w-full max-w-md"\>

        \<%= yield %\>

      \</div\>

    \</div\>

    \<\!-- Panel droite : visuel landing \--\>

    \<div class="hidden lg:flex flex-col justify-center

                bg-indigo-700 w-96 p-12"\>

      \<\!-- Features list en blanc \--\>

    \</div\>

  \</body\>

\</html\>

## **5.3 Routes complètes**

\# config/routes.rb

Rails.application.routes.draw do

  \# Landing page publique

  root 'landing\#index'

  \# Devise — authentification

  devise\_for :users, controllers: {

    sessions:      'users/sessions',

    passwords:     'users/passwords',

    registrations: 'users/registrations'

  }

  \# Application comptable (authentifié)

  authenticate :user do

    namespace :accounting do

      root to: 'dashboard\#index'

      resources :journal\_entries do

        member do

          post :post\_entry

          post :reverse

        end

      end

      resources :invoices do

        member do

          post :validate\_invoice

          post :send\_peppol

        end

      end

      resources :vat\_declarations, only: \[:index, :new, :create, :show\]

      resources :fiscal\_years do

        member { post :close }

      end

      resource  :bank\_reconciliation, only: \[:show, :update\]

      namespace :reports do

        get :trial\_balance

        get :balance\_sheet

        get :income\_statement

        get :general\_ledger

        get :analytic\_by\_project

      end

    end

  end

  \# API BudgetFlow (JWT)

  namespace :api do

    namespace :v1 do

      resources :journal\_entries, only: \[:index, :show\]

      resources :invoices,        only: \[:index, :show\]

      resources :projects,        only: \[\] do

        get :accounting\_summary, on: :member

      end

    end

  end

  \# Webhooks Peppol (public, HMAC-signed)

  post '/peppol/webhooks', to: 'peppol/webhooks\#receive'

end

# **6\. Intégration BudgetFlow — API REST JWT**

| ▶ | *Les deux applications sont indépendantes et ne partagent pas de base de données. Toute communication passe par l'API REST. Chaque application expose des endpoints consommés par l'autre. Le couplage est minimal et documenté.* |
| :---- | :---- |

## **6.1 Architecture d'intégration**

| Direction | Émetteur | Récepteur | Données échangées |
| :---- | :---- | :---- | :---- |
| BudgetFlow → LedgerFlow | BudgetFlow | LedgerFlow API v1 | Dépenses validées → création écriture comptable automatique |
| LedgerFlow → BudgetFlow | LedgerFlow | BudgetFlow API | Statut comptable des dépenses, factures générées |
| LedgerFlow → LedgerFlow | Peppol webhook | LedgerFlow | Factures fournisseurs reçues via Digiteal |

## **6.2 Authentification JWT**

### **6.2.1 Génération et validation des tokens**

\# config/initializers/budgetflow\_api.rb

BUDGETFLOW\_API\_URL    \= ENV.fetch('BUDGETFLOW\_API\_URL')

LEDGERFLOW\_JWT\_SECRET \= Rails.application.credentials.jwt\_secret\!

BUDGETFLOW\_JWT\_SECRET \= Rails.application.credentials.budgetflow\_jwt\_secret\!

\# app/services/api/jwt\_service.rb

class Api::JwtService

  ALGORITHM \= 'HS256'

  EXPIRY    \= 1.hour

  def self.encode(payload)

    JWT.encode(

      payload.merge(exp: EXPIRY.from\_now.to\_i, iss: 'ledgerflow'),

      LEDGERFLOW\_JWT\_SECRET, ALGORITHM

    )

  end

  def self.decode(token, secret: BUDGETFLOW\_JWT\_SECRET)

    JWT.decode(token, secret, true, algorithm: ALGORITHM).first

  rescue JWT::DecodeError \=\> e

    raise Api::AuthenticationError, e.message

  end

end

### **6.2.2 Middleware d'authentification API**

\# app/controllers/api/v1/base\_controller.rb

class Api::V1::BaseController \< ActionController::API

  before\_action :authenticate\_api\_request\!

  private

  def authenticate\_api\_request\!

    token \= request.headers\['Authorization'\]&.split(' ')&.last

    @api\_payload \= Api::JwtService.decode(token)

  rescue Api::AuthenticationError

    render json: { error: 'Unauthorized' }, status: :unauthorized

  end

end

## **6.3 Endpoints exposés par LedgerFlow**

| Méthode | Endpoint | Paramètres | Réponse |
| :---- | :---- | :---- | :---- |
| POST | /api/v1/journal\_entries | project\_id, amount, date, description, account\_code | { id, reference, status } |
| GET | /api/v1/journal\_entries | project\_id, fiscal\_year\_id, page | Array d'écritures paginées |
| GET | /api/v1/projects/:id/accounting\_summary | project\_id, year | { charges, produits, solde, taux\_absorption } |
| GET | /api/v1/invoices | project\_id, status, page | Array de factures paginées |

## **6.4 Client HTTP vers BudgetFlow**

\# app/services/api/budgetflow\_client.rb

class Api::BudgetflowClient

  include HTTParty

  base\_uri BUDGETFLOW\_API\_URL

  def initialize

    @token \= Api::JwtService.encode({ client: 'ledgerflow' })

    @headers \= {

      'Authorization' \=\> "Bearer \#{@token}",

      'Content-Type'  \=\> 'application/json'

    }

  end

  def notify\_entry\_posted(entry)

    post('/api/v1/accounting\_events',

         body: { event: 'entry\_posted',

                 entry\_id: entry.id,

                 project\_id: entry.project\_id }.to\_json,

         headers: @headers)

  end

end

## **6.5 Flux complet : Dépense BudgetFlow → Écriture LedgerFlow**

1. BudgetFlow valide une dépense projet (status: approved)

2. BudgetFlow POST /api/v1/journal\_entries avec JWT token

3. LedgerFlow::Api::V1::JournalEntriesController\#create reçoit la requête

4. Vérifie le token JWT (middleware) — 401 si invalide

5. Appelle Accounting::PostJournalEntry organizer

6. Écriture créée (ACH journal), liée au project\_id BudgetFlow

7. Réponse JSON 201 avec { reference, status }

8. BudgetFlow stocke la référence LedgerFlow sur la dépense

9. LedgerFlow notifie BudgetFlow via Api::BudgetflowClient (async Solid Queue)

# **7\. Modèle de données — Migrations complètes**

| ▶ | *Toutes les migrations incluent des contraintes PostgreSQL (CHECK, NOT NULL, UNIQUE, FOREIGN KEY) en complément des validations Rails. La DB est le dernier rempart d'intégrité. Le trigger partie double est obligatoire.* |
| :---- | :---- |

## **7.1 Users (Devise)**

create\_table :users do |t|

  \# Colonnes Devise standard

  t.string   :email,                  null: false, default: ''

  t.string   :encrypted\_password,     null: false, default: ''

  t.string   :reset\_password\_token

  t.datetime :reset\_password\_sent\_at

  t.datetime :remember\_created\_at

  t.integer  :sign\_in\_count,           null: false, default: 0

  t.datetime :current\_sign\_in\_at

  t.datetime :last\_sign\_in\_at

  t.string   :current\_sign\_in\_ip

  t.string   :last\_sign\_in\_ip

  t.integer  :failed\_attempts,         null: false, default: 0

  t.string   :unlock\_token

  t.datetime :locked\_at

  \# Colonnes métier

  t.integer  :role,      null: false, default: 3   \# auditor par défaut

  t.string   :full\_name, null: false

  t.string   :locale,    null: false, default: 'fr'

  t.boolean  :active,    null: false, default: true

  t.timestamps

end

add\_index :users, :email,                unique: true

add\_index :users, :reset\_password\_token, unique: true

add\_index :users, :unlock\_token,         unique: true

## **7.2 Accounts (Plan Comptable PCMN)**

create\_table :accounting\_accounts do |t|

  t.string  :code,             null: false, limit: 10

  t.string  :label\_fr,         null: false

  t.string  :label\_nl

  t.integer :account\_class,    null: false   \# 1..7

  t.integer :account\_type,     null: false

  \# enum: asset(0)/liability(1)/equity(2)/revenue(3)/expense(4)

  t.integer :normal\_balance,   null: false

  \# enum: debit(0)/credit(1)

  t.boolean :reconcilable,     null: false, default: false

  t.boolean :active,           null: false, default: true

  t.boolean :is\_leaf,          null: false, default: true

  t.integer :vat\_code\_default

  t.bigint  :parent\_id

  t.decimal :balance\_debit,    precision: 15, scale: 2, default: 0

  t.decimal :balance\_credit,   precision: 15, scale: 2, default: 0

  t.timestamps

end

add\_index :accounting\_accounts, :code, unique: true

add\_index :accounting\_accounts, :parent\_id

## **7.3 Fiscal Years**

create\_table :accounting\_fiscal\_years do |t|

  t.integer  :year,       null: false

  t.date     :start\_date, null: false

  t.date     :end\_date,   null: false

  t.integer  :status,     null: false, default: 0

  \# enum: open(0)/pre\_closing(1)/closed(2)

  t.decimal  :opening\_balance, precision: 15, scale: 2, default: 0

  t.datetime :closed\_at

  t.bigint   :closed\_by\_id

  t.timestamps

end

add\_index :accounting\_fiscal\_years, :year, unique: true

\# CHECK : start\_date \< end\_date

\# CHECK : un seul exercice 'open' à la fois (partial unique index)

## **7.4 Journals**

create\_table :accounting\_journals do |t|

  t.string  :code,              null: false, limit: 5

  t.string  :label\_fr,          null: false

  t.integer :journal\_type,      null: false

  \# enum: purchase(0)/sale(1)/bank(2)/cash(3)/misc(4)/payroll(5)

  t.bigint  :default\_account\_id

  t.string  :sequence\_prefix,   null: false

  t.integer :current\_sequence,  null: false, default: 0

  t.boolean :active,            null: false, default: true

  t.timestamps

end

add\_index :accounting\_journals, :code, unique: true

## **7.5 Journal Entries**

create\_table :accounting\_journal\_entries do |t|

  t.references :journal,     null: false,

               foreign\_key: { to\_table: :accounting\_journals }

  t.references :fiscal\_year, null: false,

               foreign\_key: { to\_table: :accounting\_fiscal\_years }

  t.date    :entry\_date,   null: false

  t.string  :reference,    null: false

  t.string  :description

  t.integer :status,       null: false, default: 0

  \# enum: draft(0)/posted(1)/reversed(2)

  t.string  :source\_type   \# polymorphic

  t.bigint  :source\_id

  t.bigint  :reversal\_of\_id

  t.integer :project\_id    \# ID BudgetFlow (pas de FK — app séparée)

  t.string  :external\_ref  \# référence dépense BudgetFlow

  t.string  :locked\_by

  t.datetime :locked\_at

  t.timestamps

end

add\_index :accounting\_journal\_entries, :reference, unique: true

add\_index :accounting\_journal\_entries, \[:source\_type, :source\_id\]

add\_index :accounting\_journal\_entries, :project\_id

| ▶ | *Note importante : le champ project\_id est un entier ordinaire (pas de clé étrangère DB), car BudgetFlow est une application séparée. L'intégrité référentielle est assurée au niveau applicatif via l'API JWT.* |
| :---- | :---- |

## **7.6 Journal Entry Lines**

create\_table :accounting\_journal\_entry\_lines do |t|

  t.references :journal\_entry, null: false,

               foreign\_key: { to\_table: :accounting\_journal\_entries }

  t.references :account, null: false,

               foreign\_key: { to\_table: :accounting\_accounts }

  t.references :partner,

               foreign\_key: { to\_table: :accounting\_partners }

  t.decimal :debit,  precision: 15, scale: 2, null: false, default: 0

  t.decimal :credit, precision: 15, scale: 2, null: false, default: 0

  t.string  :label

  t.integer :vat\_code      \# grille TVA (01..88)

  t.decimal :vat\_amount,   precision: 15, scale: 2

  t.string  :currency,     null: false, default: 'EUR'

  t.decimal :amount\_currency, precision: 15, scale: 2

  t.decimal :exchange\_rate,   precision: 10, scale: 6

  t.integer :sort\_order,   null: false, default: 0

  t.timestamps

end

\# CHECK : debit \>= 0 AND credit \>= 0

\# CHECK : NOT (debit \> 0 AND credit \> 0\)  — jamais les deux

\# CHECK : debit \> 0 OR credit \> 0          — au moins un

\# TRIGGER : enforce\_double\_entry (voir §10.4)

## **7.7–7.12 Autres tables**

Les tables accounting\_partners, accounting\_invoices, accounting\_invoice\_lines, accounting\_bank\_accounts, accounting\_bank\_transactions, accounting\_vat\_declarations et accounting\_audit\_logs restent identiques à la spécification v1.0 (§3.6 à §3.12). Se référer à ce document pour leurs migrations complètes. La seule modification est la suppression de toute foreign key vers une table BudgetFlow — les liens inter-applications passent par l'API JWT.

# **8\. Méthodologie TDD — Convention stricte**

| ▶ | *TDD signifie Test-Driven Development : le test est écrit AVANT le code de production. L'assistant de codage doit impérativement suivre le cycle Red → Green → Refactor pour chaque feature. Aucune exception.* |
| :---- | :---- |

## **8.1 Cycle Red → Green → Refactor**

10. RED : écrire le test qui décrit le comportement attendu — il doit échouer

11. GREEN : écrire le minimum de code de production pour faire passer le test

12. REFACTOR : améliorer le code sans casser les tests (DRY, lisibilité, performance)

13. Répéter pour chaque comportement unitaire

## **8.2 Ordre d'implémentation TDD par couche**

| Ordre | Couche | Fichier de test créé en premier | Puis le code de production |
| :---- | :---- | :---- | :---- |
| 1 | Model | spec/models/accounting/account\_spec.rb | app/models/accounting/account.rb |
| 2 | Query | spec/queries/accounting/trial\_balance\_query\_spec.rb | app/queries/accounting/trial\_balance\_query.rb |
| 3 | Service Action | spec/services/accounting/actions/validate\_balance\_spec.rb | app/services/accounting/actions/validate\_balance.rb |
| 4 | Service Organizer | spec/services/accounting/post\_journal\_entry\_spec.rb | app/services/accounting/post\_journal\_entry.rb |
| 5 | Presenter | spec/presenters/accounting/money\_presenter\_spec.rb | app/presenters/accounting/money\_presenter.rb |
| 6 | ViewComponent | spec/components/accounting/money\_display\_component\_spec.rb | app/components/accounting/money\_display\_component.rb |
| 7 | Controller/Request | spec/requests/accounting/journal\_entries\_spec.rb | app/controllers/accounting/journal\_entries\_controller.rb |
| 8 | System | spec/system/journal\_entry\_workflow\_spec.rb | Intégration complète Capybara |

## **8.3 Shared Contexts et Shared Examples**

### **8.3.1 Shared Contexts**

\# spec/support/shared\_contexts/accounting.rb

RSpec.shared\_context 'with\_open\_fiscal\_year' do

  let\!(:fiscal\_year) { create(:fiscal\_year, status: :open) }

end

RSpec.shared\_context 'with\_pcmn\_accounts' do

  let\!(:account\_604) { create(:account, code: '604000', label\_fr: 'Services divers') }

  let\!(:account\_440) { create(:account, code: '440000', label\_fr: 'Fournisseurs') }

  let\!(:account\_400) { create(:account, code: '400000', label\_fr: 'Clients') }

  let\!(:account\_700) { create(:account, code: '700000', label\_fr: 'Ventes') }

  let\!(:account\_451) { create(:account, code: '451000', label\_fr: 'TVA à reverser') }

end

RSpec.shared\_context 'with\_authenticated\_api' do

  let(:jwt\_token) { Api::JwtService.encode({ client: 'budgetflow' }) }

  let(:auth\_headers) { { 'Authorization' \=\> "Bearer \#{jwt\_token}" } }

end

### **8.3.2 Shared Examples**

\# spec/support/shared\_examples/immutable\_record.rb

RSpec.shared\_examples 'an immutable posted record' do

  it 'cannot be updated after posting' do

    expect { subject.update\!(description: 'modified') }

      .to raise\_error(Accounting::ImmutableRecordError)

  end

  it 'cannot be destroyed after posting' do

    expect { subject.destroy\! }

      .to raise\_error(Accounting::ImmutableRecordError)

  end

end

\# spec/support/shared\_examples/jwt\_protected\_endpoint.rb

RSpec.shared\_examples 'a JWT-protected endpoint' do

  context 'without token' do

    it 'returns 401' do

      subject

      expect(response).to have\_http\_status(:unauthorized)

    end

  end

  context 'with invalid token' do

    let(:jwt\_token) { 'invalid.token.here' }

    it 'returns 401' do

      subject

      expect(response).to have\_http\_status(:unauthorized)

    end

  end

end

## **8.4 Suite de tests complète par couche**

### **8.4.1 Concerns — spec/models/concerns/**

\# spec/models/concerns/accounting/immutable\_spec.rb

RSpec.describe Accounting::Immutable, type: :model do

  let(:entry) { create(:journal\_entry, :posted) }

  it\_behaves\_like 'an immutable posted record' do

    subject { entry }

  end

end

### **8.4.2 Models — Échantillon critique**

\# spec/models/accounting/journal\_entry\_line\_spec.rb

RSpec.describe Accounting::JournalEntryLine, type: :model do

  include\_context 'with\_pcmn\_accounts'

  describe 'validations de la partie double' do

    it 'est invalide si débit ET crédit sont positifs' do

      line \= build(:journal\_entry\_line, debit: 100, credit: 50\)

      expect(line).not\_to be\_valid

      expect(line.errors\[:base\]).to include(I18n.t('accounting.errors.dual\_side'))

    end

    it 'est invalide si débit ET crédit sont nuls' do

      line \= build(:journal\_entry\_line, debit: 0, credit: 0\)

      expect(line).not\_to be\_valid

    end

    it 'rejette les Float pour les montants' do

      line \= build(:journal\_entry\_line, debit: 100.0)

      \# MonetaryPrecision concern force BigDecimal

      expect(line.debit).to be\_a(BigDecimal)

    end

    it 'le trigger DB rejette les écritures déséquilibrées' do

      entry \= create(:journal\_entry)

      expect {

        create(:journal\_entry\_line, journal\_entry: entry,

               debit: 100, credit: 0\)

        \# Pas de ligne crédit compensatrice

      }.to raise\_error(ActiveRecord::StatementInvalid, /Unbalanced entry/)

    end

  end

end

### **8.4.3 Services — Organizer complet**

RSpec.describe Accounting::PostJournalEntry, type: :service do

  include\_context 'with\_open\_fiscal\_year'

  include\_context 'with\_pcmn\_accounts'

  let(:entry) { create(:journal\_entry, :with\_balanced\_lines) }

  describe '.call — chemin de succès' do

    subject(:result) { described\_class.call(entry: entry) }

    it 'retourne un contexte de succès' do

      expect(result).to be\_success

    end

    it 'passe le statut en posted' do

      expect { result }.to change { entry.reload.status }

        .from('draft').to('posted')

    end

    it 'exécute toutes les actions dans l ordre' do

      \# Vérifier via audit\_log que toutes les actions ont tourné

      result

      expect(Accounting::AuditLog.last.action).to eq('post\_entry')

    end

    it 'est atomique : rollback si une action échoue' do

      allow(Accounting::Actions::UpdateAccountBalances)

        .to receive(:execute).and\_raise(StandardError)

      expect { result }.not\_to change { entry.reload.status }

    end

  end

  describe '.call — échec ValidateBalance' do

    let(:entry) { create(:journal\_entry, :with\_unbalanced\_lines) }

    it 'retourne un contexte d échec' do

      expect(result).to be\_failure

    end

    it 'inclut le message d erreur' do

      expect(result.message).to include('déséquilibré')

    end

    it 'ne modifie pas le statut' do

      expect { result }.not\_to change { entry.reload.status }

    end

  end

  describe 'concurrence — race condition' do

    it 'ne valide qu une seule fois en cas de double soumission' do

      threads \= 2.times.map do

        Thread.new { described\_class.call(entry: entry) }

      end

      results \= threads.map(&:value)

      expect(results.count(&:success?)).to eq(1)

      expect(results.count(&:failure?)).to eq(1)

    end

  end

end

### **8.4.4 ViewComponents — Tests atomiques**

\# spec/components/accounting/balance\_indicator\_component\_spec.rb

RSpec.describe Accounting::BalanceIndicatorComponent, type: :component do

  context 'quand équilibré' do

    let(:entry) { build(:journal\_entry, :balanced) }

    it 'affiche le badge vert Équilibré' do

      render\_inline(described\_class.new(entry: entry))

      expect(page).to have\_css('.bg-emerald-100', text: 'Équilibré')

    end

  end

  context 'quand déséquilibré' do

    let(:entry) { build(:journal\_entry, :unbalanced, gap: 150.00) }

    it 'affiche le badge rouge avec le montant du déséquilibre' do

      render\_inline(described\_class.new(entry: entry))

      expect(page).to have\_css('.bg-red-100', text: 'Déséquilibré')

      expect(page).to have\_text('150,00')

    end

  end

end

### **8.4.5 API Controllers — JWT Tests**

RSpec.describe 'Api::V1::JournalEntries', type: :request do

  include\_context 'with\_authenticated\_api'

  describe 'POST /api/v1/journal\_entries' do

    it\_behaves\_like 'a JWT-protected endpoint' do

      subject { post '/api/v1/journal\_entries', headers: {} }

    end

    context 'avec token valide' do

      let(:params) { { project\_id: 42, amount: 1000,

                       date: Date.today, account\_code: '604000',

                       description: 'Mission terrain' } }

      it 'crée une écriture comptable' do

        expect {

          post '/api/v1/journal\_entries',

               params: params, headers: auth\_headers

        }.to change(Accounting::JournalEntry, :count).by(1)

      end

      it 'retourne 201 avec la référence' do

        post '/api/v1/journal\_entries',

             params: params, headers: auth\_headers

        expect(response).to have\_http\_status(:created)

        expect(JSON.parse(response.body)\['reference'\]).to match(/ACH\\d{4}\\/\\d{4}/)

      end

    end

  end

end

### **8.4.6 Tests Système — Workflows complets**

RSpec.describe 'Workflow : Création et validation d une écriture',

               type: :system do

  include\_context 'with\_open\_fiscal\_year'

  include\_context 'with\_pcmn\_accounts'

  before { driven\_by :selenium\_chrome\_headless }

  let(:accountant) { create(:user, :accountant) }

  it 'permet à un comptable de créer et valider une écriture équilibrée' do

    sign\_in accountant

    visit new\_accounting\_journal\_entry\_path

    select 'ACH — Achats', from: 'Journal'

    fill\_in 'Date',        with: Date.today.strftime('%d/%m/%Y')

    fill\_in 'Description', with: 'Achat fournitures bureau'

    within '\[data-controller="journal-entry-form"\]' do

      \# Ligne 1 : débit charges

      within '.entry-lines', match: :first do

        fill\_in 'Compte', with: '604000'

        find('\[data-account-search-target="suggestion"\]',

             text: 'Services divers').click

        fill\_in 'Débit',  with: '1210.00'

      end

      click\_button 'Ajouter une ligne'

      \# Ligne 2 : crédit fournisseur

      within '.entry-lines:last-child' do

        fill\_in 'Compte', with: '440000'

        find('\[data-account-search-target="suggestion"\]',

             text: 'Fournisseurs').click

        fill\_in 'Crédit', with: '1210.00'

      end

    end

    \# Vérifier indicateur Stimulus : vert, équilibré

    expect(page).to have\_css('.balance-indicator .bg-emerald-100',

                             text: 'Équilibré')

    expect(page).not\_to have\_button('Valider', disabled: true)

    click\_button 'Valider'

    expect(page).to have\_content('Écriture ACH')

    expect(page).to have\_css('.bg-emerald-100', text: 'Validé')

    expect(page).not\_to have\_button('Modifier')

    expect(page).to have\_button('Contre-passer')

  end

  it 'empêche la validation si déséquilibrée' do

    \# ... débit 1000, pas de crédit

    expect(page).to have\_css('.balance-indicator .bg-red-100')

    expect(page).to have\_button('Valider', disabled: true)

  end

  it 'interdit la modification après validation (auditor)' do

    sign\_in create(:user, :auditor)

    visit accounting\_journal\_entry\_path(create(:journal\_entry, :posted))

    expect(page).not\_to have\_button('Valider')

    expect(page).not\_to have\_button('Contre-passer')

    expect(page).not\_to have\_link('Modifier')

  end

end

# **9\. Stimulus — Contrôleurs JavaScript**

## **9.1 journal-entry-form — Contrôleur principal**

Responsabilités : gestion dynamique des lignes, calcul balance en temps réel, validation côté client avant soumission.

// app/javascript/controllers/journal\_entry\_form\_controller.js

import { Controller } from '@hotwired/stimulus'

export default class extends Controller {

  static targets \= \['lines', 'debitTotal', 'creditTotal',

                    'balanceIndicator', 'submitButton', 'template'\]

  static values  \= { balanced: Boolean }

  connect() { this.recalculate() }

  addLine(event) {

    event.preventDefault()

    const template \= this.templateTarget.innerHTML

      .replace(/INDEX/g, Date.now())

    this.linesTarget.insertAdjacentHTML('beforeend', template)

  }

  removeLine(event) {

    event.target.closest('.entry-line').remove()

    this.recalculate()

  }

  recalculate() {

    const debits  \= this.\#sumColumn('debit')

    const credits \= this.\#sumColumn('credit')

    const balanced \= Math.abs(debits \- credits) \<= 0.01

    this.debitTotalTarget.textContent  \= this.\#format(debits)

    this.creditTotalTarget.textContent \= this.\#format(credits)

    this.balancedValue \= balanced

    this.\#updateIndicator(balanced, Math.abs(debits \- credits))

    this.submitButtonTarget.disabled \= \!balanced

  }

  \#sumColumn(type) {

    return Array.from(this.element.querySelectorAll(\`\[data-${type}\]\`))

      .reduce((sum, el) \=\> sum \+ (parseFloat(el.value) || 0), 0\)

  }

  \#format(amount) {

    return new Intl.NumberFormat('fr-BE', {

      style: 'currency', currency: 'EUR'

    }).format(amount)

  }

  \#updateIndicator(balanced, gap) {

    const el \= this.balanceIndicatorTarget

    el.className \= balanced

      ? 'balance-indicator bg-emerald-100 text-emerald-700 ...'

      : 'balance-indicator bg-red-100 text-red-700 ...'

    el.textContent \= balanced ? 'Équilibré'

                              : \`Déséquilibré : ${this.\#format(gap)}\`

  }

}

## **9.2 account-search — Autocomplete PCMN**

// Turbo Frame \+ Stimulus pour autocomplete des comptes PCMN

// Frappe 3 caractères → GET /accounting/accounts/search?q=604

// → Turbo Frame retourne la liste filtrée

// → Stimulus gère la sélection et remplit le champ

## **9.3 money-input — Formatage des montants**

// Formate automatiquement les inputs montant

// Accepte : '1000', '1000.50', '1 000,50'

// Stocke : BigDecimal compatible (pas de Float)

// Affiche : '1 000,50' (fr-BE locale)

# **10\. Séquence d'implémentation — TDD phase par phase**

| ▶ | *Règle TDD absolue : pour chaque item de cette liste, écrire le test en premier (Red), puis le code (Green), puis refactorer (Refactor). Ne jamais avancer à l'item suivant sans que les tests de l'item courant soient au vert.* |
| :---- | :---- |

| Phase | Contenu TDD | Durée | Critère de sortie |
| :---- | :---- | :---- | :---- |
| 0 — Bootstrap | Gemfile, DB config, RSpec config, shared contexts/examples, FactoryBot base, Tailwind config tokens, layouts devise/application | 2-3j | rails new OK, rspec \--dry-run passe, tokens Tailwind définis |
| 1 — Atoms UI | Tests BadgeComponent, ButtonComponent, InputComponent, etc. → Implémentation ViewComponents atomiques | 2-3j | Tous les composants Atoms testés et documentés |
| 2 — Fondations DB | Tests Account \+ FiscalYear \+ Journal models → Migrations \+ seeds PCMN (782 comptes) | 3-4j | 782 comptes PCMN chargés, tests models verts |
| 3 — Authentification | Tests Devise (sign in/out, lockout, timeout, roles) → Landing page \+ pages Devise customisées | 2-3j | Tous les flows auth testés, landing page visuelle |
| 4 — Concerns | Tests Auditable, Immutable, MonetaryPrecision, Statusable → Implémentation concerns | 2-3j | Shared examples immuabilité passent sur tous les modèles |
| 5 — Écritures | Tests JournalEntry \+ Lines \+ trigger DB → PostJournalEntry organizer \+ toutes Actions | 5-7j | Trigger DB actif, organizer passe tous les cas dont race condition |
| 6 — Molecules UI | Tests MoneyDisplayComponent, StatusBadgeComponent, etc. → Implémentation \+ Presenters | 3-4j | Composants molecules testés avec Presenters |
| 7 — Partenaires | Tests Partner \+ validation TVA belge → CRUD partenaires | 2-3j | Validation n° TVA format BE0123456789 |
| 8 — Facturation | Tests Invoice \+ Lines \+ PostInvoice organizer → Formulaire \+ PDF Ferrum | 5-6j | Facture créée → écriture VTE équilibrée → PDF généré |
| 9 — Organisms UI | Tests JournalEntryFormComponent, Stimulus journal-entry-form → Interface saisie complète | 4-5j | Tests système saisie écriture passent (Capybara) |
| 10 — TVA | Tests VatDeclaration \+ VatGridQuery → Calcul grilles \+ rapport | 3-4j | Grilles 01-88 correctes sur données test réelles |
| 11 — Trésorerie | Tests BankTransaction \+ ReconcileBankTransaction → Import CAMT.053 \+ UI lettrage | 4-5j | Import relevé → lettrage manuel → écriture BNQ |
| 12 — API JWT | Tests Api::JwtService \+ endpoints \+ shared example JWT → Contrôleurs API v1 | 3-4j | Tous endpoints protégés, intégration BudgetFlow mockée (VCR) |
| 13 — Peppol | Tests UblInvoiceBuilder (schema validation) \+ SendInvoice \+ webhooks → Digiteal sandbox | 4-5j | Facture envoyée \+ reçue en sandbox Peppol |
| 14 — Rapports | Tests TrialBalanceQuery, GeneralLedgerQuery, AnalyticProjectQuery → Pages rapports \+ exports | 3-4j | Bilan équilibré, rapport analytique projet |
| 15 — Clôture | Tests CloseFiscalYear organizer → UI clôture \+ dépôt BNB | 4-5j | Clôture exercice test sans erreur, bilan final équilibré |
| 16 — Hardening | Coverage \>= 95% SimpleCov, performance specs, sécurité Rack::Attack, CI/CD | 3-4j | CI vert, coverage atteint, aucune N+1 query |

# **11\. Gemfile complet**

\# Gemfile — LedgerFlow

source 'https://rubygems.org'

ruby '3.3.0'

gem 'rails', '\~\> 8.0'

gem 'pg', '\~\> 1.5'

gem 'puma', '\>= 5.0'

gem 'propshaft'              \# Asset pipeline Rails 8

gem 'solid\_queue'            \# Jobs (inclus Rails 8\)

gem 'solid\_cable'            \# WebSockets (inclus Rails 8\)

\# UI Framework

gem 'tailwindcss-rails'      \# Tailwind CSS

gem 'view\_component'         \# ViewComponent

gem 'hotwire-rails'          \# Turbo \+ Stimulus

\# Auth & Autorisations

gem 'devise'                 \# Authentification

gem 'pundit'                 \# Autorisations par rôle

gem 'jwt'                    \# Tokens JWT API

\# Logique métier

gem 'light-service'          \# Organizers \+ Actions

gem 'aasm'                   \# Machine à états (Statusable concern)

\# Audit & Traçabilité

gem 'paper\_trail'            \# Versioning des modèles

\# PDF

gem 'ferrum'                 \# Chrome headless pour PDF

gem 'prawn'                  \# PDF simples (reçus, etc.)

\# XML / Peppol UBL

gem 'nokogiri'               \# Génération XML UBL

\# Export

gem 'caxlsx'                 \# Génération .xlsx

gem 'caxlsx\_rails'

gem 'csv'                    \# Export CSV

\# Import bancaire

gem 'sepa\_king'              \# Parsing CAMT.053 ISO 20022

\# HTTP Client (Digiteal API \+ BudgetFlow)

gem 'faraday'

gem 'faraday-retry'

gem 'httparty'               \# Client BudgetFlow

\# Notifications

gem 'noticed'                \# Notifications in-app

\# Sécurité

gem 'rack-attack'            \# Rate limiting

gem 'bcrypt'                 \# Chiffrement (Devise)

group :development, :test do

  gem 'rspec-rails'

  gem 'factory\_bot\_rails'

  gem 'faker'

  gem 'database\_cleaner-active\_record'

  gem 'shoulda-matchers'

  gem 'simplecov'

  gem 'brakeman'             \# Audit sécurité

  gem 'rubocop-rails-omakase'

end

group :test do

  gem 'capybara'

  gem 'selenium-webdriver'

  gem 'webmock'              \# Mocking API externes

  gem 'vcr'                  \# Enregistrement réponses API

  gem 'view\_component\_storybook' \# Documentation composants

end

group :development do

  gem 'web-console'

  gem 'bullet'               \# Détection N+1 queries

  gem 'rack-mini-profiler'   \# Profiling performance

end

# **12\. Checklist de livraison**

| À vérifier intégralement avant de considérer l'implémentation comme terminée |
| :---: |

## **12.1 Architecture & Code**

* Structure de répertoires conforme §4.1

* Toutes les couches séparées : Models / Services / Queries / Presenters / Components / Controllers

* Aucune logique métier dans les contrôleurs

* Aucune logique de présentation dans les modèles

* DRY : aucune duplication de code détectée (rubocop \+ review manuelle)

* Tous les concerns implémentés : Auditable, Immutable, MonetaryPrecision, Statusable

## **12.2 TDD & Tests**

* Coverage SimpleCov \>= 95%

* Zéro test écrit après le code de production

* Shared contexts et shared examples utilisés systématiquement

* Tests ViewComponent pour tous les composants (atoms \+ molecules \+ organisms)

* Tests API JWT avec shared example 'a JWT-protected endpoint'

* Tests de concurrence pour PostJournalEntry

* Tests système Capybara pour les 5 workflows critiques

* Tests de performance pour balance, grand livre, TVA

## **12.3 UI & Design**

* Palette de couleurs LedgerFlow conforme §2.1 (indigo \+ émeraude)

* Cohérence visuelle avec BudgetFlow vérifiée

* Landing page publique responsive avec CTA

* Pages Devise customisées (Tailwind, layout split-screen)

* Tous les composants Atoms documentés (Storybook ou équivalent)

* Montants comptables en font-mono, alignés à droite

* Couleurs sémantiques : rouge pour négatif, émeraude pour positif

## **12.4 Intégration & API**

* JWT généré et validé correctement dans les deux sens

* Endpoint POST /api/v1/journal\_entries fonctionnel et testé

* Endpoint GET /api/v1/projects/:id/accounting\_summary fonctionnel

* Client BudgetFlow avec retry et gestion d'erreurs

* Webhook Peppol avec vérification HMAC

* Tests API mockés avec WebMock \+ VCR

## **12.5 Conformité légale**

* 782 comptes PCMN chargés (version ASBL/Fondation AR 2019\)

* Trigger PostgreSQL partie double actif et testé

* Immuabilité des écritures validées vérifiée (tests \+ DB)

* Grilles TVA 01-88 correctes

* Audit trail immuable (REVOKE UPDATE/DELETE sur audit\_logs)

* Conservation 7 ans : archivage sécurisé configuré

* UBL XML valide contre schéma Peppol BIS 3.0

## **12.6 Sécurité**

* Brakeman scan : zéro vulnérabilité critique

* Rack::Attack configuré (rate limiting login \+ API)

* CSP headers configurés

* Credentials Rails (master.key) — aucun secret dans le code

* Devise lockout (5 tentatives) fonctionnel

* Session timeout 8h fonctionnel

*— Fin du document — LedgerFlow v2.0*  
CaC Management BV  •  Confidentiel  •  Usage interne uniquement