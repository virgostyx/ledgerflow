# LedgerFlow UI Migration Plan — BudgetFlow Look & Feel

**Status**: In progress  
**Created**: 2026-05-16  
**Theme**: Orange (primary) replacing Indigo  

---

## Decisions validées

| Sujet | Décision |
|---|---|
| Layout navigation | Sidebar conservée (pas de top navbar) |
| Font | Inter var (Google Fonts) |
| Couleur primaire | Orange (`#ea580c` / `orange-600`) |
| Widgets flottants | Music Player, Calculatrice, Convertisseur de devises, Confirm Modal global |
| Floating labels | gem `floating_labels_rails` (Devise) + Stimulus controller (autres forms) |
| Music player | Thème violet conservé (indépendant du thème app) |

---

## Architecture du thème

Tailwind alias `primary: colors.orange` dans `tailwind.config.js`.  
Tous les composants utilisent `bg-primary-*`, `text-primary-*`, `ring-primary-*`.  
Changer de thème = changer une ligne dans le config.

---

## Ordre des phases

```
Phase 1  → CSS Foundation (design tokens, Inter font, TW plugins, CSS custom)
Phase 2  → Layout shell (sidebar, header, main restylés)
Phase 2B → Floating Labels (gem + controller + migration forms)
Phase 3  → FlashMessageComponent
Phase 4  → Composants UI de base (Button, Card, Badge, Modal, Empty State, Tooltip, etc.)
Phase 5  → Widgets flottants (MusicPlayer, Calculator, CurrencyConverter, BackToTop, Loading)
Phase 6  → Stimulus controllers
Phase 7  → Stats/KPI components
Phase 8  → Mise à jour des vues
Phase 9  → Specs
```

---

## Phase 1 — CSS Foundation

### 1.1 — Inter var font
**Fichiers modifiés** : `app/views/layouts/application.html.erb`, `devise.html.erb`, `landing.html.erb`
- Ajouter `<link>` Google Fonts pour Inter (weights 100–900, variable)
- Appliquer `font-family: 'Inter var'` via CSS global

### 1.2 — Design Tokens
**Fichier créé** : `app/assets/stylesheets/config/design_tokens.css`

