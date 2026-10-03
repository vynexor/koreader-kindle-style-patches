# Reference: my personal build of the patch

`2-mimic-kindle-ui-patch.personal.lua` is the built v1.2.0 patch with my changes edited directly into it. It runs on a Kindle Paperwhite 12th gen (KOReader 2026.07) and was tested in the macOS build of KOReader. It is here as a reference for porting the changes into `src/` properly, with tests.

## Changes that fix problems for everyone (candidates for a pull request)
1. **Missing spaces in the footer** ("Time left in chapter:25minutes"). KOReader's compact item style replaces every whitespace with a hair space. Fix: use no-break spaces in the footer text (`keepSpaces`).
2. **Percentage truncated to "…"** on KOReader 2026.07.2+. The old `genAllFooterText` override added margins after the filler was measured, so the line was wider than the bar. Fix: margins are added inside the left and right items.
3. **Tap to cycle the left item**: page -> time left in chapter -> time left in book -> blank (setting `kindle_ui_left_mode`, `TapFooter` override). Kindle-style wording: "5 mins left in chapter", "4 hrs 40 mins left in book", "Page 5".
4. **Percentage stays in place** when the left item changes: the left text is padded with hair spaces until the whole line is as close as possible to the bar width.
5. **Clock updates by itself** once a minute instead of only on page turn (`refreshClock`, partial "ui" refresh of the header strip; stops when no book is open or the device sleeps).

## Personal taste (keep out of the pull request, or make them config options)
- Header: `top_padding = 24`, `font_bold = false` plus the text painted three times one pixel apart for a medium weight.
- On suspend with a transparent sleep screen (`screensaver_background == "none"`): close menus, dictionary and selection pop-ups, hide header and footer, restore on wake.
