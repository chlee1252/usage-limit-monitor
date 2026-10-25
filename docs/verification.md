# Interaction verification

Verified on macOS using Computer Use on 2026-10-25.

- Opened the running menu bar app's popover and inspected its live accessibility tree and screenshot.
- Clicked refresh; Codex returned current quota data and the popover remained usable.
- Inspected the revised header: refresh and settings are separate controls. The footer contains notification status and Quit, with no native overflow menu next to settings.
- Clicked the header settings control; the native settings window opened.
- Reopened the popover through Finder's Open action on the running app.
- Clicked an empty part of the Finder window outside the popover. A subsequent screenshot and fresh accessibility tree showed only the settings window, confirming the popover had closed.
- Pressed Escape while the popover was open. The accessibility tree switched back to the settings window.
- Reopened the popover and opened settings again after dismissal.

The test did not change the user's notification, provider, or account preferences. README images use the separate sample-data renderer, not live account screenshots.

Automated validation: `swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` (24 tests), release `.app` build, and the panel layout check.