```css
/* ============================================
   LEDGERFLOW DESIGN TOKENS
   ============================================ */

:root {
  /* Primary (Orange) */
  --lf-primary-50:  #fff7ed;
  --lf-primary-100: #ffedd5;
  --lf-primary-200: #fed7aa;
  --lf-primary-300: #fdba74;
  --lf-primary-400: #fb923c;
  --lf-primary-500: #f97316;
  --lf-primary-600: #ea580c;   /* boutons, liens actifs */
  --lf-primary-700: #c2410c;   /* logo, titres, hover */
  --lf-primary-800: #9a3412;
  --lf-primary-900: #7c2d12;

  /* Gray (Neutral) */
  --lf-gray-50:  #f9fafb;
  --lf-gray-100: #f3f4f6;
  --lf-gray-200: #e5e7eb;
  --lf-gray-300: #d1d5db;
  --lf-gray-400: #9ca3af;
  --lf-gray-500: #6b7280;
  --lf-gray-600: #4b5563;
  --lf-gray-700: #374151;
  --lf-gray-800: #1f2937;
  --lf-gray-900: #111827;

  /* Success (Emerald) */
  --lf-success-50:  #f0fdf4;
  --lf-success-100: #dcfce7;
  --lf-success-500: #22c55e;
  --lf-success-600: #16a34a;
  --lf-success-700: #15803d;

  /* Warning (Amber) */
  --lf-warning-50:  #fffbeb;
  --lf-warning-100: #fef3c7;
  --lf-warning-500: #f59e0b;
  --lf-warning-600: #d97706;
  --lf-warning-700: #b45309;

  /* Danger (Red) */
  --lf-danger-50:  #fef2f2;
  --lf-danger-100: #fee2e2;
  --lf-danger-500: #ef4444;
  --lf-danger-600: #dc2626;
  --lf-danger-700: #b91c1c;

  /* Info (Blue) */
  --lf-info-50:  #eff6ff;
  --lf-info-100: #dbeafe;
  --lf-info-500: #3b82f6;
  --lf-info-600: #2563eb;
  --lf-info-700: #1d4ed8;

  /* Spacing */
  --lf-spacing-xs:  0.25rem;
  --lf-spacing-sm:  0.5rem;
  --lf-spacing-md:  1rem;
  --lf-spacing-lg:  1.5rem;
  --lf-spacing-xl:  2rem;
  --lf-spacing-2xl: 3rem;
  --lf-spacing-3xl: 4rem;

  /* Typography */
  --text-xs:   0.75rem;
  --text-sm:   0.875rem;
  --text-base: 1rem;
  --text-lg:   1.125rem;
  --text-xl:   1.25rem;
  --text-2xl:  1.5rem;
  --text-3xl:  1.875rem;
  --text-4xl:  2.25rem;

  --font-weight-normal:   400;
  --font-weight-medium:   500;
  --font-weight-semibold: 600;
  --font-weight-bold:     700;
  --line-height-tight:    1.25;
  --line-height-normal:   1.5;
  --line-height-relaxed:  1.75;

  /* Borders */
  --border-radius-sm:   0.25rem;
  --border-radius-md:   0.375rem;
  --border-radius-lg:   0.5rem;
  --border-radius-xl:   0.75rem;
  --border-radius-2xl:  1rem;
  --border-radius-full: 9999px;
  --border-width-thin:   1px;
  --border-width-medium: 2px;
  --border-width-thick:  4px;

  /* Shadows */
  --shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
  --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
  --shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
  --shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.1);

  /* Z-index */
  --z-index-dropdown:       1000;
  --z-index-sticky:         1020;
  --z-index-fixed:          1030;
  --z-index-modal-backdrop: 1040;
  --z-index-modal:          1050;
  --z-index-popover:        1060;
  --z-index-tooltip:        1070;

  /* Transitions */
  --transition-fast:   150ms;
  --transition-base:   300ms;
  --transition-slow:   500ms;
  --transition-timing: cubic-bezier(0.4, 0, 0.2, 1);
}
```

### 1.3 — Tailwind config
**Fichier modifié** : `config/tailwind.config.js`

```js
const colors = require('tailwindcss/colors')

module.exports = {
  theme: {
    extend: {
      colors: {
        primary: colors.orange,
        success: colors.emerald,
        warning: colors.amber,
        danger:  colors.red,
        info:    colors.blue,
      },
      fontFamily: {
        sans: ['Inter var', 'ui-sans-serif', 'system-ui', 'sans-serif'],
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'Monaco', 'Consolas', 'monospace'],
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/aspect-ratio'),
    require('@tailwindcss/container-queries'),
  ],
}
```

### 1.4 — CSS custom files
**Fichiers créés** :
- `app/assets/stylesheets/components/floating_labels.css` — animation label flottant, placeholder mgmt, focus ring, scrollbar, selection colors
- `app/assets/stylesheets/print.css` — hide nav/buttons, BW colors, page breaks
- `app/assets/stylesheets/application.css` — manifest important les nouveaux fichiers

**`app/assets/stylesheets/application.css`** ajouts :
```css
/* Music Player animations */
@keyframes vinyl-spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
.music-vinyl-spin { animation: vinyl-spin 4s linear infinite; }

@keyframes eq-bounce { 0%, 100% { height: 4px; } 50% { height: 14px; } }
.music-eq-bar { display: inline-block; height: 4px; animation: eq-bounce 0.8s ease-in-out infinite; }

.music-volume-slider::-webkit-slider-runnable-track { height: 4px; background: rgba(255,255,255,0.2); border-radius: 9999px; }
.music-volume-slider::-webkit-slider-thumb { -webkit-appearance: none; width: 12px; height: 12px; border-radius: 50%; background: #a78bfa; margin-top: -4px; cursor: pointer; }
.music-volume-slider::-moz-range-track { height: 4px; background: rgba(255,255,255,0.2); border-radius: 9999px; }
.music-volume-slider::-moz-range-thumb { width: 12px; height: 12px; border: none; border-radius: 50%; background: #a78bfa; cursor: pointer; }
```

---

## Phase 2 — Layout shell (Sidebar + Shell)

