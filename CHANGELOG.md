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
