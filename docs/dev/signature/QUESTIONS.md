# Questions ouvertes — Fonctions signature (B01 à B03)

Décisions prises par prudence pendant l'implémentation (règle du §14.1 de `docs/dev/signature/spec.md`), à faire valider. Les décisions de fond sont dans `00-audit.md` §6.

## Décisions prises le 2026-10-09
- **Renumérotation (validée)** : invariants de la signature I14 (temps), I15 (lots de paiement), I16 (un seul lot actif), I17 (ancrage), car I12 et I13 existent déjà dans `spec/invariants/`; contrôles R19 C20 (reconstruction historique) et C21 (ancrage compromis), car C18 existe déjà. `spec.md` est mis à jour.
- **Permissions et drapeaux de §2.2 ajoutés avec chaque capacité, pas avant** : `spec/policies/permissions_spec.rb` exige une action de policy testée pour chaque permission de la matrice, et `CustomRole::ASSIGNABLE` expose toute la matrice. Une permission sans policy serait donc un test impossible et un choix trompeur dans l'écran des rôles. Même raison pour les clés de `Entity::FEATURES` (`b01a`…) : chacune arrive avec sa capacité, comme le prévoit le commentaire de `FEATURES`.

## Étape 0
- **Second facteur récent** : `ApplicationController#require_recent_second_factor!(within: 5.minutes)`, horodatage `session[:second_factor_at]`. Fenêtre par défaut de 5 minutes : à confirmer (la spec dit seulement « récent »).
- **Personne avec passkey seulement** : renvoyée vers l'inscription TOTP, car il n'existe pas d'écran de ré-authentification par passkey. À construire avec le premier écran qui l'exige (export B01b ou seuil B01a). À décider : accepter cette limite d'ici là, ou construire l'écran plus tôt.
- **`audit_logs.actor_type`** : valeurs `user` (défaut) et `portal_user`. Il n'entre dans l'empreinte que s'il vaut autre chose que `user`, pour que les lignes existantes gardent leur hash. Un `actor_id` pour les personnes du portail viendra avec B02a (`user_id` ne peut pas les désigner).
