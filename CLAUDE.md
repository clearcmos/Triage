# HealerWatch - Development Guide

## Overview

HealerWatch is a WoW Classic Anniversary Edition addon that tracks healer mana in group content. It automatically detects healers via talent inspection (since role assignment is unreliable in Classic) and displays their mana percentages with color coding and status indicators. It also tracks raid-wide cooldowns (Innervate, Mana Tide, Bloodlust/Heroism, Power Infusion, Rebirth, Soulstone, Symbol of Hope) via combat log.

## Architecture

**Single-file addon** — all logic in `HealerWatch.lua` (~4150 lines). No XML, no external dependencies.

### Key Systems

1. **Healer Detection Engine** (layered approach):
   - Layer 1: Class filter — only Priest/Druid/Paladin/Shaman can heal
   - Layer 2: Talent inspection via `C_SpecializationInfo.GetSpecializationInfo()` — checks `role` field first, falls back to `HEALING_TALENT_TABS` mapping when `role` is nil (which is the norm in Classic Anniversary). Tracks `inspectConfirmed` flag per member; only re-queues unconfirmed members.
   - Layer 3: Provisional display — 5-man assumes healer-capable = healer; raids use `UnitGroupRolesAssigned()` as a hint while waiting for inspect.
   - Only queues inspects for visible units (`UnitIsVisible()`); resets retry count when out-of-range so they're re-queued on proximity.

2. **Inspection Queue** — async system that queues `NotifyInspect()` calls with 2.5s cooldown, pauses in combat, validates range via `CanInspect()`. Runs on a separate `BackgroundFrame` (always shown) to avoid the hidden-frame OnUpdate deadlock. Periodically re-queues unresolved members.

3. **Raid Cooldown Tracker** — monitors `SPELL_CAST_SUCCESS` (and `SPELL_AURA_APPLIED` for Soulstone) in combat log for key raid cooldowns. Three seeding tiers: class-baseline (Innervate, Rebirth, Soulstone, Bloodlust/Heroism), race-baseline via `RACE_COOLDOWN_SPELLS` (Symbol of Hope for Draenei Priests), and player talent cooldowns (Mana Tide, Power Infusion) detected via `IsSpellKnown()`. Local player cooldowns check `GetSpellCooldown()` at seed time for accurate initial state. Multi-rank spells use canonical spell IDs for consistent keys. Displays with class-colored caster names, spell names, and countdown timers (or green "Ready"). Supports text, icon, and icon+label display modes. Cross-zone sync via addon messages (SYNC/CD) shares cooldown states between HealerWatch users.

4. **Display System** — two independently movable, resizable frames (`HealerWatchFrame` for healer rows, `CooldownFrame` for raid cooldowns) with BackdropTemplate. `splitFrames` setting (default false) controls whether cooldowns render in their own frame or merge into HealerWatchFrame. Object-pooled row frames reparented on acquire. Resize handles appear on hover, clamped to content-driven minimums. All periodic logic (preview animation, mana updates, display refresh) runs on BackgroundFrame to avoid hidden-frame OnUpdate deadlock.

5. **Cooldown Request System** — click-to-whisper system for requesting cooldowns. Clicking a healer row or cooldown row opens a context menu to whisper a request. Includes target selection submenus, caster priority logic (prefers longest time since last cast), and subgroup-aware mana checks for targeted spells.

6. **Options GUI** — uses the native WoW Settings API (`Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnCategory`) so options appear in the AddOns tab of the built-in Options panel (ESC > Options > AddOns > HealerWatch). Proxy settings with get/set callbacks to `db`. `/healerwatch` opens directly to the category.

7. **Broadcaster Election** — when multiple players run HealerWatch, only one (the "broadcaster") sends chat warnings. Uses DBM-style deterministic election: leader > assistant > alphabetical name. HELLO/OVERRIDE addon messages discover peers and allow manual override. `/hwatch sync` opens a window showing all HealerWatch users and the current broadcaster. Heartbeat every 30s, stale pruning at 90s.

### Code Sections (in order)