### 2.1 — Sidebar restylée
**Fichier modifié** : `app/views/layouts/application.html.erb`

- Logo : `◈ LedgerFlow` avec `text-primary-700 font-semibold`
- Nav items default : `text-gray-600 hover:bg-primary-50 hover:text-primary-700 rounded-md px-3 py-2`
- Nav items active : `bg-primary-100 text-primary-700 font-medium border-l-2 border-primary-600`
- Icônes SVG Heroicons (stroke-based, w-5 h-5)
- Section user en bas : avatar `w-8 h-8 bg-primary-600 rounded-full` + nom + "Sign out"

### 2.2 — Header bar
- `bg-white border-b border-gray-200 px-6 py-3`
- Gauche : `Ui::BreadcrumbsComponent`
- Droite : boutons d'action contextuels

### 2.3 — Main content
- `flex-1 p-6 bg-gray-50`
- Flash messages via FlashMessageComponent (Phase 3)
- Back-to-top button fixe bas-droite
- Loading overlay fixe z-9999

### 2.4 — Layout Devise (auth)
- Sidebar marketing `bg-primary-700` (côté droit, `hidden lg:flex`)
- Formulaire centré `max-w-md` avec card blanche `shadow-sm`

---

## Phase 2B — Floating Labels

### 2B.1 — Gem
`Gemfile` : `gem "floating_labels_rails", ">= 0.1.1"`

### 2B.2 — Stimulus controller
`app/javascript/controllers/floating_label_controller.js`
- `connect()` → checkValue (gère les records existants en édition)
- `focus()` → label monte (classe `floating-active`)
- `blur()` → label descend si champ vide
- `checkValue()` → label reste monté si valeur présente

### 2B.3 — CSS
`app/assets/stylesheets/components/floating_labels.css`
- `.floating` : `transform: translateY(-1.25rem) scale(0.75)` + `color: primary-600`
- Placeholders : opacity 0 par défaut, 0.6 au focus
- Focus ring : `ring-2 ring-primary-500 border-transparent`
- Erreur : `input.border-red-500 + label { color: danger-600 }`

### 2B.4 — Pattern HTML formulaires métier
```html
<div class="relative" data-controller="floating-label">
  <%= f.text_field :field,
        placeholder: " ",
        class: "block w-full px-3 pt-6 pb-2 text-gray-900 bg-white
                border border-gray-300 rounded-lg appearance-none
                focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent
                peer",
        data: {
          floating_label_target: "input",
          action: "focus->floating-label#focus blur->floating-label#blur input->floating-label#checkValue"
        } %>
  <label data-floating-label-target="label"
         class="absolute text-gray-500 duration-300 transform
                -translate-y-3 scale-75 top-4 left-3 z-10 origin-[0]
                peer-placeholder-shown:scale-100 peer-placeholder-shown:translate-y-0
                peer-focus:scale-75 peer-focus:-translate-y-3 peer-focus:text-primary-600 floating">
    Field Label
  </label>
</div>
```

### 2B.5 — Formulaires Devise
`builder: FloatingLabelsRails::FormBuilder` dans :
- `users/sessions/new.html.erb`
- `users/registrations/new.html.erb`
- `users/passwords/new.html.erb`

### 2B.6 — Formulaires métier à migrer
- `accounting/partners/_form.html.erb` — restyle complet + floating labels
- `accounting/fiscal_years/_form.html.erb`
- `accounting/invoices/_form.html.erb`
- `accounting/vat_declarations/new.html.erb`
- `Layouts::JournalEntryFormComponent` — champs d'en-tête (Journal, Date, Description) uniquement

### 2B.7 — Ui::InputComponent
Ajouter option `floating: true` pour générer le wrapper Stimulus automatiquement.

---

## Phase 3 — FlashMessageComponent

### 3.1 — Composant Ruby
`app/components/flash_message_component.rb`
- Props : `type` (:notice/:success/:alert/:warning/:error/:info), `message`, `duration` (5000ms)

### 3.2 — Template
`app/components/flash_message_component.html.erb`
- Icône animée dans carré coloré
- Progress bar en bas
- Animations : `opacity-0 translate-y-[-1rem]` → `opacity-100 translate-y-0`

