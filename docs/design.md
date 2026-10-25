# Design notes

A compact native menu bar instrument for checking headroom before starting another AI task.

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
