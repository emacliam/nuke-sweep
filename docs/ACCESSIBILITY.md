# Keyboard and accessibility

## Appearance

- System, Light and Dark are available in Settings → General.
- The main window and menu-bar popover share the setting.
- Theme colors use adaptive light/dark tokens; the primary action, status colors, cards, tables, separators and brand mark have dark variants.
- Color is never the only signal: warnings include text and icons; selected navigation includes an underline or tinted row.

## File tree keyboard map

Focus the tree with Tab, then:

| Key | Action |
|---|---|
| Up / Down | Move the focused row |
| Space | Open Quick Look for the focused file |
| Shift-Space | Select or deselect the focused item when allowed |
| Right | Expand the focused folder; if already expanded, move to the next row |
| Left | Collapse the focused folder; otherwise move to its parent |
| Return | Expand or collapse the focused folder |
| Tab | Move to the tree’s controls (disclosure, checkbox, actions) |

The focused row has a visible outline. Blocked, incomplete and action-busy rows cannot be selected from the keyboard.

## Other keyboard support

- `⌘F` focuses the Files/Processes filter or the History/Apps filter.
- `⌘R` refreshes.
- `⌘O` opens the folder chooser.
- `⌘1`–`⌘5` open Cleanup, Files, Apps, History and Settings.
- Native tables and pickers support standard arrow, Tab and VoiceOver navigation.

## Personal Files

In Cleanup, use Tab to reach a file category and Space to expand it. Tab moves
through the checkboxes and the available Quick Look and Finder buttons. Use Space
to activate the focused control. The category reports its item count, selected
count, size and recovery information. Each checkbox identifies the file and
provides its measured size and reason for being listed. Incomplete files cannot
be selected. The review button becomes available after eligible files are selected.

## Accessibility labels

- Tree rows expose disclosure, checkbox, item name, size and evidence controls separately.
- AI controls have labels for the active provider, plan provider, add-provider menu, Explain action and plan/undo actions.
- Chart marks expose date/item and size values; chart pickers provide a keyboard alternative to hover.
- The brand mark is hidden from accessibility (decorative).
- Sidebar and section tabs expose selected traits.

## Known gaps

- A complete VoiceOver pass over every screen has not been run.
- Dynamic Type and larger accessibility text sizes are not yet supported by the fixed-size layout.
- The custom tree’s keyboard support is new; verify with VoiceOver on your macOS version.
- The treemap is mouse-first; the table and list below it remain the accessible alternative.
- Reduce Motion is not explicitly handled; the app has few animations, but this needs review.
