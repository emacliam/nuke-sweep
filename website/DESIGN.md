---
name: Nuke Sweep Showcase
description: An editorial showcase for a considered Mac cleanup utility.
colors:
  paper: "#fbfaf7"
  ink: "#262b2b"
  rust: "#b73e1c"
  orange: "#c24521"
  muted: "#626760"
  line: "#ddded6"
  rail: "#f0efe9"
  forest: "#386654"
  primary-hover: "#963218"
  selection: "#f4c6b2"
  hero-copy: "#545b55"
  screenshot-stage: "#e9e7df"
  window-caption: "#f7f6f2"
  window-border: "#d9dad2"
  window-label: "#6d7069"
  window-dot: "#d6d7cf"
  on-dark-muted: "#c7ccc3"
  on-dark-line: "#4c5350"
  on-dark-footnote: "#bdc5bb"
  white: "#ffffff"
typography:
  display:
    fontFamily: "Instrument, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "clamp(64px, 7.8vw, 104px)"
    fontWeight: 600
    lineHeight: 1.02
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "Instrument, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "clamp(36px, 4.3vw, 54px)"
    fontWeight: 600
    lineHeight: 1.13
    letterSpacing: "-1.9px"
  body:
    fontFamily: "Instrument, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Instrument, -apple-system, BlinkMacSystemFont, sans-serif"
    fontSize: "14px"
    fontWeight: 400
rounded:
  button: "7px"
  callout: "9px"
  screenshot: "11px"
  stage: "15px 15px 0 0"
spacing:
  mobile-gutter: "20px"
  tablet-gutter: "28px"
  desktop-gutter: "48px"
  section: "105px"
  section-mobile: "62px"
components:
  button-primary:
    backgroundColor: "{colors.rust}"
    textColor: "{colors.white}"
    rounded: "{rounded.button}"
    padding: "15px 22px"
  button-primary-hover:
    backgroundColor: "{colors.primary-hover}"
    textColor: "{colors.white}"
  screenshot-frame:
    backgroundColor: "{colors.rail}"
    rounded: "{rounded.screenshot}"
    padding: "20px"
  installation-callout:
    backgroundColor: "{colors.rail}"
    textColor: "{colors.muted}"
    rounded: "{rounded.callout}"
    padding: "25px 28px"
---

# Design System: Nuke Sweep Showcase

## Overview

The approved direction is **Persuade**: a cream, typography-led editorial showcase that lets the real Mac app supply the evidence. Large, closely set headlines, generous space, restrained rust accents, and fine rules give the page a calm, practical voice.

This document governs `website/` only. Root `PRODUCT.md` defines product truth; root `DESIGN.md` governs the native app. Site guidance must preserve the product's commitments to real measurements, visible unknowns, explicit review, and optional monitoring.

**Key characteristics:** editorial hierarchy; authentic product imagery; linear information; a dark cleanup-safety chapter; direct download.

## Colors

### Primary

- **Rust** is the website's interactive accent: primary downloads, the hero's emphasized word, selected tabs, icons, and focus rings. The darker site CTA value preserves contrast with white text.
- **Brand Orange** is retained in the approved identity. Do not replace the site CTA rust with the brighter brand orange without checking contrast.

### Neutral

- **Paper / Ink** supply the main ivory canvas and charcoal text; reverse them for the safety chapter.
- **Muted** supports explanatory text. **Line** separates rows and sections. **Rail** groups screenshots and the installation callout without introducing cards throughout the page.
- **Forest** marks factual reassurance and the release-status line; it is a supporting status color, not a competing primary accent.
- The remaining frontmatter colors are observed supporting values from `styles.css`, including screenshot chrome, selection, and text on the dark chapter.

## Typography

Instrument Sans is self-hosted under the CSS family name `Instrument`. The regular TTF supplies 400; the semibold TTF is declared for 600–800. The implemented system uses 400 and 600. System fallbacks remain available during loading (`font-display: swap`).

- **Display:** the hero uses the frontmatter clamp with deliberate line breaks. At 1000px and below it becomes 78px; at 700px and below it becomes `clamp(43px, 13.1vw, 58px)` with 1.04 line height.
- **Headline:** section headings use the frontmatter scale; mobile uses 38px / -1.3px tracking. Safety, FAQ, download, and privacy headings have local size adjustments.
- **Title:** product-panel titles are 29px / 1.18 / -0.8px, 600; tool and installation headings are 21px with -0.4px tracking.
- **Body:** base 16px / 1.6. Intro copy ranges from 17–19px; supporting content is 14–15px. Requirements and factual notes use 11–12px.
- **Labels:** navigation and tabs are 14px on desktop; selected tabs become 600. Avoid uppercase display treatments absent from this implementation.

