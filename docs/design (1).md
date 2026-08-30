---
name: Wisp
colors:
  surface: '#141310'
  surface-dim: '#141310'
  surface-bright: '#3b3935'
  surface-container-lowest: '#0f0e0b'
  surface-container-low: '#1d1b18'
  surface-container: '#211f1c'
  surface-container-high: '#2b2a26'
  surface-container-highest: '#363531'
  on-surface: '#e6e2dc'
  on-surface-variant: '#bfc9c4'
  inverse-surface: '#e6e2dc'
  inverse-on-surface: '#32302c'
  outline: '#89938e'
  outline-variant: '#404945'
  surface-tint: '#98d2bf'
  primary: '#98d2bf'
  on-primary: '#00382c'
  primary-container: '#276152'
  on-primary-container: '#9fdac7'
  inverse-primary: '#2f6859'
  secondary: '#c2c8bc'
  on-secondary: '#2c3229'
  secondary-container: '#43493f'
  on-secondary-container: '#b1b7ab'
  tertiary: '#a4cfc8'
  on-tertiary: '#083732'
  tertiary-container: '#365f59'
  on-tertiary-container: '#abd7cf'
  error: '#E24B4A'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#b3efdb'
  primary-fixed-dim: '#98d2bf'
  on-primary-fixed: '#002019'
  on-primary-fixed-variant: '#125042'
  secondary-fixed: '#dfe4d8'
  secondary-fixed-dim: '#c2c8bc'
  on-secondary-fixed: '#171d15'
  on-secondary-fixed-variant: '#43493f'
  tertiary-fixed: '#bfebe4'
  tertiary-fixed-dim: '#a4cfc8'
  on-tertiary-fixed: '#00201d'
  on-tertiary-fixed-variant: '#244e48'
  background: '#141310'
  on-background: '#e6e2dc'
  surface-variant: '#363531'
  surface-raised: '#154B44'
  background-base: '#0D3A35'
typography:
  headline-lg:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '500'
    lineHeight: 32px
  headline-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '500'
    lineHeight: 28px
  title-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '500'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '400'
    lineHeight: 14px
    letterSpacing: 0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  margin-page: 1.25rem
  gutter-bubble: 0.5rem
  padding-bubble-x: 1rem
  padding-bubble-y: 0.75rem
  stack-compact: 0.25rem
  stack-default: 1rem
---

## Brand & Style

The design system embodies a **Minimalist** and **Dark-First** aesthetic, prioritizing tranquility and premium restraint over visual noise. The experience is designed to feel like a "whisper" in a world of loud notifications—calm, private, and exceptionally clear.

While the UX patterns are informed by established messaging conventions (WhatsApp), the visual layer is elevated through a sophisticated, deep-green palette and architectural clarity. The emotional response should be one of trustworthiness and focus, achieved through:
- **Generous Whitespace:** Ensuring the UI never feels cluttered despite being a utility-heavy application.
- **Intentional Restraint:** Limiting the color and weight variants to the absolute essentials to maintain a "quiet" interface.
- **Flat Depth:** Avoiding skeuomorphism in favor of tonal layering and hairline borders that define structure without adding weight.

## Colors

The palette is a focused exploration of greens and creams, optimized for eye comfort during long-form communication. 

- **Primary Dark Background:** The foundation is a deep bluish-green, providing more depth than a standard black or gray.
- **The Accent:** Moderate Green is used surgically for primary interactions, active states, and sent messages. It also doubles as the "success" semantic color.
- **Muted Elements:** Laurel Green is used for timestamps, inactive icons, and hairline dividers to ensure they are legible but recede into the background.
- **Text:** Light Cream is the primary ink for dark surfaces, offering a softer, more premium contrast than pure white.

**Surface Tiers:**
- **Level 0 (Base):** `#0D3A35` (Main background)
- **Level 1 (Raised):** `#154B44` (Cards, Received bubbles, search bars)

## Typography

Typography is functional and utilitarian, using **Inter** for its exceptional legibility in small-screen chat environments. 

**Core Principles:**
- **Sentence Case Only:** No all-caps buttons or headers. This maintains the "calm" tone and feels more human and conversational.
- **Weight Restriction:** Strictly use **Regular (400)** and **Medium (500)** weights. Avoid bold or extra-bold weights to preserve the premium, restrained aesthetic.
- **Hierarchy:** Use size and color (Cream vs. Laurel Green) rather than weight to establish hierarchy.

## Layout & Spacing

