# UI Refactor Follow-up Fix Plan (2026-02-13)

## Scope
- 目标：修复重构后 UI 可读性、风格一致性与组件样式遗漏问题。
- 约束：分项推进；每完成一项即更新本文档进度。

## Progress
- Overall: `19 / 19` completed
- Last update: `2026-02-13`

## Task Checklist
1. [x] Add shared visual tokens + form-control helpers in `ui/utils/ui_styles.gd`
2. [x] Fix critical menu readability baselines (online lobby + settings + key labels with missing explicit dark text)
3. [x] Style runtime-created labels in online lobby renderers/controllers
4. [x] Unify runtime-generated controls in room config editor
5. [x] Unify runtime-generated controls in game setup dynamic rows
6. [x] Align module selector group palette with warm UI system + unify notes/checkbox text styles
7. [x] Fix outdated modal hint color(s) conflicting with current warm theme
8. [x] Unify action panel context labels + rotate buttons + context control styling
9. [x] Apply consistent topbar button styling in main game HUD
10. [x] Unify dynamic dialog text/control styling (save/load, info, password)
11. [x] Unify help tooltip visual style with shared panel/text tokens
12. [x] Contrast pass for low-alpha text and weak muted text hotspots
13. [x] Batch-2: Unify ReserveCardSelectionModal text/button styles (title/selection/card title/card description/hint)
14. [x] Batch-2: Fix menu modal stacking priority so it never gets covered by gameplay modals
15. [x] Batch-2: Enforce menu + blocking gameplay modal coexistence safety (auto-close stale menu before opening reserve-card modal)
16. [x] Batch-2: Screenshot-driven contrast follow-up for weak placeholder/hint texts (turn-order empty slot + company-structure empty slot)
17. [x] Batch-3: Prevent opening game menu while blocking gameplay modals are active (fix reserve-card menu click dead state)
18. [x] Batch-3: Add reliable scroll-wheel zoom support in EmployeeTree (upgrade route panel)
19. [x] Batch-3: Unify player info panel employee/milestone subcomponent styles with shared warm UI tokens

## Update Log
- `2026-02-13`: Created plan and initialized task checklist.
- `2026-02-13`: Completed Task 1. Added shared color tokens and helper methods for labels, line edits, option buttons, spin boxes, check boxes, tab containers, and item lists.
- `2026-02-13`: Completed Task 2. Applied readability baseline styles in online lobby and settings dialog, and fixed key missing label text colors in core panels.
- `2026-02-13`: Completed Task 3. Styled runtime-generated labels in online lobby room list/state renderers to use unified readable text colors.
- `2026-02-13`: Completed Task 4. Unified dynamic control styling in room config editor (labels, form fields, check boxes, error text, advanced toggle button).
- `2026-02-13`: Completed Task 5. Unified dynamic game setup rows and form controls (player rows, setup message label, seed/player count inputs).
- `2026-02-13`: Completed Task 6. Reworked module selector group palette to warm tones and unified notes/checkbox text styles.
- `2026-02-13`: Completed Task 7. Updated restructuring modal legacy hint text color to match warm theme tokens.
- `2026-02-13`: Completed Task 8. Unified ActionPanel context area visuals (labels, option fields, rotate buttons, context panel surface).
- `2026-02-13`: Completed Task 9. Applied unified button styling to main game TopBar controls.
- `2026-02-13`: Completed Task 10. Unified dynamic dialog text/control styling for save/load, info, and password dialogs.
- `2026-02-13`: Completed Task 11. Unified tooltip panel and text styling with shared warm UI tokens.
- `2026-02-13`: Completed Task 12. Finished contrast cleanup for low-alpha hotspot texts (menu decorative lines/version text, turn-order empty slots, company-structure empty-slot hint).
- `2026-02-13`: Added Batch-2 follow-up tasks (Task 13-16) for screenshot-reported remaining inconsistencies and reserve-card/menu modal stacking conflict.
- `2026-02-13`: Completed Task 13. Unified ReserveCardSelectionModal visual hierarchy by applying shared dark/muted/error text tokens and secondary button styling for all card choices.
- `2026-02-13`: Completed Task 14. Raised game menu dialog and confirm dialog z-index to keep menu-related modals above gameplay phase modals.
- `2026-02-13`: Completed Task 15. Added blocking-modal safety hook so reserve-card modal opening force-closes stale menu/confirm dialogs to prevent coexistence conflicts.
- `2026-02-13`: Completed Task 16. Standardized weak empty-slot placeholders in turn-order and company-structure components to shared muted text tokens with stronger readable alpha.
- `2026-02-13`: Added Batch-3 follow-up tasks (Task 17-19) for reserve-card/menu interaction lockup, employee-tree scroll zoom support, and player-info employee/milestone style consistency.
- `2026-02-13`: Completed Task 17. Added menu-open guard for blocking gameplay modals so reserve-card/other mandatory modals no longer enter an unclickable menu state.
- `2026-02-13`: Completed Task 18. Reworked EmployeeTree zoom input path to support reliable wheel zoom from GUI input and added touchpad magnify gesture fallback.
- `2026-02-13`: Completed Task 19. Unified LeftPanel employee list and milestone card visuals with shared warm tokens (text, buttons, borders, and panel surfaces) to match main game style.