### 3.3 — Stimulus controller
`app/javascript/controllers/flash_controller.js`
- Auto-close après `duration` ms
- Hover to pause
- Progress bar décroissante

### 3.4 — Intégration layout
Remplacer les `<% if notice %>` dans les layouts par `render FlashMessageComponent`.

---

## Phase 4 — Composants UI de base

### 4.1 — Ui::ButtonComponent (mise à jour)
- Ajouter variant `ghost`
- Ajouter `loading: true` (spinner + opacity-50)
- Ajouter `icon:` (SVG inline)
- Sizes : xs, sm, md, lg, xl
- Focus : `ring-primary-500`

### 4.2 — Ui::CardComponent (mise à jour)
- `renders_one :header` → `border-b border-gray-200 px-6 py-4`
- `renders_one :footer` → `border-t border-gray-200 px-6 py-4 bg-gray-50 rounded-b-lg`
- Option `shadow: true/false`

### 4.3 — Ui::BadgeComponent (mise à jour)
- Ajouter variantes `info` et `gray`
- Sizes : sm, md, lg
- Couleurs alignées sur tokens LedgerFlow

### 4.4 — Ui::ModalComponent (mise à jour)
- `align: :center | :top`
- Backdrop click → close
- Esc key → close
- `renders_one :footer`

### 4.5 — Ui::EmptyStateComponent (nouveau)
- Container : `text-center py-12 bg-gray-50 rounded-lg border-2 border-dashed border-gray-300`
- Icon : `h-12 w-12 text-gray-400 mx-auto`
- Slot `actions`

### 4.6 — Ui::TooltipComponent (nouveau)
- Props : `text`, `position` (:top, :bottom, :left, :right)
- Wrapper `group relative`
- Transition `duration-200`

### 4.7 — Ui::PageHeaderComponent (nouveau)
- Props : `title`, `description`, `back_path`, `back_text`
- Title : `text-3xl font-bold text-gray-900`
- Slot `actions`

### 4.8 — Ui::BreadcrumbsComponent (nouveau)
- Props : `items` (array of `{label:, path:}`)
- Separator : SVG chevron

### 4.9 — Ui::FilterPanelComponent (nouveau)
- Collapsible (Stimulus toggle)
- Ouvert par défaut si `active_count > 0`
- Slot `fields`

### 4.10 — Ui::ConfirmModalComponent (nouveau)
- Modal global dans le layout
- Déclenché par data attributes

---

## Phase 5 — Widgets flottants

### Position empilée (bas-droite)
```
bottom-6  right-6  → Back To Top button
bottom-20 right-6  → Calculator
bottom-36 right-6  → Currency Converter
bottom-56 right-6  → Music Player FAB
```

### 5.0 — Ui::MusicPlayerComponent (nouveau)
- Porté tel quel depuis BudgetFlow (Ruby + ERB + JS controller)
- Thème violet/indigo foncé conservé (délibérément distinct du thème orange)
- `data-turbo-permanent` : audio continu pendant navigation Turbo
- 5 stations SomaFM : Groove Salad, Secret Agent, Space Station, Lush, Drone Zone
- localStorage : station + volume persistés

### 5.1 — Ui::CalculatorComponent (nouveau)
- Grid 4×5 touches
- `calculator_controller.js`

### 5.2 — Ui::CurrencyConverterComponent (nouveau)
- EUR, USD, GBP, CHF, JPY
- `currency_converter_controller.js`

### 5.3 — Ui::BackToTopComponent (nouveau)
- Visible après scroll
- `back_to_top_controller.js`

### 5.4 — Loading overlay
- Div fixe global `z-[9999]`
- `loading_overlay_controller.js`

---

## Phase 6 — Stimulus Controllers (nouveaux)

