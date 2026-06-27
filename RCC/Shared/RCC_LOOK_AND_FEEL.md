# RCC Look And Feel

Room Control Center is a modular script system. Every module must feel like the same product, not like a separate REAPER script.

## Core Rules

- Use shared RCC modules before custom drawing: `RCCTheme`, `RCCUI`, `RCCUIUtils`, `RCCUIKit`, and `RCCModule`.
- Use the RCC grid: 3 px tiny gaps, 6 px normal gaps, 8 px panel padding.
- Use RCC heights: 18 px header/action buttons, 22 px list rows.
- Use RCC radius: 4 px for controls and rows, 6 px for panels.
- Center every button label by measured text size through `RCCUI.CenterTextInRect` or `RCCUIUtils.CenterTextInRect`.
- Hover, active, and selected states must not change geometry. They only change tone, border, or accent intensity.
- Do not draw value fills behind readable text unless the component explicitly reserves text lanes.
- Right-side numeric values are badges/readouts, not loose text.
- Popups use dark RCC styling: rounded 4-7 px, padded 4-8 px, smoked background, subtle border, no default gray selectable rows.
- Collapsible panels use RCC animation: smoothstep easing, faster collapse than expand.
- When a new visual idea is approved, promote it to `Shared` before copying it into another module.

## Module Contract

- New modules must add `../../Shared/?.lua` or use `RCCModule.AddSharedPaths`.
- New modules should use `RCCModule.RequireImGui`, `RCCModule.CreateFonts`, and `RCCModule.ApplyTheme`.
- New modules should expose a small module table when practical: `id`, `title`, `version`, `capabilities`, `init`, `draw`, and `shutdown`.
- A module may draw custom primitives only for domain-specific widgets. Generic buttons, panels, meters, badges, selectors, popups, animation, and theme colors belong in `Shared`.

## Reuse Rules

- Analyzer, meter, waveform, and readout components become shared components when they are considered finished.
- Future modules must reuse finished shared components instead of reimplementing them.
- Module-local helpers are allowed only while an idea is experimental. Once accepted, move the helper into `Shared` and replace local copies.
