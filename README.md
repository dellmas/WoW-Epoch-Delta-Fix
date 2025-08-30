# DWD_TooltipDeltaFix ([WoW-Epoch-Delta-Fix](https://github.com/dellmas/WoW-Epoch-Delta-Fix)): ElvUI compatibility plugin.

> [!TIP]
> <ins>The plugin was primarily made to bring back ElvUI compatibility, but it works even for **non-ElvUI users**</ins>!  
> (Without ElvUI, it will only make the tooltips require Shift to be held, and make some tooltip anchoring adjustments)

Plugin for the original “DWD Tooltip Delta Fix” addon that adds:
- ElvUI-friendly styling for compare tooltips (applied only if ElvUI is loaded)
- Retail-like anchoring (compare panes extend toward the screen center with safe fallbacks)
- Optional Shift-to-show gating (show comparisons only while holding Shift)

---

## Requirements

- **Required: DWD_TooltipDeltaFix/[WoW-Epoch-Delta-Fix](https://github.com/dellmas/WoW-Epoch-Delta-Fix)**
- Optional: [ElvUI-WotLK](https://github.com/ElvUI-WotLK/ElvUI) (to skin the compare tooltips when present)
- Client: WotLK 3.3.5

---

## Features

- ElvUI Compatibility
  - Skins DWDCompareTooltip1/2 via ElvUI’s Tooltip module when ElvUI is present (no hard dependency).
- Retail-like anchoring
  - Compare panes prefer to extend toward the screen center; falls back outward, then below if needed.
- Shift-to-show (configurable)
  - Comparisons only appear while holding Shift (enabled by default in the plugin; see Configuration).  

---

## Installation

1) Install the original addon: DWD_TooltipDeltaFix [WoW-Epoch-Delta-Fix](https://github.com/dellmas/WoW-Epoch-Delta-Fix).
2) Install this plugin:
   - Download and extract this plugin, rename from `DWD_TooltipDeltaFix_ElvUI-main` to `DWD_TooltipDeltaFix_ElvUI`
   - Place the folder `DWD_TooltipDeltaFix_ElvUI` in `Interface/AddOns/`.
3) Ensure both are enabled on the character selection screen.

The plugin’s TOC declares the original addon as a dependency, so load order is guaranteed.

---

## Configuration

Edit the top of `DWD_TooltipDeltaFix_ElvUI.lua` to adjust behavior:

- REQUIRE_SHIFT = true
  - If true (default), compare tooltips show only while holding Shift.
  - Set to false for always-on comparisons (original behavior).
- PADDING_X, PADDING_Y, SCREEN_MARGIN
  - Fine-tune compare pane positioning relative to the main tooltip.

No in-game slash commands; this plugin is intentionally simple and minimal.

---

## Credits

- Original addon: DWD_TooltipDeltaFix ([WoW-Epoch-Delta-Fix](https://github.com/dellmas/WoW-Epoch-Delta-Fix)) by dellmas
- Plugin: ZythDr (and ChatGPT)
- License: MIT

---
