# HealerWatch - Development Guide

## Overview

HealerWatch is a WoW Classic Anniversary Edition addon that monitors healer mana and raid cooldowns in group content, with click-to-request coordination for cooldowns like Innervate, Rebirth, and Soulstone. It automatically detects healers via talent inspection (since role assignment is unreliable in Classic) and displays their mana percentages with color coding and status indicators. It also tracks raid-wide cooldowns (Innervate, Mana Tide, Rebirth, Soulstone, Symbol of Hope) via combat log. Shadowfiend is seeded for all Priests and shown in the healer row tooltip but not in the cooldown rows section (cdShadowfiend defaults off, no Options GUI toggle). Bloodlust/Heroism and Power Infusion infrastructure exists but is disabled.

## Architecture

**Single-file addon** — all logic in `HealerWatch.lua` (~4840 lines). No XML, no external dependencies.

### Key Systems

1. **Healer Detection Engine** (layered approach):
   - Layer 1: Class filter — only Priest/Druid/Paladin/Shaman can heal
   - Layer 2: Talent inspection via `C_SpecializationInfo.GetSpecializationInfo()` — checks `role` field first, falls back to `HEALING_TALENT_TABS` mapping when `role` is nil (which is the norm in Classic Anniversary). Tracks `inspectConfirmed` flag per member; only re-queues unconfirmed members.
   - Layer 3: Provisional display — 5-man assumes healer-capable = healer; raids use `UnitGroupRolesAssigned()` as a hint while waiting for inspect.
   - Only queues inspects for visible units (`UnitIsVisible()`); resets retry count when out-of-range so they're re-queued on proximity.

2. **Inspection Queue** — async system that queues `NotifyInspect()` calls with 2.5s cooldown, pauses in combat, validates range via `CanInspect()`. Runs on a separate `BackgroundFrame` (always shown) to avoid the hidden-frame OnUpdate deadlock. Periodically re-queues unresolved members.

3. **Raid Cooldown Tracker** — monitors `SPELL_CAST_SUCCESS` (and `SPELL_AURA_APPLIED` for Soulstone) in combat log for key raid cooldowns. Three seeding tiers: class-baseline (Innervate, Rebirth, Soulstone), race-baseline via `RACE_COOLDOWN_SPELLS` (Symbol of Hope for Draenei Priests), and player talent cooldowns (Mana Tide) detected via `IsSpellKnown()`. Local player cooldowns check `GetSpellCooldown()` at seed time for accurate initial state (except Soulstone buff IDs, which are non-castable spells and return unreliable data). Multi-rank spells use canonical spell IDs for consistent keys. Displays with class-colored caster names, spell names, and countdown timers (or green "Ready" with charge count). Supports text, icon, and icon+label display modes. Cross-zone sync via addon messages (SYNC/CD) shares cooldown states between HealerWatch users. Cooldown state is persisted to `db.savedCooldowns` on `PLAYER_LEAVING_WORLD` and restored on next `ScanGroupComposition`, so timers survive `/reload`. Bloodlust/Heroism and Power Infusion infrastructure exists in `RAID_COOLDOWN_SPELLS` but seeding, settings toggles, and options GUI entries are disabled.

4. **Display System** — two independently movable, resizable frames (`HealerWatchFrame` for healer rows, `CooldownFrame` for raid cooldowns) with BackdropTemplate. `splitFrames` setting (default false) controls whether cooldowns render in their own frame or merge into HealerWatchFrame. Persistent pre-created row frames (healer rows parented to HealerWatchFrame; CD rows reparented between HealerWatchFrame and CooldownFrame based on split mode). Resize handles appear on hover, clamped to content-driven minimums. All periodic logic (preview animation, mana updates, display refresh) runs on BackgroundFrame to avoid hidden-frame OnUpdate deadlock. Dead healer rows show an amber pulse when rebirth is available; cooldown rows show an amber "Request" pulse for subgroup-aware spells (Mana Tide, Symbol of Hope) when eligible.

5. **Cooldown Request System** — click-to-whisper system for requesting cooldowns. Clicking an alive healer row opens a context menu with one item per spell (Innervate, Soulstone); clicking auto-routes to the best available caster (longest time since last cast, random if all uncast). Bear-form druids are deprioritized for Innervate/Rebirth — non-bear druids are preferred, with a "if safe to leave bear form" whisper caveat when forced to pick a bear. Includes target selection submenus and subgroup-aware mana checks for targeted spells. Dead healers with a Soulstone or Rebirth buff are whispered directly to accept it (no menu). Dead healers without either buff auto-whisper the best available rebirth druid using the same priority + bear form logic (no menu). Rebirth only appears in menus for dead targets; Soulstone only for alive targets.

6. **Options GUI** — uses the native WoW Settings API (`Settings.RegisterVerticalLayoutCategory` + `Settings.RegisterAddOnCategory`) so options appear in the AddOns tab of the built-in Options panel (ESC > Options > AddOns > HealerWatch). Proxy settings with get/set callbacks to `db`. `/healerwatch` opens directly to the category.

7. **Broadcaster Election** — when multiple players run HealerWatch, only one (the "broadcaster") sends chat warnings. Uses DBM-style deterministic election: leader > assistant > alphabetical name. HELLO/OVERRIDE addon messages discover peers and allow manual override. `/hwatch sync` opens a window showing all HealerWatch users and the current broadcaster. Heartbeat every 30s, stale pruning at 90s.

### Code Sections (in order)

