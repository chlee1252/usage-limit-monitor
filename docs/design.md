# Design notes

A compact native menu bar instrument for checking headroom before starting another AI task.

## Compact revision

The panel is 300 points wide and fits its actual content (roughly 300 points tall with three providers and five quota windows). It has no subtitle, oversized percentage, or repeated update footer. Each quota occupies one line: label, narrow meter, percentage, time to reset. A tooltip provides exact reset time and source; unavailable, stale, manual, and error states remain visible.

The system background/label colors and the Codex `#1F7A6B`, Claude `#AD613B`, Gemini `#426ECA`, warning `#FF9500` palette remain. Use SF system at 10–12 points with tabular digits. A 14-point inset, 22-point quota row, and small service separators form a utility menu, with no cards or decorative motion. All controls have accessibility names. If quota rows exceed the available screen height, only the list scrolls.

```text
Usage Monitor                      ↻
Codex
5시간    ━━━━━━━━━│────  42%   2시간
7일      ━━━━━━━━━│────  68%     2일
───────────────────────────────────
Claude Code
5시간    ━━━━━━━━━│━━──  83%   1시간
7일      ━━━━━━━━━│────  56%     1일
───────────────────────────────────
Gemini                    직접 입력
일일     ━━━──────│────  24%   8시간
───────────────────────────────────
80%에서 알림                    ⚙  ⋯
```

Review: retain separate quota windows, rather than compressing a provider into an ambiguous single percentage. Remove repeated labels and empty space. The menu bar percentage can independently select a provider and quota window; missing selections never silently switch to a different provider.

## Original direction

- System background and label colors follow macOS light and dark appearance.
- Provider colors: Codex `#1F7A6B`, Claude `#AD613B`, Gemini `#426ECA`; warning amber `#FF9500`; neutral track uses the system label color at 7% opacity.
- SF system type for controls; rounded SF for percentages and the title, with tabular digits to keep changing values stable.
- A 370-point panel, left-aligned service names, right-aligned percentages, and aligned horizontal quota meters. One thin tick on every meter communicates the user's alert threshold.
- Provider sections use separators rather than nested cards. No decorative gradients or animation.
- Missing data has a connection action. Old or expired readings are explicitly labeled and muted. Unknown usage is never represented as zero.

```text
Usage Monitor                       refresh
------------------------------------------
terminal  Codex                 automatic
5 hours                               42%
━━━━━━━━━━━━━━━━━━────────────│──────────
Reset countdown              threshold
7 days                                68%
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━│──────────
------------------------------------------
asterisk  Claude Code           statusline
…
------------------------------------------
bell  Alert at 80%               settings
```

Review: the bar and threshold tick carry the product's central information. Avoiding rings and oversized summary cards leaves enough room to compare distinct reset windows without implying that different providers share a quota.
