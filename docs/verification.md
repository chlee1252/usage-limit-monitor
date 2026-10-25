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

## Launch at login

Verified on macOS using Computer Use on 2026-10-25 with the signed release `.app` bundle.

- Opened Settings and inspected the **일반 → 로그인 시 자동 실행** switch.
- Verified the settings window initially shows the top of the form, with the login switch visible instead of scrolling to the Codex path field.
- Enabled the switch and confirmed it displayed `on`.
- Opened macOS System Settings → General → Login Items & Extensions and confirmed **Usage Monitor** appeared under **Open at Login**.
- Disabled the switch and confirmed it displayed `off`; the Usage Monitor row disappeared from the system's login items list.
- Restored the original off state after verification. Other application preferences were not changed.

No logout or reboot was performed. The test verifies system registration and removal, not an actual login session. The approval-required branch depends on macOS returning that status and was not exercised in this test.
