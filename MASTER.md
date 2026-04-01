# MASTER.md — nixdash Website Design System

> Source of truth. Every color, font, spacing, shadow, animation token comes from here.
> No magic numbers. No rogue hex values. No freelancing.

---

## Visual Thesis

Dark interface chaleureuse inspirée de Charm.sh — fond sombre profond (#13111c) sans froideur, violet nixdash (#8B5CF6) comme accent principal. Typographie à 4 niveaux : **Audiowide** pour le hero (impact digital futuriste), **Dela Gothic One** pour les headers (bold, tranchée, massive), **Outfit** pour le body (géométrique soft, lisible), **JetBrains Mono** pour le code et éléments terminal. Composants aux bords légèrement arrondis avec surfaces subtiles (cards avec bordures fines translucides). Personnalité via éléments terminal stylisés et ASCII art. Ambiance dev tool propre avec chaleur humaine.

## Interaction Thesis

Animations moyennes-rapides (150-300ms), easings smooth ease-out. Hover avec légère élévation et glow violet subtil. Scroll-triggered reveals avec fade-in + léger translateY et stagger sur les listes. Hero avec stagger entry séquentiel. Pas de parallax, pas de bounce, pas d'elastic, pas de scroll hijacking — tout reste fluide et discret, le contenu prime sur le spectacle.

---

## Color Palette

### Backgrounds (dark navy scale)

| Token | Hex | Usage |
|---|---|---|
| `--bg-deepest` | `#0d0b14` | Page background, base layer |
| `--bg-base` | `#13111c` | Default surface (nixdash brand bg) |
| `--bg-surface` | `#1c1929` | Cards, elevated surfaces |
| `--bg-elevated` | `#252236` | Hover states on surfaces, active elements |
| `--bg-input` | `#161320` | Input fields, code blocks |

### Text

| Token | Hex | Usage |
|---|---|---|
| `--text-primary` | `#f0eef5` | Headings, primary content |
| `--text-secondary` | `#a8a3b8` | Body text, descriptions |
| `--text-muted` | `#6b6580` | Captions, hints, disabled |
| `--text-inverse` | `#0d0b14` | Text on accent backgrounds |

### Accent (violet — nixdash brand)

| Token | Hex | Usage |
|---|---|---|
| `--accent` | `#8B5CF6` | Primary accent, CTAs, links, active states |
| `--accent-hover` | `#A78BFA` | Hover state for accent elements |
| `--accent-muted` | `rgba(139, 92, 246, 0.15)` | Accent backgrounds, badges, subtle highlights |
| `--accent-strong` | `#7C3AED` | Pressed/active state |
| `--accent-glow` | `rgba(139, 92, 246, 0.25)` | Glow effects on focus/hover |

### Secondary accent (warm)

| Token | Hex | Usage |
|---|---|---|
| `--warm` | `#E8B4B8` | Subtle warm touches, secondary highlights |
| `--warm-muted` | `rgba(232, 180, 184, 0.1)` | Soft warm backgrounds |

### Semantic

| Token | Hex | Usage |
|---|---|---|
| `--success` | `#4ade80` | Success states, installed packages |
| `--error` | `#ef4444` | Error states, removal |
| `--warning` | `#fbbf24` | Warning states |
| `--info` | `#60a5fa` | Info states |

### Borders & Dividers

| Token | Value | Usage |
|---|---|---|
| `--border-subtle` | `rgba(168, 163, 184, 0.08)` | Card borders, dividers |
| `--border-medium` | `rgba(168, 163, 184, 0.15)` | Input borders, hover borders |
| `--border-strong` | `rgba(168, 163, 184, 0.25)` | Focus rings, active borders |
| `--border-accent` | `#8B5CF6` | Accent borders, selected states |

---

## Typography

### Font Stack

| Role | Font | Weight(s) | Fallback | Usage |
|---|---|---|---|---|
| **Hero** | Audiowide | 400 | cursive, sans-serif | Hero headline only — digital, futuriste |
| **Display** | Dela Gothic One | 400 | sans-serif | Headers, section titles — bold, tranchée |
| **Body** | Outfit | 300, 400, 500, 600 | sans-serif | Body text, UI elements — soft, lisible |
| **Mono** | JetBrains Mono | 400, 500, 700 | monospace | Code blocks, terminal elements, commands |

**Why Audiowide:** Racing/tech feel, arrondie mais digitale. Utilisée uniquement pour le hero — elle crée un impact immédiat sans saturer.

**Why Dela Gothic One:** Massive, japonaise/brutale, formes tranchées. Parfaite pour les titres de sections — identitaire et mémorable.

**Why Outfit:** Géométrique mais soft, excellent en body. Assez neutre pour laisser briller Audiowide et Dela Gothic, mais avec plus de personnalité qu'Inter.

**Why JetBrains Mono:** Standard dev, lisible, ligatures. Cohérent avec l'univers terminal de nixdash.

### Type Scale

| Token | Size | Line Height | Weight | Font | Usage |
|---|---|---|---|---|---|
| `--text-hero` | `clamp(3rem, 8vw, 5.5rem)` | 1.0 | 400 | Audiowide | Hero headline only |
| `--text-h1` | `clamp(2rem, 4vw, 3rem)` | 1.1 | 400 | Dela Gothic One | Page titles |
| `--text-h2` | `clamp(1.5rem, 3vw, 2.25rem)` | 1.15 | 400 | Dela Gothic One | Section headers |
| `--text-h3` | `1.25rem` | 1.3 | 400 | Dela Gothic One | Subsection headers |
| `--text-body` | `1rem` (16px) | 1.6 | 400 | Outfit | Body text |
| `--text-body-lg` | `1.125rem` (18px) | 1.6 | 400 | Outfit | Lead paragraphs, hero subtitle |
| `--text-small` | `0.875rem` (14px) | 1.5 | 400 | Outfit | Captions, metadata |
| `--text-xs` | `0.75rem` (12px) | 1.4 | 500 | Outfit | Badges, labels |
| `--text-code` | `0.875rem` | 1.7 | 400 | JetBrains Mono | Inline code, code blocks |

### Typography Rules

- **Audiowide** exclusivement pour le hero — jamais ailleurs.
- **Dela Gothic One** n'a qu'un seul weight (400) mais c'est déjà bold par nature.
- **Letter-spacing:** +0.03em sur Audiowide hero, +0.01em sur Dela Gothic headers, normal sur Outfit.
- **Max line length:** 70ch pour le body text.
- **No underlines on links.** Couleur + hover shift.
- **Uppercase** autorisé sur les badges et petits labels (Outfit 500).

---

## Spacing

Base unit: **4px**

| Token | Value | Usage |
|---|---|---|
| `--space-1` | 4px | Micro gaps (icon-text) |
| `--space-2` | 8px | Tight gaps (badge padding, inline spacing) |
| `--space-3` | 12px | Small gaps (card inner padding) |
| `--space-4` | 16px | Default gap (between elements) |
| `--space-6` | 24px | Medium gap (card padding, group spacing) |
| `--space-8` | 32px | Large gap (section inner padding) |
| `--space-12` | 48px | Section gaps |
| `--space-16` | 64px | Major section separators |
| `--space-24` | 96px | Page section padding (vertical) |
| `--space-32` | 128px | Hero padding |

### Spacing Rules

- Sections: `96px` vertical padding minimum (mobile: `64px`).
- Cards: `24px` padding.
- Max content width: `1200px` (max-w-6xl equivalent).
- Generous whitespace — Charm.sh spirit: let elements breathe.

---

## Border Radius

| Token | Value | Usage |
|---|---|---|
| `--radius-none` | 0px | N/A |
| `--radius-sm` | 6px | Buttons, inputs, badges |
| `--radius-md` | 8px | Cards, code blocks |
| `--radius-lg` | 12px | Terminal windows, large containers |
| `--radius-xl` | 16px | Feature cards, hero elements |
| `--radius-full` | 9999px | Pills, status dots, avatars |

### Radius Rules

- **Default: `radius-md` (8px).** Clean developer tool — slightly rounded, jamais sharp brutalist.
- Interactive elements (buttons, inputs): `radius-sm` (6px).
- Cards et containers: `radius-md` à `radius-lg`.
- Le look est "soft" sans être "bubbly" — jamais > 16px sauf pills.

---

## Shadows

Depth through subtle shadows and border glow, not heavy elevation.

| Token | Value | Usage |
|---|---|---|
| `--shadow-none` | none | Default |
| `--shadow-sm` | `0 1px 3px rgba(0, 0, 0, 0.3)` | Subtle lift on cards |
| `--shadow-md` | `0 4px 12px rgba(0, 0, 0, 0.4)` | Elevated elements, dropdowns |
| `--shadow-glow` | `0 0 20px rgba(139, 92, 246, 0.2)` | Violet glow on focus/active |
| `--shadow-glow-strong` | `0 0 40px rgba(139, 92, 246, 0.3)` | Hero elements, featured cards |

### Shadow Rules

- Ombre subtile, jamais lourde.
- Glow violet pour les éléments focus/featured — signature visuelle.
- NO harsh drop shadows.
- NO elevation system complexe — 2 niveaux max (sm, md).

---

## Components

### Button

```
Primary:
  bg: --accent (#8B5CF6)
  text: --text-inverse (#0d0b14)
  border: none
  radius: --radius-sm (6px)
  padding: 12px 24px
  font: Outfit 500, 15px
  hover: bg --accent-hover (#A78BFA), shadow --shadow-glow
  active: bg --accent-strong (#7C3AED), scale(0.98)
  transition: 200ms ease-out

Secondary:
  bg: transparent
  text: --text-primary (#f0eef5)
  border: 1px solid --border-medium
  radius: --radius-sm (6px)
  padding: 12px 24px
  font: Outfit 500, 15px
  hover: bg --bg-elevated, border --border-strong
  active: bg --bg-surface
  transition: 200ms ease-out

Ghost:
  bg: transparent
  text: --accent (#8B5CF6)
  border: none
  padding: 12px 24px
  hover: bg --accent-muted
  transition: 150ms ease-out
```

### Card

```
bg: --bg-surface (#1c1929)
border: 1px solid --border-subtle
radius: --radius-md (8px)
padding: --space-6 (24px)
hover: border-color --border-medium, shadow --shadow-sm, translateY(-2px)
transition: 200ms ease-out
```

### Terminal Window

```
bg: --bg-input (#161320)
border: 1px solid --border-medium
radius: --radius-lg (12px)
padding: 0
header:
  bg: --bg-elevated (#252236)
  padding: 12px 16px
  border-bottom: 1px solid --border-subtle
  dots: #ef4444, #fbbf24, #4ade80 (8px circles)
  title: JetBrains Mono 400, 13px, --text-muted
body:
  padding: 20px 24px
  font: JetBrains Mono 400, 14px
  line-height: 1.7
```

### Input

```
bg: --bg-input (#161320)
text: --text-primary
border: 1px solid --border-medium
radius: --radius-sm (6px)
padding: 10px 16px
font: Outfit 400, 16px
placeholder: --text-muted
focus: border-color --accent, shadow --shadow-glow
transition: 200ms ease-out
```

### Badge / Tag

```
bg: --accent-muted
text: --accent (#8B5CF6)
border: none
radius: --radius-full (9999px)
padding: 4px 12px
font: Outfit 500, 12px, uppercase, tracking +0.05em
```

### Code Block

```
bg: --bg-input (#161320)
text: --text-primary
border: 1px solid --border-subtle
radius: --radius-md (8px)
padding: 20px 24px
font: JetBrains Mono 400, 14px
line-height: 1.7
copy-button: top-right, Ghost style
```

### Inline Code

```
bg: --accent-muted
text: --accent (#8B5CF6)
radius: --radius-sm (6px)
padding: 2px 8px
font: JetBrains Mono 500, 0.875em
```

### Kbd (keyboard shortcut)

```
bg: --bg-elevated (#252236)
text: --text-primary
border: 1px solid --border-medium
border-bottom: 2px solid --border-medium
radius: --radius-sm (6px)
padding: 2px 8px
font: JetBrains Mono 500, 0.8em
```

### Link

```
text: --accent (#8B5CF6)
decoration: none
hover: color --accent-hover (#A78BFA), no underline
transition: 150ms ease-out
```

### Navigation

```
bg: --bg-base/80 + backdrop-blur(12px)
border-bottom: 1px solid --border-subtle
padding: 16px 0
position: sticky top-0
z-index: 50
logo: nixdash in Audiowide or ASCII logo
links: Outfit 500, 14px, --text-secondary
links hover: --text-primary
active link: --accent
```

---

## Motion Tokens

### Duration

| Token | Value | Usage |
|---|---|---|
| `--duration-instant` | 0ms | Reduced motion fallback |
| `--duration-fast` | 100ms | Hover color shifts, focus rings |
| `--duration-normal` | 200ms | Button interactions, card hovers |
| `--duration-medium` | 300ms | Content reveals, menu transitions |
| `--duration-slow` | 500ms | Hero entry, major reveals |

### Easing

| Token | Value | Usage |
|---|---|---|
| `--ease-out` | `cubic-bezier(0.16, 1, 0.3, 1)` | Primary — smooth deceleration |
| `--ease-in-out` | `cubic-bezier(0.4, 0, 0.2, 1)` | Symmetric transitions |
| `--ease-in` | `cubic-bezier(0.4, 0, 1, 1)` | Elements exiting only |

### Stagger

| Token | Value | Usage |
|---|---|---|
| `--stagger-fast` | 50ms | List items, grid cards |
| `--stagger-normal` | 80ms | Feature cards, nav items |
| `--stagger-slow` | 120ms | Hero elements, major sections |

### Scroll Reveal

```
trigger: IntersectionObserver, threshold 0.15
initial: opacity 0, translateY 24px
animate: opacity 1, translateY 0
duration: --duration-medium (300ms)
easing: --ease-out
stagger: --stagger-fast (50ms) for lists
```

### Hero Entry (stagger séquentiel)

```
Order: logo ASCII → badge version → title (Audiowide) → subtitle → install command → CTA buttons
Per-element: opacity 0 → 1, translateY 30px → 0
Duration: 500ms per element
Stagger: 120ms between elements
Easing: --ease-out
Total sequence: ~1.2s
```

### Forbidden Patterns

- `bounce`, `elastic`, `spring` easings
- Duration > 500ms on UI interactions
- Smooth scroll / scroll hijacking / inertia
- Parallax scrolling
- Floating/bobbing loops
- Scale > 1.05 on hover
- Gradient animations
- Lens/blur effects animés
- Auto-playing carousels

---

## Page Structure

### Landing Page

1. **Navbar** — Logo + nav links + GitHub star button
2. **Hero** — ASCII logo + Audiowide title + tagline + install command + CTA
3. **Terminal Demo** — Terminal window animé montrant nixdash en action
4. **Features** — Grid de feature cards (search, install, shell, flakes, shortcuts, config)
5. **Installation** — Commands par plateforme (Nix flake, nix profile)
6. **Shortcuts** — Table des raccourcis clavier
7. **CTA** — Call-to-action final vers docs/GitHub
8. **Footer** — Links, license, credits

### Documentation

- Sidebar navigation
- Pages: Overview, Installation, Commands, Configuration, Shortcuts, FAQ
- Clean reading experience, max-width 70ch sur le contenu

---

## Accessibility Requirements (Non-Negotiable)

### prefers-reduced-motion

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

### Contrast Ratios

- `--text-primary` (#f0eef5) on `--bg-deepest` (#0d0b14) = ~16:1 (AAA)
- `--text-secondary` (#a8a3b8) on `--bg-deepest` (#0d0b14) = ~6.5:1 (AA)
- `--text-muted` (#6b6580) on `--bg-deepest` (#0d0b14) = ~3.5:1 (large text only)
- `--accent` (#8B5CF6) on `--bg-deepest` (#0d0b14) = ~5.2:1 (AA)

### Focus States

All interactive elements: `outline: 2px solid --accent; outline-offset: 2px;`

### Other

- Semantic HTML (no clickable divs without `role="button"`)
- `aria-hidden="true"` on decorative elements
- `alt` text on all meaningful images
- Tab order matches visual order
- Min touch target: 44x44px

---

## Responsive Breakpoints

| Name | Width | Adjustments |
|---|---|---|
| Mobile | < 640px | Stack layouts, reduce section padding to 64px, hero text clamp min |
| Tablet | 640-1023px | 2-col grids, adjust card layouts |
| Desktop | 1024-1439px | Full layout |
| Large | 1440px+ | Max-width container, center content |

---

## Anti-Patterns (NEVER DO)

- Gradient fills on backgrounds or text
- Heavy box-shadow elevation systems
- Rounded corners > 16px (except pills)
- Neon glow effects excessifs
- Floating/hovering decorative elements
- Parallax scrolling
- Smooth scroll libraries
- Generic "SaaS landing page" layout (Stripe clones)
- Emoji as icons — use Lucide React
- Multiple accent colors (violet only, warm as subtle secondary)
- Light mode (dark-only)
- Bounce/elastic animations
- Auto-playing anything
