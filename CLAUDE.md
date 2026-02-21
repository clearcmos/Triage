# HealerMana - Development Guide

## Overview

HealerMana is a WoW Classic Anniversary Edition addon that tracks healer mana in group content. It automatically detects healers via talent inspection (since role assignment is unreliable in Classic) and displays their mana percentages with color coding and status indicators. It also tracks raid-wide cooldowns (Innervate, Mana Tide, Bloodlust/Heroism, Power Infusion, Divine Intervention, Rebirth, Lay on Hands) via combat log.

## Architecture

**Single-file addon** — all logic in `HealerMana.lua` (~2450 lines). No XML, no external dependencies.

### Key Systems

1. **Healer Detection Engine** (layered approach):
   - Layer 1: `UnitGroupRolesAssigned()` — trusts assigned roles
   - Layer 2: Class filter — only Priest/Druid/Paladin/Shaman can heal
   - Layer 3: Talent inspection via `C_SpecializationInfo.GetSpecializationInfo()` — checks `role` field first, falls back to `HEALING_TALENT_TABS` mapping when `role` is nil (which is the norm in Classic Anniversary). 5-man fallback assumes healer-capable classes are healers if API returns no data.

2. **Inspection Queue** — async system that queues `NotifyInspect()` calls with 2.5s cooldown, pauses in combat, validates range via `CanInspect()`. Runs on a separate `BackgroundFrame` (always shown) to avoid the hidden-frame OnUpdate deadlock. Periodically re-queues unresolved members.

3. **Raid Cooldown Tracker** — monitors `SPELL_CAST_SUCCESS` (and `SPELL_AURA_APPLIED` for Soulstone) in combat log for key raid cooldowns. Class-baseline cooldowns (Innervate, Rebirth, Lay on Hands, Divine Intervention, Soulstone, Bloodlust/Heroism) are pre-seeded as "Ready" on group scan; player talent cooldowns (Mana Tide, Power Infusion) detected via `IsSpellKnown()`. Multi-rank spells use canonical spell IDs for consistent keys. Displays with class-colored caster names, spell names, and countdown timers (or green "Ready") in a text-only layout matching the healer rows above.

4. **Display System** — two independently movable, resizable frames (`HealerManaFrame` for healer rows, `CooldownFrame` for raid cooldowns) with BackdropTemplate. `splitFrames` setting (default true) controls whether cooldowns render in their own frame or merge into HealerManaFrame. Object-pooled row frames reparented on acquire. Resize handles appear on hover, clamped to content-driven minimums. All periodic logic (preview animation, mana updates, display refresh) runs on BackgroundFrame to avoid hidden-frame OnUpdate deadlock.

5. **Options GUI** — uses the native WoW Settings API (`Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnCategory`) so options appear in the AddOns tab of the built-in Options panel (ESC > Options > AddOns > HealerMana). Proxy settings with get/set callbacks to `db`. `/hm` opens directly to the category.

### Code Sections (in order)

| Section | Lines (approx) | Description |
|---------|----------------|-------------|
| S1      | 1-42           | Header, DEFAULT_SETTINGS (incl. splitFrames, cdFrame* keys) |
| S2      | 44-82          | Local performance caches |
| S3      | 84-267         | Constants (classes, healing tabs, potions, raid cooldowns, canonical IDs, class/talent mappings) |
| S4      | 269-330        | State variables (incl. cdFrame resize state) |
| S5      | 332-470        | Utility functions (iteration, colors, measurement, status formatting) |
| S6      | 472-655        | Healer detection engine (self-spec, inspect results, inspect queue) |
| S7      | 657-810        | Group scanning + class cooldown seeding |
| S8      | 812-870        | Mana updating |
| S9      | 872-930        | Buff/status tracking |
| S10     | 932-940        | Raid cooldown cleanup (no-op, entries kept for Ready state) |
| S11     | 942-1010       | Potion + raid cooldown tracking (CLEU) |
| S12     | 1012-1040      | Warning system |
| S13     | 1042-1155      | HealerMana display frame + resize handle |
| S13b    | 1157-1260      | CooldownFrame + resize handle (split mode) |
| S14     | 1262-1310      | Row frame pool (UIParent-parented, reparented on acquire) |
| S15     | 1312-1355      | Cooldown row frame pool (split-aware reparenting) |
| S16     | 1357-1765      | Display update (PrepareHealerRowData, RenderHealerRows, RenderCooldownRows, RefreshHealerDisplay, RefreshCooldownDisplay, RefreshMergedDisplay, RefreshDisplay dispatcher) |
| S17     | 1767-1860      | OnUpdate handler (all logic on BackgroundFrame; per-frame resize-hover only) |
| S18     | 1862-2035      | Preview system (mock healers + mock cooldowns, both frames) |
| S19     | 2037-2230      | Options GUI (native Settings API, splitFrames checkbox) |
| S20     | 2232-2360      | Event handling (both frame positions restored) |
| S21     | 2362-2448      | Slash commands + init (lock/reset apply to both frames) |

