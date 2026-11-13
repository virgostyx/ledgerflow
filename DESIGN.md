---
name: LedgerFlow
description: Belgian accounting workspace; a calm, dense, flat light UI where orange marks the way and every figure can be traced.
colors:
  primary: "#ea580c"
  primary-deep: "#c2410c"
  primary-tint: "#ffedd5"
  primary-wash: "#fff7ed"
  primary-border: "#fdba74"
  canvas: "#f9fafb"
  surface: "#ffffff"
  surface-alt: "#f3f4f6"
  line: "#e5e7eb"
  line-strong: "#d1d5db"
  ink: "#111827"
  ink-soft: "#374151"
  ink-muted: "#6b7280"
  ink-faint: "#9ca3af"
  positive: "#047857"
  positive-tint: "#d1fae5"
  caution: "#b45309"
  caution-tint: "#fef3c7"
  negative: "#b91c1c"
  negative-tint: "#fee2e2"
  info: "#1d4ed8"
  info-tint: "#dbeafe"
typography:
  headline:
    fontFamily: "Inter var, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 700
    lineHeight: "2rem"
  title:
    fontFamily: "Inter var, ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 600
    lineHeight: "1.75rem"
  body:
    fontFamily: "Inter var, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: "1.25rem"
  label:
    fontFamily: "Inter var, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 500
    letterSpacing: "0.05em"
  figure:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
    fontSize: "0.875rem"
    fontWeight: 400
    fontFeature: "tabular-nums"
rounded:
  sm: "2px"
  md: "6px"
  lg: "8px"
  xl: "12px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.surface}"
    rounded: "{rounded.lg}"
    padding: "8px 16px"
  button-primary-hover:
    backgroundColor: "{colors.primary-deep}"
  button-secondary:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink-soft}"
    rounded: "{rounded.lg}"
    padding: "8px 16px"
  button-ghost:
    backgroundColor: "transparent"
    textColor: "{colors.primary}"
    rounded: "{rounded.lg}"
    padding: "8px 16px"
  button-danger:
    backgroundColor: "#dc2626"
    textColor: "{colors.surface}"
    rounded: "{rounded.lg}"
    padding: "8px 16px"
  card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.xl}"
    padding: "24px"
  input:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "12px"
  badge:
    backgroundColor: "{colors.surface-alt}"
    textColor: "{colors.ink-soft}"
    rounded: "{rounded.full}"
    padding: "2px 10px"
  nav-item-active:
    backgroundColor: "{colors.primary-tint}"
    textColor: "{colors.primary-deep}"
    rounded: "{rounded.md}"
    padding: "8px 12px"
---

# Design System: LedgerFlow

## Overview

**Creative North Star: "The Audit Trail"**

LedgerFlow looks like a set of books that can be checked. Every screen is built so that a figure can be read, compared and traced back: tabular numerals, right-aligned amounts, an unambiguous sign, and a surface quiet enough that nothing competes with the numbers. It is a working tool for long sessions, so it favours density and consistency over expression. Brand shows up in precise details, not in decoration.

The surface is light and flat: a pale grey canvas, white cards separated by hairline borders, a single warm accent. Colour carries meaning (action, state, sign of an amount) and is never ornamental. It belongs to the same family as BudgetFlow: Inter, Tailwind, light UI.

**Key Characteristics:**
- Dense but scannable; `text-sm` is the working size.
- Flat by default; structure comes from borders, not shadows.
- One accent (orange); semantic colours only for status and sign.
- Amounts are always monospace, tabular and right-aligned.
- Everything user-visible is in English.

## Colors

A neutral grey scale does the structural work; orange marks the primary action and the current location; four semantic hues report status.

