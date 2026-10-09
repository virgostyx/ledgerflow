# Questions ouvertes — Fonctions signature (B01 à B03)

Décisions prises par prudence pendant l'implémentation (règle du §14.1 de `docs/dev/signature/spec.md`), à faire valider. Les décisions de fond sont dans `00-audit.md` §6.

## Décisions prises le 2026-10-09
- **Renumérotation (validée)** : invariants de la signature I14 (temps), I15 (lots de paiement), I16 (un seul lot actif), I17 (ancrage), car I12 et I13 existent déjà dans `spec/invariants/`; contrôles R19 C20 (reconstruction historique) et C21 (ancrage compromis), car C18 existe déjà. `spec.md` est mis à jour.
- **Permissions et drapeaux de §2.2 ajoutés avec chaque capacité, pas avant** : `spec/policies/permissions_spec.rb` exige une action de policy testée pour chaque permission de la matrice, et `CustomRole::ASSIGNABLE` expose toute la matrice. Une permission sans policy serait donc un test impossible et un choix trompeur dans l'écran des rôles. Même raison pour les clés de `Entity::FEATURES` (`b01a`…) : chacune arrive avec sa capacité, comme le prévoit le commentaire de `FEATURES`.

## Étape 0
- **Second facteur récent** : `ApplicationController#require_recent_second_factor!(within: 5.minutes)`, horodatage `session[:second_factor_at]`. Fenêtre par défaut de 5 minutes : à confirmer (la spec dit seulement « récent »).
- **Personne avec passkey seulement** : renvoyée vers l'inscription TOTP, car il n'existe pas d'écran de ré-authentification par passkey. À construire avec le premier écran qui l'exige (export B01b ou seuil B01a). À décider : accepter cette limite d'ici là, ou construire l'écran plus tôt.
- **`audit_logs.actor_type`** : valeurs `user` (défaut) et `portal_user`. Il n'entre dans l'empreinte que s'il vaut autre chose que `user`, pour que les lignes existantes gardent leur hash. Un `actor_id` pour les personnes du portail viendra avec B02a (`user_id` ne peut pas les désigner).

## B01a — Circuit d'approbation
- **Le sujet est la facture (`Accounting::Invoice` fournisseur, facture ou note de crédit), pas l'écriture d'achat.** La spec parle d'« écriture d'achat », mais le module de paiement, les montants, l'échéance et le fournisseur vivent sur la facture. `payment_status` est donc sur `accounting_invoices` (défaut `not_required` : l'existant ne change pas). Une écriture d'achat saisie à la main sans facture n'entre pas dans un lot de paiement aujourd'hui, donc pas dans le circuit. À valider.
- **Montant d'une politique** = somme SQL des lignes TTC, converti en EUR au taux de la facture (`Fx::Convert.to_eur`, convention F11 : unités de devise pour 1 EUR). Les totaux d'en-tête d'une facture ne sont calculés qu'à la validation, alors que la spec soumet dès le brouillon : on lit donc les lignes. Bornes min et max incluses.
- **« Premier paiement »** = aucune autre facture fournisseur du tiers au statut `paid`. Un fournisseur payé hors LedgerFlow avant l'activation déclenche donc « premier paiement » une fois si aucune de ses factures n'est marquée payée (comportement prudent, cf. audit §7.6).
- **L'empreinte de contenu** couvre fournisseur, type de document, devise et taux, échéance, lignes (compte, quantité, prix, taux de TVA, code de grille) et SHA-256 des pièces liées. Elle ignore les libellés, les notes, le numéro attribué à la validation et l'ordre des lignes. L'IBAN écrit sur la facture y entrera avec la colonne (audit §7.8).
- **Rôles d'un échelon** limités à ceux qui ont `approvals.approve` (propriétaire, comptable). Un assistant ne peut donc jamais être nommé approbateur par rôle.
- **Une demande `changes_requested` est fermée** : après modification, une nouvelle demande est ouverte (une seule demande `pending` par facture, garantie par un index unique partiel).

## B01a — Rappels, escalade, absence
- **Heures de rappel par politique** (`approval_policies.reminder_hours`, 24 et 48 par défaut), délai de service et personne d'escalade par échelon. Au plus un rappel par passage du job, même si plusieurs délais sont passés d'un coup (pas de rafale).
- **Escalade** : la personne désignée doit avoir `approvals.approve` ; sinon, ou si personne n'est désigné, ce sont les propriétaires. La personne appelée **s'ajoute** aux approbateurs de l'échelon (les autres peuvent toujours décider) ; la séparation des tâches s'applique à elle aussi.
- **Approbateur absent ou désactivé** : quand plus personne de nommé ne peut décider, la demande est reroutée vers les propriétaires avec une alerte (une fois par échelon). Les compteurs (rappels, escalade, reroutage) repartent à zéro à chaque changement d'échelon.
- **Notifications uniquement dans l'application pour l'instant** (écran des notifications, qui dépend du drapeau F08) : le SMTP n'est pas configuré en production, et la spec demande de toute façon des e-mails sans montants ni noms. Le lien ouvre la fiche de la facture, en attendant l'écran « À approuver ».
- **Job horaire** `Approvals::ProcessDueJob` (`config/recurring.yml`, production seulement, comme les autres).
- **Pas de gestion des jours fermés ni des heures calmes** : les délais sont en heures civiles. À décider si les rappels doivent éviter la nuit et le week-end.