| Section | Lines (approx) | Description |
|---------|----------------|-------------|
| S1      | 1-57           | Header, DEFAULT_SETTINGS (incl. splitFrames, cdFrame* keys, per-cooldown cd* toggles, tooltipAnchor) |
| S2      | 59-66          | Local references (performance caches: band, CombatLogGetCurrentEventInfo, GetPlayerInfoByGUID, SendAddonMessage) |
| S3      | 68-279         | Constants (classes, healing tabs, potions, spell IDs, STATUS_ICONS, RAID_COOLDOWN_SPELLS, CANONICAL_SPELL_ID, COOLDOWN_SETTING_KEY, class/talent/race mappings) |
| S4      | 281-386        | State variables (incl. cdFrame resize state, context menu, subgroup tracking, forward declarations) |
| S5      | 388-571        | Utility functions (iteration, colors, IsInBearForm, IsCasterDead, measurement, status formatting) |
| S5b     | 573-642        | Broadcaster election (rank lookup, register, hello, deterministic elect, override) |
| S6      | 644-841        | Healer detection engine (self-spec, inspect results, inspect queue) |
| S7      | 842-1164       | Group scanning + savedCooldowns restore + class/race cooldown seeding + cross-zone sync + hoisted sort comparators + cooldown grouping |
| S8      | 1166-1203      | Mana updating |
| S9      | 1205-1264      | Buff/status tracking |
| S10     | 1266-1380      | Potion + raid cooldown tracking (CLEU) |
| S11     | 1382-1415      | Warning system |
| S12     | 1416-1557      | HealerWatch display frame + resize handle |
| S13     | 1559-1676      | CooldownFrame + resize handle (split mode) |
| S14     | 1677-1933      | Row frame pool (persistent healer rows, dead pulse overlay, rebirth routing with bear form check) |
| S15     | 1934-2132      | Cooldown row frame pool (persistent, request pulse overlay) |
| S16     | 2133-2831      | Cooldown request menu (one-item-per-spell, bear form deprioritization, target selection, dead healer whisper) |
| S16b    | 2832-3010      | Sync window (broadcaster election UI, `/hwatch sync`) |
| S17     | 3011-3755      | Display update (PrepareHealerRowData, RenderHealerRows, RenderCooldownRows with readyCount, RefreshHealerDisplay, RefreshCooldownDisplay, RefreshMergedDisplay, RefreshDisplay dispatcher) |
| S18     | 3756-3882      | OnUpdate handler (all logic on BackgroundFrame; heartbeat + stale pruning; pulse animations) |
| S19     | 3883-4146      | Preview system (mock healers + mock cooldowns + mock group members, both frames) |
| S20     | 4147-4408      | Options GUI (native Settings API, splitFrames checkbox, per-cooldown toggles, tooltipAnchor dropdown) |
| S21     | 4409-4727      | Event handling (both frame positions restored, PLAYER_LEAVING_WORLD cooldown persistence, broadcaster hello/register on group events, addon message protocol) |
| S22     | 4727-4840      | Slash commands + init (lock/reset apply to both frames, sync command, /hw alias) |

## Features

- Auto-detect healers via talent inspection
- Color-coded mana display (green/yellow/orange/red with configurable thresholds)
- Dead/DC detection with grey indicators
- Dead healer pulse: amber glow on dead healers when a rebirth is available and they have no soulstone/rebirth buff, click to auto-whisper the best rebirth druid (priority-ordered, bear-form aware)
- Dead healer click-to-accept: clicking a dead healer with a Soulstone or Rebirth buff whispers them to accept it (no menu)
- Status indicators: Drinking, Innervate, Mana Tide Totem, Symbol of Hope (text or icon mode, with optional durations)
- Potion cooldown tracking (2min timer from combat log)
- Soulstone status indicator on dead healers (purple "SS"/"Soulstone")
- Raid cooldown tracking with Ready/on-cooldown states: Innervate, Mana Tide, Rebirth, Soulstone, Symbol of Hope (each individually toggleable). Ready/Request labels show charge count, e.g. "Ready (2)"
- Healer row tooltips: hovering a healer shows their personal cooldown timers (Druids: Innervate, Rebirth; Shamans: Mana Tide; Priests: Shadowfiend, Symbol of Hope)
- Cooldown persistence across /reload via SavedVariables (GetTime is continuous across reloads)
- Request pulse: amber "Request" glow on cooldown rows for subgroup-aware spells (Mana Tide, Symbol of Hope) when an eligible healer in the caster's subgroup has low mana
- Cooldown display modes: text only, icons only, or icons with labels
- Click-to-request cooldowns via whisper: healer rows show one menu item per spell (auto-routes to best caster), cooldown rows open caster/target selection. Bear-form druids deprioritized for Innervate/Rebirth. Rebirth scoped to dead targets only, Soulstone scoped to alive targets only
- Average mana across all healers
- Sort healers by lowest mana or alphabetically
- Optional chat warnings at configurable threshold with cooldown
- Single-broadcaster election: when multiple HealerWatch users are in group, only the elected broadcaster sends warnings (leader > assist > alphabetical). Manual override via `/hwatch sync` window.
- Cross-zone cooldown sync: HealerWatch users share cooldown states via addon messages so cooldowns are accurate even when group members are in different zones
- Split or merged display: raid cooldowns in their own frame or combined with healer mana
- Movable, lockable, resizable frames with configurable scale/font/opacity
- Row highlights and header backgrounds
- Live preview system with animated mock data (includes mock group members for Rebirth/Soulstone target menus)
- Native options panel in AddOns tab (ESC > Options > AddOns > HealerWatch, or `/healerwatch`)
- Configurable tooltip anchor (left/right of frame, auto-flips when insufficient screen space)
- Slash command aliases: `/healerwatch`, `/hwatch`, `/hw`

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