## Layout

The centered `.wrap` is `min(1180px, calc(100% - 96px))`. At max-width 1000px it becomes `calc(100% - 56px)`; at max-width 700px it becomes `calc(100% - 40px)`.

The page sequence is hero and screenshot, factual principles, screenshot tabs, linear tool list, full-width dark safety chapter, installation steps, FAQs, final download, and footer. Desktop uses a `1fr 250px` hero, `280px 1fr` product panel, three-column tool rows (`48px 270px 1fr`), three installation columns, and paired safety/FAQ/download columns. Standard sections have 105px vertical padding; mobile uses 62px. At 700px the hero and paired chapters stack, the side icon is hidden, tool rows retain an icon rail, and installation steps become vertical.

Privacy uses the same header, palette, and footer with a 740px maximum prose width. The site has no forms or account flow.

## Elevation & Depth

There are no box shadows. Tonal layers, one-pixel borders, and screenshot chrome establish depth. The cream screenshot stage and rail belong to authentic app imagery rather than every text section. Dark safety content creates one strong chapter transition.

## Shapes

Buttons and screenshot images use 7px corners, the installation callout 9px, the screenshot rail 11px, and the desktop hero stage 15px top corners. Mobile reduces the stage to 9px. Circular step numbers and window dots are the only repeated circular shapes. Tool rows, tabs, FAQs, and page divisions remain flat and ruled.

## Components

### Downloads and links

Primary download anchors are rust with white 600 text, 15px desktop type, 15px 22px padding, a 36px label/arrow gap, and 7px corners. Hover darkens to the recorded primary-hover color over 0.18s. Mobile uses 14px type, 14px 18px padding, and a 23px gap. Text links underline on hover with a 5px offset. The header download is a restrained underlined link. Download targets are the actual versioned DMG; checksum and release-note links accompany the final CTA. Release claims must match the packaged artifact.

### Navigation

Desktop navigation is an inline 14px row inside a 110px header. Mobile has an 83px header and an explicit Menu button that opens a wrapped link panel beneath it. `aria-expanded` reflects state; links close it, and Escape closes it and returns focus to the menu button.

### Screenshot tabs

Three buttons share one tabpanel: Everyday cleanup, Developer workspaces, and At a glance. Selected tabs use rust text and a 2px underline. Roving tabindex, Left/Right arrows, Home, and End update selection and focus. Update the panel's `aria-labelledby`, title, copy, factual note, image, and alternative text together. Preserve intrinsic screenshot proportions; use the real app captures rather than reconstructed interfaces.

### Tool list, installation, and FAQs

Tools are ruled rows with small inline SVG symbols, titles, and explanatory copy. Installation is an ordered three-step sequence with circular counters and a quiet permissions callout. FAQs use native `details`/`summary`, with rust plus/minus indicators and no accordion script. Supporting safety notes remain legible within the dark chapter.

### Accessibility and motion

Links, buttons, summaries, and focusable tabpanels use a 3px rust focus outline with 6px offset. The skip link becomes visible on focus. At min-width 900px, the hero copy enters over 0.7s with `cubic-bezier(.16,1,.3,1)`, translating 12px and resolving opacity/blur. Reduced-motion disables animations and transitions and restores automatic scrolling. Smooth scrolling otherwise uses a 28px anchor offset.

### Asset provenance

`assets/cleanup.png`, `developer.png`, and `widgets.png` are real Nuke Sweep 0.8.1 captures, as recorded in `website/README.md`; widget imagery is a preview/setup screen, not a promise of continuous widget updates. `mark.svg` and `app-icon.png` derive from the user-approved identity in `branding/nuke-sweep`. The TTF files originate from Google Fonts / the Instrument Sans project; retain `assets/FONT-LICENSE.txt` (SIL Open Font License 1.1). Assets and fonts are served locally. No competitor reference screenshot is a shipped site asset.

## Do's and Don'ts

- **Do** preserve the approved charcoal, orange, and ivory identity while using rust for site CTAs.
- **Do** keep authentic screenshots, clear product limitations, review-before-cleanup language, and accurate platform requirements.
- **Do** preserve keyboard tab behavior, visible focus, native FAQ semantics, and reduced-motion support.
- **Do** update versions, download links, checksum, release status, and screenshot provenance together when the release changes.
- **Don't** turn the linear tool list into a grid of generic cards or add shadows to the flat system.
- **Don't** imply automatic cleanup, guaranteed reclaimable space, or live WidgetKit refresh.
- **Don't** apply website typography or layout rules to the native app's root design system.
