## v1.1.0

**Raid Cooldown Tracker & Resizable Frame**

- Added raid cooldown tracking: Innervate, Mana Tide Totem, Bloodlust/Heroism, Power Infusion, Divine Intervention, Rebirth, Lay on Hands
- Class-baseline cooldowns pre-seeded as "Ready" on group join; player talent cooldowns detected via IsSpellKnown
- Cooldowns show green "Ready" when available or countdown timer when on cooldown
- Cooldowns displayed below healer mana rows with spell icons, class-colored caster names
- Added resizable frame with drag handle (appears on hover when unlocked), clamped to content-driven minimums
- Preview system now includes mock raid cooldowns with Ready and on-cooldown states

## v1.0.0

**Initial Release**

- Smart healer detection via talent inspection (no manual role assignment needed)
- Per-healer mana display with class-colored names
- Color-coded mana percentages (green/yellow/orange/red with configurable thresholds)
- Average mana display across all healers
- Status indicators: Drinking, Innervate, Mana Tide Totem
- Potion cooldown tracking via combat log (2 min timer)
- Optional chat warnings at configurable mana thresholds
- Movable, lockable display frame
- Full options GUI with sliders, checkboxes, and dropdowns
- Works in party, raid, battlegrounds, and arena