| Controller | Fichier | Rôle |
|---|---|---|
| `modal_controller.js` | controllers/ | Open/close via `hidden` |
| `modal_trigger_controller.js` | controllers/ | Déclenche modal par ID |
| `dropdown_controller.js` | controllers/ | Toggle dropdowns |
| `tooltip_controller.js` | controllers/ | Show/hide tooltips |
| `flash_controller.js` | controllers/ | Auto-dismiss + progress bar |
| `loading_overlay_controller.js` | controllers/ | Overlay global Turbo |
| `back_to_top_controller.js` | controllers/ | Scroll + visibility |
| `confirm_modal_controller.js` | controllers/ | Confirm modal global |
| `calculator_controller.js` | controllers/ | Logique calculatrice |
| `currency_converter_controller.js` | controllers/ | Conversion temps réel |
| `floating_label_controller.js` | controllers/ | Floating label forms |

---

## Phase 7 — Stats/KPI Components

### Stats::KpiCardComponent (restructuration)
- Props : `title`, `value`, `icon`, `color`, `trend`, `subtitle`
- Structure :
  - Gauche : title, value (`text-3xl font-bold`), subtitle, trend
  - Droite : icon dans carré coloré `bg-{color}-50`
- Colors : orange, green, red, blue, amber, gray
- Container : `bg-white rounded-lg shadow-sm border border-gray-200 p-6 hover:shadow-md`

---

## Phase 8 — Mise à jour des vues

- Remplacer les H1 inline par `Ui::PageHeaderComponent`
- Ajouter `Ui::BreadcrumbsComponent` aux pages principales
- Ajouter `Ui::EmptyStateComponent` sur les index vides
- Remplacer `data: { confirm: }` par confirm modal global
- Ajouter tooltips sur boutons icon-only
- Wrapper les filtres dans `Ui::FilterPanelComponent`

---

## Phase 9 — Specs (TDD)

### Component specs à créer
`spec/components/ui/` :
- `empty_state_component_spec.rb`
- `tooltip_component_spec.rb`
- `page_header_component_spec.rb`
- `breadcrumbs_component_spec.rb`
- `filter_panel_component_spec.rb`
- `confirm_modal_component_spec.rb`
- `flash_message_component_spec.rb`
- `calculator_component_spec.rb`
- `currency_converter_component_spec.rb`
- `music_player_component_spec.rb`

`spec/components/stats/` :
- `kpi_card_component_spec.rb`

### Component specs à mettre à jour
- `button_component_spec.rb` (nouvelles variants/sizes/states)
- `card_component_spec.rb` (header/footer slots)
- `badge_component_spec.rb` (info/gray variants)
- `modal_component_spec.rb` (align, backdrop, Esc)
- `input_component_spec.rb` (option floating:)

### Couverture
Maintenir ≥ 95% SimpleCov.

---

## Design System — Palette de couleurs LedgerFlow

### Primary — Orange
| Token | Hex | Usage |
|---|---|---|
| `primary-50` | `#fff7ed` | Hover backgrounds |
| `primary-100` | `#ffedd5` | Badge backgrounds |
| `primary-600` | `#ea580c` | **Boutons, nav active, liens** |
| `primary-700` | `#c2410c` | **Logo, titres, hover** |

### Couleurs sémantiques comptables
| Concept | Classe | Convention |
|---|---|---|
| Montant crédit | `text-success-600` | Argent entrant |
| Montant débit | `text-danger-600` | Argent sortant |
| Montant zéro | `text-gray-400` | Valeur vide |
| Code compte PCMN | `text-primary-700 font-mono` | `411000` |
| Écriture équilibrée | `text-success-600` | ✓ Balanced |
| Écriture déséquilibrée | `text-danger-600` | ✗ +12,50 € |

### Récapitulatif des fichiers

| Type | Nouveaux | Modifiés |
|---|---|---|
| CSS | 3 (`design_tokens.css`, `floating_labels.css`, `print.css`) | 1 (`application.css`) |
| TW Config | 0 | 1 (`tailwind.config.js`) |
| Layouts | 0 | 3 (`application.html.erb`, `devise.html.erb`, `landing.html.erb`) |
| ViewComponents | 11 (EmptyState, Tooltip, PageHeader, Breadcrumbs, FilterPanel, ConfirmModal, Flash, Calculator, CurrencyConverter, BackToTop, MusicPlayer) | 4 (Button, Card, Badge, Modal) |
| Stimulus controllers | 11 | 0 |
| Vues | 0 | ~15 |
| Specs | ~15 | ~5 |
