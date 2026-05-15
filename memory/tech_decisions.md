---
name: tech-decisions
description: Décisions techniques clés : RSpec au lieu de Minitest, PostgreSQL via Docker en local
metadata:
  type: feedback
---

Utiliser RSpec pour tous les tests (pas Minitest, malgré le défaut Rails).

**Why:** La spec LedgerFlow_ConceptNote_v2.md prescrit RSpec + FactoryBot. Confirmation explicite de l'utilisateur.

**How to apply:** Toujours écrire les tests en RSpec. Le dossier `spec/` est la référence, `test/` peut être ignoré/supprimé. Mettre à jour CLAUDE.md avec les commandes RSpec.

---

Utiliser PostgreSQL via Docker en développement et test (pas SQLite).

**Why:** La spec requiert un trigger PostgreSQL `enforce_double_entry` pour l'intégrité comptable en partie double. Ce trigger est incompatible avec SQLite. Confirmation explicite de l'utilisateur.

**How to apply:** Toujours supposer PostgreSQL comme base de données, y compris en local. Un docker-compose.yml est présent à la racine pour démarrer le container PG.
