# Native UI check, 2026-10-12

Checked on macOS 27.0.1 (26A434), built with SDK 27. The deployment target remains macOS 15. A temporary native app rendered the production views with a separate synthetic archive, a public synthetic PDF and disabled network transport. The installed app and its records were not changed. This is a focused compatibility check, not exhaustive accessibility or older-OS certification.

## Changes kept

- Start and bookings: reproduced the narrow glass pill around the busy spinner. Both now use `IntakeProgress`, hiding only the status item's shared background on macOS 26 and later. Action groups retain their native backgrounds. Checked busy appearance in light and dark and absence while idle. The indicator also has a meaningful accessibility label and tooltip.
- Inspector: reproduced clipped payment amounts at the normal fixed pane width. The payment/refund label now sits below the date and amount. Verified visible `1.234,56 €` and `-1.115,56 €` as well as small amounts in light and dark. Bindings, validation and arithmetic are unchanged.

## Other views checked

The standard settings tabs, profile form, AI settings and appearance picker remain native. Profile content uses its existing scrollable form. Booking selection, receipt thumbnail, expanded PDF preview and its Return-key dismissal rendered correctly on this display. The export dialog rendered and dismissed with Escape. Start and the empty chat/composer also rendered normally. No external API call or real document import was part of this UI check.

## Remaining finding

The selected Settings tab has weak contrast in dark appearance: the fixed navy app accent is too close to the tab background. Inactive windows additionally dim their native controls, as expected.

A lighter dark accent improved the tab and native button foregrounds, but left white text on a lighter selected table row. Neither `.tint` nor `.accentColor` scoped to Settings changed the AppKit-backed tab selection; a local table tint also failed to isolate the selection fill. A grouped-tab trial produced overlapping labels. All these experiments were removed. Keep the standard tabs and resolve accent/selection colors together in a separately bounded change rather than introduce custom controls or native-view introspection.

Receipt preview is still fixed at 720 × 800 points. Its footer was reachable on this Mac; smaller display heights were not verified.

## Verification

259 existing tests passed, SwiftFormat was clean, and the standard Debug app build succeeded. A separate review checked the macOS availability guard, both spinner call sites, payment bindings and unnecessary complexity. No schema, model configuration or accounting rules changed.

Apple API reference: [ToolbarContent.sharedBackgroundVisibility](https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)).