## B01a — Écrans
- **« À approuver »** : liste des demandes dont je peux décider l'échelon courant, échéance de paiement la plus proche d'abord. Filtres : fournisseur, montant (de/à, EUR), projet. Le calcul de « qui peut décider » se fait demande par demande (`Approvals::Approvers`) : correct pour des centaines, **à mesurer contre le budget de 500 ms pour 500 éléments** (§13). Le compteur du menu fait le même calcul à chaque page : à mettre en cache si la mesure le demande.
- **Avertissements affichés** : montant inhabituel seulement (plus de deux fois la moyenne des cinq dernières factures validées du fournisseur, même devise, au moins trois factures). Les avertissements de doublon (F03), de changement d'IBAN (B01b) et d'état du budget (R11) se brancheront sur `Approvals::SupplierHistory#warnings` quand ils existeront pour les factures. L'état du budget n'est pas affiché : BudgetFlow ne se modifie pas sans accord.
- **Approbation groupée** : désactivée tant que la société n'a pas de seuil (`bulk_threshold`). Seules les demandes sous le seuil (TTC en EUR) et **sans avertissement** sont cochables ; chaque décision porte l'empreinte affichée et s'enregistre à part. Ce qui a changé entre-temps est laissé, avec un message.
- **Décision par le web** : canal `web`, empreinte d'appareil = 16 premiers caractères du SHA-256 de l'agent utilisateur (jamais l'agent lui-même). Le canal `mobile` arrive avec l'écran mobile.
- **Réglages** `bap_before_posting`, `allow_self_approval`, `bulk_threshold` : sur l'écran de la société, propriétaire seul, visibles quand le drapeau b01a est actif. Leur changement est journalisé par l'audit existant de l'entité (à vérifier avec le propriétaire des audits : `Entity` n'est pas `AuditTrailed` aujourd'hui — voir ci-dessous).
- **Pas encore d'écran** pour écrire les politiques, les échelons et les délégations (`approvals.configure`) : c'est le lot suivant, avant l'API.

## B01a — Politiques et délégations
- **Une politique sous laquelle des demandes existent n'est jamais modifiée sous leurs pieds** : si ses **échelons** changent, elle est retirée (`active: false`, ses échelons intacts, visible dans « Retired ») et une nouvelle version (`version + 1`) prend sa place pour les prochaines factures ; son nom, sa priorité, ses conditions, ses rappels et son interrupteur « active » se changent sur place. Sans demande, tout se modifie sur place. Une politique n'est jamais supprimée (les demandes y renvoient).
- **Conditions saisies en texte** : fournisseurs, comptes et projets par **identifiants** séparés par des virgules (pas de sélecteur de fournisseur dans ce lot). À remplacer par des sélecteurs avec recherche si l'usage le demande.
- **Ajouter un niveau** = enregistrer, puis rouvrir : le formulaire montre toujours deux lignes vides en plus. Pas de JavaScript pour l'instant (règle des index numériques de Stimulus si on en ajoute).
- **Délégations faites par le propriétaire seulement** (`approvals.configure`). La spec dit seulement qu'elles sont « visibles de tous les propriétaires ». À décider : un approbateur peut-il déclarer lui-même son absence ? Les deux personnes doivent pouvoir approuver dans la société au moment où la délégation est faite (contrôlé à la création uniquement : un délégataire rétrogradé ensuite est refusé au moment de décider).
- **Politiques et délégations sont dans le journal d'audit** champ par champ (`AuditTrailed`), plus une entrée « approval_policy_revised » pour une nouvelle version.

## B01a — API
- **Deux portées** `approvals:read` et `approvals:decide`, toutes deux rattachées au droit `approvals.approve` du propriétaire du jeton (comme les autres portées : retirer le droit coupe le jeton à l'appel suivant).
- **Visibilité** : une demande n'est trouvée que si elle attend le propriétaire du jeton ou s'il a décidé dessus ; sinon 404 (on ne dit rien d'une demande qui n'est pas la sienne).
- **Canal `api`** et empreinte d'appareil `token-<id>` dans les décisions. L'API ne donne pas la configuration (politiques, délégations) : l'écran du propriétaire reste le seul chemin.
- **Seuil de second facteur** (`step_up_threshold`, lot mobile) : un jeton ne peut pas fournir de second facteur. Proposition : au-delà du seuil, l'API répond 403 `step-up-required` et la décision se prend dans l'application. À valider quand le seuil existera.
- **Pas de transfert** à un autre approbateur dans l'API ni dans les écrans pour l'instant.
- **« Demander une modification »** : la tâche va à l'auteur de la facture s'il est encore membre de la société, sinon à la personne qui a soumis, sinon elle reste sans assigné (un propriétaire l'assigne). Avant ce correctif, l'action échouait si l'auteur n'était plus membre.