| Section | Lines (approx) | Description |
|---------|----------------|-------------|
| S1      | 1-58           | Header, DEFAULT_SETTINGS (incl. splitFrames, cdFrame* keys, per-cooldown cd* toggles) |
| S2      | 59-105         | Local performance caches |
| S3      | 106-336        | Constants (classes, healing tabs, potions, raid cooldowns, canonical IDs, COOLDOWN_SETTING_KEY, class/talent/race/tank mappings) |
| S4      | 337-412        | State variables (incl. cdFrame resize state, context menu, subgroup tracking) |
| S5      | 413-581        | Utility functions (iteration, colors, measurement, status formatting) |
| S6      | 582-834        | Healer detection engine (self-spec, inspect results, inspect queue) |
| S7      | 835-1108       | Group scanning + class/race cooldown seeding + cross-zone sync + cooldown grouping |
| S8      | 1109-1147      | Mana updating |
| S9      | 1148-1208      | Buff/status tracking |
| S10     | 1209-1293      | Potion + raid cooldown tracking (CLEU) |
| S11     | 1294-1322      | Warning system |
| S12     | 1323-1455      | HealerWatch display frame + resize handle |
| S13     | 1456-1563      | CooldownFrame + resize handle (split mode) |
| S14     | 1564-1644      | Row frame pool (UIParent-parented, reparented on acquire) |
| S15     | 1645-1714      | Cooldown row frame pool (persistent, reused in place) |
| S16     | 1715-2325      | Cooldown request menu (click-to-whisper, target selection, caster menus) |
| S16b    | 2326-2490      | Sync window (broadcaster election UI, `/hwatch sync`) |
| S17     | 2491-3180      | Display update (PrepareHealerRowData, RenderHealerRows, RenderCooldownRows, RefreshHealerDisplay, RefreshCooldownDisplay, RefreshMergedDisplay, RefreshDisplay dispatcher) |
| S18     | 3181-3290      | OnUpdate handler (all logic on BackgroundFrame; heartbeat + stale pruning; per-frame resize-hover only) |
| S19     | 3291-3530      | Preview system (mock healers + mock cooldowns, both frames) |
| S20     | 3531-3830      | Options GUI (native Settings API, splitFrames checkbox, per-cooldown toggles, broadcaster status) |
| S21     | 3831-3990      | Event handling (both frame positions restored, broadcaster hello/register on group events) |
| S22     | 3991-4100      | Slash commands + init (lock/reset apply to both frames, sync command) |

## Features

- Auto-detect healers via talent inspection
- Color-coded mana display (green/yellow/orange/red with configurable thresholds)
- Dead/DC detection with grey indicators
- Status indicators: Drinking, Innervate, Mana Tide Totem, Symbol of Hope (text or icon mode, with optional durations)
- Potion cooldown tracking (2min timer from combat log)
- Soulstone status indicator on dead healers (purple "SS"/"Soulstone")
- Raid cooldown tracking with Ready/on-cooldown states: Innervate, Mana Tide, Bloodlust/Heroism, Power Infusion, Rebirth, Soulstone, Symbol of Hope (each individually toggleable)
- Cooldown display modes: text only, icons only, or icons with labels
- Click-to-request cooldowns via whisper (healer rows and cooldown rows)
- Average mana across all healers
- Sort healers by lowest mana or alphabetically
- Optional chat warnings at configurable threshold with cooldown
- Single-broadcaster election: when multiple HealerWatch users are in group, only the elected broadcaster sends warnings (leader > assist > alphabetical). Manual override via `/hwatch sync` window.
- Cross-zone cooldown sync: HealerWatch users share cooldown states via addon messages so cooldowns are accurate even when group members are in different zones
- Split or merged display: raid cooldowns in their own frame or combined with healer mana
- Movable, lockable, resizable frames with configurable scale/font/opacity
- Row highlights and header backgrounds
- Live preview system with animated mock data
- Native options panel in AddOns tab (ESC > Options > AddOns > HealerWatch, or `/healerwatch`)

## Development Workflow

1. Edit `HealerWatch.lua` in the AddOns directory
2. `/reload` in-game to test
3. `/healerwatch test` to show fake healer data without a group
4. Copy changes back to `~/git/mine/HealerWatch/`
5. Update version in `.toc` and `CHANGELOG.md`
6. Commit, tag, push to deploy

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
- `C_ChatInfo.SendAddonMessage()` / `C_ChatInfo.RegisterAddonMessagePrefix()` — addon-to-addon communication (cooldown sync + broadcaster election)
- `C_AddOns.GetAddOnMetadata()` / `GetAddOnMetadata()` — addon version retrieval for broadcaster protocol