## Features

- Auto-detect healers via talent inspection
- Color-coded mana display (green/yellow/orange/red with configurable thresholds)
- Dead/DC detection with grey indicators
- Status indicators: Drinking, Innervate, Mana Tide Totem (with optional durations)
- Potion cooldown tracking (2min timer from combat log)
- Soulstone status indicator on dead healers (purple "SS"/"Soulstone")
- Raid cooldown tracking with Ready/on-cooldown states: Innervate, Mana Tide, Bloodlust/Heroism, Power Infusion, Divine Intervention, Rebirth, Lay on Hands, Soulstone, Shield Wall
- Average mana across all healers
- Sort healers by lowest mana or alphabetically
- Optional chat warnings at configurable thresholds with cooldown
- Split or merged display: raid cooldowns in their own frame (default) or combined with healer mana
- Movable, lockable, resizable frames with configurable scale/font/opacity
- Live preview system with animated mock data
- Native options panel in AddOns tab (ESC > Options > AddOns > HealerMana, or `/hm`)
- Show when solo option

## Development Workflow

1. Edit `HealerMana.lua` in the AddOns directory
2. `/reload` in-game to test
3. `/hm test` to show fake healer data without a group
4. Copy changes back to `~/git/mine/HealerMana/`
5. Update version in `.toc` and `CHANGELOG.md`
6. Commit, tag, push to deploy

### New Feature Checklist

When adding any new trackable feature (buff, cooldown, status indicator, etc.), **always** include all three:

1. **Options GUI toggle** — add a `showFeatureName` entry to `DEFAULT_SETTINGS` and a corresponding checkbox in the appropriate section of `RegisterSettings()`. Gate the display logic behind `db.showFeatureName`.
2. **Preview system coverage** — add mock data to `PREVIEW_DATA` and/or `StartPreview()` so the feature is visible in `/hm test` and the settings panel preview. If the feature has a timer, add it to the OnUpdate preview loop logic.
3. **Feature list consistency** — update the Features section in both `CLAUDE.md` and `README.md` to mention the new feature.

## Key APIs Used

- `C_SpecializationInfo.GetSpecializationInfo(i, isInspect, isPet, target, sex, group)` — returns `pointsSpent` per talent tree; `role` field is nil in Classic Anniversary so we fall back to `HEALING_TALENT_TABS` mapping
- `C_SpecializationInfo.GetActiveSpecGroup(isInspect, isPet)` — active talent group (required for dual spec)
- `NotifyInspect(unit)` / `INSPECT_READY` / `ClearInspectPlayer()` — inspection workflow
- `UnitGroupRolesAssigned(unit)` — assigned role check (rarely set in Classic)
- `CombatLogGetCurrentEventInfo()` — potion and raid cooldown tracking
- `UnitBuff(unit, index)` — buff scanning
- `GetPlayerInfoByGUID(guid)` — class lookup for cooldown casters
- `IsSpellKnown(spellId)` — player talent cooldown detection
- `Settings.RegisterVerticalLayoutCategory()` / `Settings.RegisterAddOnCategory()` / `Settings.RegisterProxySetting()` / `Settings.OpenToCategory()` — native options panel
