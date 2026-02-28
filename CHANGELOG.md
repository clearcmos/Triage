## v1.3.0

### Added
- Shadowfiend status indicator on priest healer rows — shows a 15s countdown when a priest summons Shadowfiend (tracked via combat log, not a buff). Toggleable via `showShadowfiend` in Options.
- Innervate request modes — three routing options when clicking an Innervate cooldown row: Target Menu (pick who gets it), Auto: Self (request for yourself), Auto: Lowest Mana (request for the lowest-mana healer). New dropdown in Options under Click-to-Request.
- Healer status persistence across /reload — confirmed healer spec status no longer resets on reload, preventing "(?) " indicators from reappearing.
- 9th preview healer "Mindmender" (Priest with Shadowfiend active) in demo mode.

### Fixed
- Dead healer amber pulse no longer shows after a wipe — only pulses during combat.
- Average mana no longer includes unconfirmed/provisional healers, preventing false low-mana warnings when inviting out-of-range players.
- Out-of-range healers no longer show 0% mana — keeps previous value until real data arrives.

### Changed
- Replaced string texture paths with numeric FileDataIDs for backdrops and resize handles (performance).
- Hoisted sort comparator and tooltip spell tables to file scope (reduced per-frame allocations).
- Consolidated FONT_PATH constant to a single definition in the constants section.

## v1.2.1

### Fixed
- Cross-zone healer detection: added PARTY_MEMBER_ENABLE event and a delayed rescan after roster updates to catch late-arriving member data, fixing cases where cross-zone party members weren't detected by other HealerWatch users.
- SPEC broadcast missed by late joiners: spec is now re-broadcast every 30s via heartbeat and immediately in response to HELLO messages, so cross-zone HealerWatch users confirm each other without needing inspect proximity.

## v1.2.0

### Added
- Unconfirmed healer indicator: healers whose spec hasn't been verified via talent inspection are shown dimmed with a "(?) " suffix. Hovering shows a tooltip explaining why and how to resolve it (move closer).
- Spec broadcasting via addon messages: HealerWatch users broadcast their healer/non-healer status to the group on join and respec, allowing instant cross-zone confirmation without needing inspect proximity.
- Configurable Innervate request threshold: new slider in Options (under Click-to-Request) controls the mana % below which targets appear in Innervate request menus. Default is 100% (show all mana users). Applies to both healer row and cooldown row click menus.

### Fixed
- Fresh login phantom cooldowns: `GetSpellCooldown` can return false cooldown data before spell state is initialized on login. Innervate/Rebirth would show incorrect timers. Fixed with a three-layer defense: skip `GetSpellCooldown` during fresh login, discard stale savedCooldowns (GetTime epoch resets on client restart), and delayed 5s re-verification via `C_Timer.After`.
- Bear form detection in cooldown request routing used English buff names ("Bear Form", "Dire Bear Form") which would fail on non-English clients. Now uses spell IDs consistently across all code paths.
- Removed duplicate bear form check functions; consolidated into a single shared `IsUnitInBearForm` utility.
- Removed dead code: `UpdateAllHealerBuffs` and `SortBySpellNameAsc` (defined but never called).

## v1.1.0

### Added
- Healer row tooltips: hover a healer to see their personal recovery cooldown timers (Druids: Innervate, Rebirth; Shamans: Mana Tide; Priests: Shadowfiend, Symbol of Hope)
- Cooldown row tooltips: hover a cooldown row to see per-caster status with class-colored names and ready/countdown timers
- Shadowfiend tracking for all Priests (shown in healer row tooltips; hidden from cooldown rows by default)
- Configurable tooltip anchor position (left or right of frame) with auto-flip when insufficient screen space
- Tooltip Position dropdown in Options GUI
- Spec change detection: re-evaluates healer status and cooldowns when player switches specs or respecs

### Changed
- Dead casters filtered from cooldown rows, tooltips, and request menus entirely
- Cooldown rows sorted with subgroup-aware spells (Mana Tide, Symbol of Hope) listed first
- Average mana returns 100% when no healers are tracked (instead of 0%)
- Whisper messages only include mana % when requesting Innervate
- Mana warnings only fire in combat, or out of combat inside dungeons/raids
- Bear form detection uses buff name matching instead of spell IDs

### Fixed
- Tooltip alignment: uniform 8px gap from frame edge on both sides (was 2px left vs 10px right due to row inset asymmetry)
- Tooltips hidden when context menu opens to prevent overlap
- Preview cooldown expiry uses prefix matching instead of hardcoded key list

## v1.0.0

Initial release.