### Primary
- **Ledger Orange** (#ea580c): primary buttons, links on dense tables, focus ring, active navigation accent. Defined as the `primary-*` scale in `app/assets/tailwind/application.css`.
- **Deep Orange** (#c2410c): hover and pressed state, active nav text, section titles inside cards.
- **Orange Tint** (#ffedd5) and **Orange Wash** (#fff7ed): active nav background, informational callouts, ghost-button hover.

### Neutral
- **Pale Canvas** (#f9fafb): page background, table headers, footers.
- **Paper White** (#ffffff): cards, sidebar, inputs' surroundings.
- **Hairline** (#e5e7eb) and **Firm Line** (#d1d5db): card borders, row dividers, input borders.
- **Ink** (#111827), **Soft Ink** (#374151), **Muted Ink** (#6b7280), **Faint Ink** (#9ca3af): page titles, body, secondary text and captions, section labels.

### Semantic
- **Ledger Green** (#047857 on #d1fae5): validated, balanced, positive.
- **Draft Amber** (#b45309 on #fef3c7): drafts, approaching due dates, warnings.
- **Alert Red** (#b91c1c on #fee2e2): errors, negative balances, destructive actions.
- **Reference Blue** (#1d4ed8 on #dbeafe): neutral information badges.

### Named Rules
**The Single Accent Rule.** Orange is for the next action and the current place. It is never used for decoration, and never to signal a status; status has its own semantic hues.

**The Sign Rule.** Colour never carries a sign alone. A negative amount is red *and* shows its minus sign.

## Typography

**Display / Body Font:** Inter (variable, with system sans fallback)
**Figure Font:** system monospace stack, with `tabular-nums`

**Character:** one sans family at modest sizes, with monospace reserved for numbers so columns line up.

### Hierarchy
- **Headline** (700, 1.5rem, 2rem): page title in `PageHeader`.
- **Title** (600, 1.125rem, 1.75rem): card titles, in Deep Orange.
- **Body** (400, 0.875rem, 1.25rem): tables, data, most text.
- **Form text** (400, 1rem): longer-form entry where the density can relax.
- **Label** (500, 0.75rem, uppercase, 0.05em tracking): table column headers and nav section headings.
- **Figure** (mono, 0.875rem, tabular): every amount, right-aligned.

### Named Rules
**The Aligned Figures Rule.** Amounts are monospace, tabular and right-aligned. No exception, including KPI cards and totals.

## Layout

A two-column shell: a fixed 16rem white sidebar (bordered on the right) and a scrolling content area on the pale canvas. Below `md` the sidebar becomes a drawer over a dimmed backdrop, opened from the header. Spacing follows Tailwind's 4px base: 16 to 24px inside cards, 24px under page headers, 2px gaps between nav items. Tables are full width with a sticky header and 16px horizontal cell padding. Density stays high; whitespace is used to separate groups, not to fill the screen.

## Elevation & Depth

Flat by default. Depth is conveyed by hairline borders and the grey-to-white step between canvas and card. A single soft shadow (`shadow-sm`) sits under cards; KPI cards lift to `shadow-md` on hover. Larger shadows (`shadow-lg` to `shadow-2xl`) are reserved for modals, drawers and floating panels.

### Named Rules
**The Border-First Rule.** Separate with a border before reaching for a shadow.

## Shapes

Gently rounded and consistent: 6px (`rounded-md`) for nav items and compact controls, 8px (`rounded-lg`) for buttons, inputs and alerts, 12px (`rounded-xl`) for cards, and full pills for badges. Only a few outliers use `rounded-sm` or `rounded-2xl`. Borders are 1px; the strongest rule is the 2px top border on table totals.

## Components

### Buttons
- **Shape:** 8px radius, `font-medium`, `text-sm` at the default size (px-4 py-2).
- **Primary:** Ledger Orange fill with white text, Deep Orange on hover.
- **Secondary:** white fill, Soft Ink text, Firm Line border.
- **Ghost:** transparent, orange text, orange-300 border, Orange Wash on hover.
- **Danger:** red-600 fill, red-700 on hover.
- **Focus / Disabled:** 2px orange focus ring; disabled at 50% opacity with a not-allowed cursor. A loading state shows a spinner and disables the button.

### Cards / Containers
- **Corner Style:** 12px. **Background:** white. **Border:** 1px Hairline. **Shadow:** `shadow-sm` unless flat.
- **Internal Padding:** 24px; optional header and footer separated by borders, the footer on Pale Canvas.

### Inputs / Fields
- **Style:** 1px Firm Line border, 8px radius, transparent fill, with a floating label (`lf-floating-label`).
- **Focus:** 2px orange ring. **Error:** red border and a red 12px message below. Required fields show a red asterisk.

### Badges
Pill-shaped (`rounded-full`), `text-xs` medium weight, tint background with the strong text of the same hue: default, success, warning, danger, primary, info.

### Navigation
Sidebar of icon + label rows (20px outline icons, 1.5 stroke), `text-sm` medium. Active row: Orange Tint background with Deep Orange text. Sections are collapsible (`details`), headed by a Faint Ink uppercase label, and the open state is remembered.

### Data tables (signature)
Sticky Pale Canvas header with uppercase 12px labels, `divide-y` hairline rows, links in Deep Orange, numeric cells monospace and right-aligned, and a totals row with a 2px top border and semibold text.

### KPI cards
White card with a medium-weight caption, a 3xl bold value, a muted subtitle and an optional trend, plus a tinted icon square on the right.

## Do's and Don'ts

### Do:
- **Do** right-align amounts and set them in monospace with tabular numerals.
- **Do** use the `primary-*` scale (orange) for the primary action, active navigation and links.
- **Do** separate surfaces with a 1px Hairline border before adding a shadow.
- **Do** write all user-visible text in English.
- **Do** keep a visible 2px orange focus ring and meet WCAG AA contrast.
- **Do** build with the existing `Ui::` ViewComponents rather than ad hoc markup.

### Don't:
- **Don't** use indigo or violet; the brand colour replaced them (migration still in progress).
- **Don't** signal status with orange, or a sign with colour alone.
- **Don't** add decorative gradients, glows or heavy shadows to working screens.
- **Don't** use `Float` representations or unformatted numbers in the UI; amounts are always formatted decimals.
- **Don't** introduce a second accent colour or a different font family.
