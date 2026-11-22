# Armory Upgrades preview

Verified 2026-11-22 with Godot 4.6.3. Existing No-Te task: `4ba86118-6b7f-4fa9-afda-c4e59868fc0e` (Redesign Main Menu as a mission preparation hub). Changes are uncommitted; commit SHA: null.

## Result

The existing Upgrades navigation opens ARMORY UPGRADES, with a display-only Currency: 0 header, a responsive card grid and Back. Armor, Bolter Damage, Movement and Max Health each display 0 / 5, five empty rank markers, Cost: — and a red LOCKED badge. Descriptions respectively explain flat damage reduction, Bolter base damage, movement speed and maximum health. Hover and keyboard focus provide feedback; clicks do not buy anything or change ranks.

The page owns four local UI-only dictionary records (stable ID, name, rank, maximum rank, description and placeholder cost). A reusable visual card scene renders those records. There is no progression backend, save data, currency acquisition, pricing, unlocking or gameplay stat application.

At widths of at least 700 pixels the cards form a two-column grid; narrower windows use one column and stack the header. The existing scroll container handles limited height. Card height follows wrapped content. Opening Armory focuses its first card and resets scrolling so the heading stays visible; focusing Back initially had scrolled the narrow preview down and was corrected. Back and Escape return to preparation.

## Files for this extension

- Modified `scenes/ui/main_menu.tscn`: Armory header, grid, page script and Back.
- Modified `scripts/ui/main_menu.gd`: currency display, responsive sizing and initial Armory focus/scroll.
- Modified `tests/main_menu_test.gd`: card data, harmless clicks, styles, grid bounds/wrapping/overlap, responsive header visibility and unchanged deployed player defaults.
- Added `scenes/ui/armory_upgrade_card.tscn`.
- Added `scripts/ui/armory_upgrade_card.gd` and its `.uid`.
- Added `scripts/ui/armory_upgrades_page.gd` and its `.uid`.
- Added this report.

Pre-existing character/mission selection edits and their selection-card/data files and report were preserved. They were already pending when this extension began. No gameplay, artwork, audio, import settings or project startup configuration was changed for Armory.

## Observed verification

- Baseline menu regression: 378 checks passed before the extension.
- Final headless `tests/main_menu_test.gd`: 575 checks passed.
- Native D3D12 menu capture regression: 589 checks passed. This preceded one final test-only assertion for heading visibility; production code was identical to the final headless/CI run.
- Full `tests/run_ci_tests.gd`: 8/8 suites passed, including the final 575 menu checks.
- Rendered previews checked at 1152×648, 1600×900, 960×540, 800×600 and 360×480. Desktop and narrow screenshots were visually inspected, including the corrected narrow initial scroll position.
- Existing regression coverage exercised Character Select, Mission Select, Collection, Settings, Back/Escape, DEPLOY and native menu/gameplay audio ownership. Deployed player defaults remain HP 50, speed 150 px/s, armor 0 and Bolter damage 25.
- Native editor import and normal project startup completed without parser/import errors.
- Dedicated native Quit mouse-input fixture exited 0. It still reports the existing synthetic-fixture ObjectDB/resource cleanup diagnostics. The final repeated Quit invocation additionally reported inability to create the optional shader-cache directory in this execution environment; rendering and Quit completed.
- `git diff --check` passed. Existing line-ending normalization notices remain informational.

Some older gameplay CI fixtures also emit previously documented ObjectDB/resource cleanup diagnostics despite passing. These were not suppressed or changed. No subjective audio listening assessment is claimed. No commit or push was performed.
