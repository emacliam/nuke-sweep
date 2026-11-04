# Nuke Sweep macOS widgets

The app embeds `NukeWidgets.appex` with two native WidgetKit configurations:

- **Nuke Sweep Storage**: available capacity and a used-storage meter.
- **Nuke Sweep Resources**: CPU snapshot, active+wired+compressed VM memory, and available storage.

Both support small and medium families, light/dark appearance, last-refresh timestamps, unknown readings, and safe deep links to Nuke Sweep. They do not initiate cleanup.

## Data and refresh

`NukeMetrics` provides the same system-counter and filesystem formulas used by the app. Each widget samples these counters directly in its sandbox, without reading Nuke Sweep's personal scan history, receipts, filenames, or other app data. No shared-container entitlement is required for this design. CPU is measured over a 250 ms counter interval when the provider is asked for content, not streamed continuously.

A timeline requests another refresh after 15 minutes. macOS controls actual refresh timing; it is not a guarantee. The app requests widget reloads no more than every 15 minutes during monitoring, plus explicit user refresh requests. The five-second menu-bar monitor is the live surface. See [Apple's timeline guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

## Build and sign

`./scripts/build-app.sh` compiles the app, shared modules, WidgetKit executable, and embeds/signs the extension before signing the containing app. Default signing is ad-hoc for local development. To use an available local development identity:

```sh
NUKE_SIGN_IDENTITY="<installed identity name or SHA-1>" ./scripts/build-app.sh
```

The extension requests only App Sandbox. It does not request App Groups, network, Full Disk Access, or notification privileges. The host app retains its existing cleanup access model.

A local ad-hoc extension may be rejected or omitted by the widget gallery. A signed development build can be used for local testing; public distribution still needs an appropriate signing/notarization workflow. Never disable Gatekeeper or other OS security protections to install a widget.

## Add a widget

Launch the containing app at least once after building/installing it. Control-click the desktop, choose **Edit Widgets**, search **Nuke Sweep**, and choose Storage or Resources and a size. Alternatively open Notification Center and choose Edit Widgets. Adding a desktop widget is left to the user; the build does not alter the desktop arrangement.

Clicking a widget opens Nuke Sweep's Storage or Monitor section. If metrics cannot be read, the widget shows an unknown reading rather than zero. Widget previews in Nuke Sweep use current local data and the exact shared SwiftUI view code used by the extension; they are not proof that the OS has accepted the extension into its gallery.

Apple requires launching the containing app before initial gallery discovery: [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension).
