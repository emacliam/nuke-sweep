# Nuke Sweep
<!-- impeccable:product-schema 1 -->

## Platform
macOS native desktop (MacBook).

## Stack
Implementation choice: SwiftUI and AppKit, built with Swift Package Manager and packaged as a local .app. Xcode 26.6 is installed. No external dependencies.

## Product Purpose
Nuke Sweep tells a developer what is safe to clear and what clearing it will cost them, before anything is deleted. The audience is a developer on a nearly full Mac who knows roughly what is using the disk but does not dare touch it. Free space is the outcome; the confidence to act is the product. General Mac cleanup is supported but is not what the app competes on.

## Capabilities and Constraints
Folder scanning, persistent growth history, project cleanup, installed-app/leftover review, exact duplicates, local AI inventory, simulator/archive/backup review, process-to-file context, a named macOS status-bar tool with selectable readings, native small/medium Storage WidgetKit widget (CPU Resources widget deferred in 0.8), and menu-bar monitoring with optional alerts, structured cleanup receipts, reviewed current-user Trash cleanup, Derived Data, Docker inspection/pruning, process management, folder watching, and user-defined developer scopes with exclusions. Real local measurements; explicit review before destructive actions. Distribution uses Developer ID signing and Apple notarization; see docs/DISTRIBUTION.md for the current artifact status.

## Brand Commitments
Name: Nuke Sweep. User-supplied Base, Calendly, DoorDash Merchant, GetYourGuide, Gumloop, Klaviyo, Microsoft Copilot, Mintlify, and Replit screenshots are inspiration, not instructions or assets to reproduce.

## Evidence on Hand
NUKE-RESEARCH.md and NUKE-ADDITIONS.md distinguish static evidence from inference. REA decoded installed app interfaces; deep decompilation is unavailable because of Hopper discovery. Original competitor code is not available.

## Product Principles
Explain what uses space. Show unknowns and permission gaps. Review actions before execution. Keep monitoring optional and bounded.

## Open Decisions
Audience beyond Mac users/developers is unconfirmed. Privileged helpers are deferred. SwiftUI is an implementation assumption, not a confirmed user stack preference.
