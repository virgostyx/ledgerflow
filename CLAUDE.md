# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bin/setup             # Install deps, prepare DB, start dev server
bin/setup --skip-server  # Install deps and prepare DB only
bin/dev               # Start development server
bin/ci                # Run full CI suite (rubocop, audits, tests, seeds)

bundle exec rspec                              # Run all tests
bundle exec rspec spec/models/foo_spec.rb      # Run a single spec file
bundle exec rspec spec/models/foo_spec.rb:42   # Run a single spec by line number
bundle exec rspec --tag focus                  # Run focused specs only

bin/rails db:prepare  # Create and migrate DB
bin/rails db:seed:replant  # Reset and reseed (test-safe)

bin/rubocop           # Lint Ruby (rubocop-rails-omakase style)
bin/brakeman --quiet --no-pager  # Security static analysis
bin/bundler-audit     # Audit gems for CVEs
bin/importmap audit   # Audit JS dependencies
```

## Local development — PostgreSQL via Docker

```bash
docker compose up -d   # Start PostgreSQL container (port 5432)
docker compose down    # Stop container
```

Credentials Docker (development/test) :
- host: localhost, port: 5432
- username: ledgerflow, password: password

## Architecture

**Stack**: Rails 8.1 / Ruby 3.3.5 / PostgreSQL / Hotwire (Turbo + Stimulus) / Tailwind CSS via Propshaft + ImportMap / ViewComponent.

**Solid stack** (all DB-backed, no Redis required):
- `solid_queue` — background jobs, runs inside Puma via `SOLID_QUEUE_IN_PUMA=true`
- `solid_cache` — Rails cache store
- `solid_cable` — Action Cable adapter

**Production databases**: The app uses four separate PostgreSQL databases in production — primary (`ledgerflow_production`), cache, queue, and cable — each with its own migrations path under `db/`.

**Deployment**: Kamal (Docker-based). Config in `config/deploy.yml`; secrets in `.kamal/secrets`. Build target is `amd64`. Registry defaults to `localhost:5555`.

**Testing**: RSpec with FactoryBot, DatabaseCleaner, Shoulda::Matchers, SimpleCov (≥ 95% coverage required). TDD strict — test before code, always. Spec structure: `spec/models/`, `spec/services/`, `spec/queries/`, `spec/presenters/`, `spec/components/`, `spec/requests/`, `spec/system/`.

**Linting**: RuboCop inherits from `rubocop-rails-omakase` (omakase style). Overrides go in `.rubocop.yml`.

## Spec reference

Full technical and functional specification: `docs/dev/LedgerFlow_ConceptNote_v2.md`

## Rapports comptables — règles de travail

- La source de vérité est `docs/dev/reports/spec.md`. En cas de doute, la relire ; ne pas deviner.
- TDD strict : test rouge, code minimal, test vert, refactoring. Un commit par étape cohérente.
- Un rapport à la fois. Ne pas commencer le suivant tant que la définition de « terminé » (§15) n'est pas remplie.
- Montants : `numeric(15,2)` en base, `BigDecimal` en Ruby, jamais `Float`.
- Toute agrégation en SQL. Aucun total calculé par une boucle Ruby sur des lignes d'écriture.
- Toutes les migrations sont réversibles. Aucune donnée existante n'est modifiée ou supprimée sans accord.
- Ne jamais modifier BudgetFlow sans accord explicite.
- Si une règle comptable ou fiscale manque ou paraît douteuse, appliquer le comportement le plus prudent, l'inscrire dans `docs/dev/reports/QUESTIONS.md` avec sa justification, et continuer.
- Chaque rapport respecte les règles transverses du §2 et le gabarit du §1 de la spec.
- Ne jamais supprimer ou affaiblir un test pour le faire passer.