The layout follows a **fluid grid** model optimized for mobile-first messaging. 

- **Messaging Rhythm:** Use a 4px baseline grid. Message bubbles are grouped with 4px spacing between consecutive messages from the same sender, and 12px between different senders.
- **Page Margins:** A standard 20px (1.25rem) margin for screen edges ensures content doesn't feel cramped.
- **Input Areas:** Floating input bars should maintain a persistent 8px margin from the bottom of the safe area.
- **Alignment:** Navigation is standard bottom-bar for ease of reach. Search and settings are located in the top-tier for secondary access.

## Elevation & Depth

This design system avoids traditional drop shadows. Instead, depth is communicated through **Tonal Layers** and **Hairline Outlines**.

- **Tonal Layering:** Surfaces are differentiated by shifting the base background color (`#0D3A35`) to a slightly lighter tint (`#154B44`). This is used for cards, received message bubbles, and input fields.
- **Hairline Borders:** Use 1px (or 0.5pt) borders in Laurel Green at 15-20% opacity. These are used for dividers between chat list items and defining card boundaries.
- **Interactive States:** Instead of a shadow, a pressed state is indicated by a subtle opacity shift or a slight darkening of the surface color.

## Shapes

The shape language is friendly but structured. 

- **Message Bubbles:** A standard radius of 14px is applied. To indicate directionality, the corner pointing toward the sender's edge uses a "tail-style" reduced radius of 4px.
- **Avatars:** Strictly circular (50% radius). This contrasts with the softer rectangles of the message bubbles.
- **Buttons & Inputs:** Follow the `rounded-lg` (16px) standard for a cohesive "soft-rectangular" feel.
- **Icons:** Use **outline-style** exclusively. Icons should have a consistent 2px stroke weight to match the clean typography.

## Components

### Buttons
- **Primary:** Filled with Moderate Green (#276152), text in Cream (#FBF6F0).
- **Secondary:** Ghost/Outline style with a Laurel Green hairline border and Cream text. No background fill.
- **FAB:** Circular, Moderate Green background, white/cream outline icon.

### Message Bubbles
- **Sent:** Moderate Green background, Cream text, right-aligned.
- **Received:** Surface-Raised (#154B44) background, Cream text, left-aligned.
- **AI-Agent:** Distinctive hairline border in Moderate Green or a small "AI" label tag in the header of the bubble.

### Inputs
- **Chat Input:** Surface-Raised background, hairline border, rounded-pill shape. 
- **Icons within inputs:** Outline style, Laurel Green for inactive/placeholder, Moderate Green for active typing.

### Status & Indicators
- **Online Dot:** Small 8px solid circle in Moderate Green.
- **Unread Badge:** Moderate Green circle with Cream label-sm text.
- **Story Ring:** A 2px Laurel Green ring around avatars, turning Moderate Green when unviewed.

### Lists
- **Chat List:** Avatar on left, two lines of text (Title Medium for name, Body Medium for preview). Laurel Green 1px divider at 10% opacity between items.
---

## Status Note (added by Claude, not part of Stitch export)
This file is the project's official `design.md` — source of truth for all UI coding, per rules.md Rule 1. It supersedes `design-brief.md` (kept for reference on original intent only) and any raw Stitch export folder's own copy of this file — this is the single canonical version to hand to a dev session.

**Locked and safe to build against (13 screens):** Onboarding, Login/Signup, Chat List, Chat Detail 1-on-1, Chat Detail with AI Agent, Group Creation, User Search, Voice Note, Location Sharing, Status List, Status Viewer, Profile/Settings (fixed), Wisp brand logo.

**Not usable as visual reference — build directly from tokens above instead (2 screens):**
- **In-Call Video screen** — Stitch has produced overlapping text across two regeneration attempts (contact name overlapping call timer; self-view label overlapping thumbnail caption and control icons). Do not use the exported screen.png/code.html as a layout reference.
- **Incoming Video Call screen** — Stitch has exported a cropped/incomplete screen across two attempts (only a partial top sliver renders). Do not use the exported screen.png/code.html as a layout reference.

For these 2 screens, build the layout directly from the color/typography/spacing/shape/component tokens defined above (Buttons, Message Bubbles, Status & Indicators sections) rather than continuing to regenerate in Stitch — the token system already fully specifies what's needed: dark full-bleed background, cream contact name, muted call status text, circular outline-icon controls with red for decline/end-call and Moderate Green for accept, consistent 8px spacing between stacked text elements to avoid overlap.
