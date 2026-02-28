# HealerWatch

**HealerWatch** tracks healer mana and recovery state in group content. It automatically detects healers via talent inspection and displays color-coded mana percentages with recovery indicators - who's drinking, who has Innervate, whose mana potions are on cooldown. It also tracks the availability of mana recovery cooldowns (Innervate, Mana Tide, Symbol of Hope) and resurrection tools (Rebirth, Soulstone), with click-to-request coordination to get help where it's needed.

Built specifically for **TBC Classic Anniversary**.

![HealerWatch](https://github.com/clearcmos/HealerWatch/blob/main/assets/image1.png?raw=true)

---

## Features

**Healer Mana Monitoring**
- **Smart healer detection** - Automatically identifies healers by inspecting their talent spec. No manual role assignment needed. HealerWatch users share spec info instantly via addon messages; others are confirmed when in inspect range. Unconfirmed healers appear dimmed with a "(?) " indicator.
- **Color-coded mana display** - Shows each healer's mana percentage with color coding (green/yellow/orange/red)
- **Average mana** - Displays the average mana across all healers in the header
- **Dead/DC detection** - Grey indicators for dead or disconnected healers
- **Sorting** - Sort healers by lowest mana first or alphabetically

**Recovery State Tracking**
- **Status indicators** - Shows when healers are Drinking, have Innervate, Symbol of Hope, Mana Tide Totem, or Shadowfiend active, with optional durations. Text or icon display modes.
- **Potion tracking** - Tracks mana/healing potion cooldowns (2 min) via combat log
- **Healer tooltips** - Hover a healer row to see their personal recovery cooldown timers (Druids: Innervate, Rebirth; Shamans: Mana Tide; Priests: Shadowfiend, Symbol of Hope)
- **Soulstone indicator** - Purple status on dead healers who have a Soulstone buff
- **Rebirth indicator** - Orange status on dead healers who have been battle-rezzed

**Recovery Cooldown Availability**
- **Cooldown tracking** - Shows which mana recovery cooldowns (Innervate, Mana Tide, Symbol of Hope) and healer rez tools (Rebirth, Soulstone) are available across the group. "Ready (N)" with charge count or countdown timer. Each individually toggleable. Timers persist across /reload.
- **Cooldown tooltips** - Hover a cooldown row to see all casters for that spell with their individual Ready/timer status
- **Request pulse** - Amber "Request" glow on Mana Tide and Symbol of Hope rows when an eligible healer in the caster's subgroup has low mana
- **Cooldown display modes** - Text only, icons only, or icons with labels

**Click-to-Request Coordination**
- **Request cooldowns** - Click a healer row to request available spells for them (auto-routes to best caster). Click a cooldown row for caster/target selection. Bear-form druids deprioritized for Innervate/Rebirth. Innervate target threshold is configurable (default: show all mana users).
- **Innervate request modes** - Three routing options when clicking an Innervate cooldown row: Target Menu (pick who gets it), Auto: Self (request for yourself), Auto: Lowest Mana (request for the lowest-mana healer)
- **Dead healer pulse** - Amber glow on dead healers when a Rebirth is available (combat only, suppressed after wipes). Click to auto-whisper the best available druid.
- **Dead healer accept** - Clicking a dead healer who has a Soulstone or Rebirth buff whispers them to accept it

**Group Coordination**
- **Chat warnings** - Optional automatic warnings to party/raid when average healer mana drops below a configurable threshold
- **Single-broadcaster election** - When multiple players have HealerWatch, only one sends warnings. Auto-elected by rank, with manual override via `/hwatch sync`
- **Cross-zone sync** - Cooldown timers and healer spec confirmations stay accurate even when group members are in different zones

**Display & Customization**
- **Split or merged display** - Recovery cooldowns in their own frame or combined with healer mana
- **Resizable frames** - Drag the corner handle to resize (appears on hover when unlocked)
- **Configurable** - Font size, scale, opacity, color thresholds, per-cooldown toggles, and more
- **Live preview** - See your changes instantly with animated mock data while configuring

---

## Usage

Type `/healerwatch` to open the options panel.

### Slash Commands

- `/healerwatch` - Open options panel (starts live preview)
- `/healerwatch lock` - Toggle frame lock (drag to reposition when unlocked)
- `/healerwatch test` - Show test data to preview the display
- `/healerwatch sync` - Open broadcaster sync window (see who has HealerWatch and who broadcasts warnings)
- `/healerwatch reset` - Reset all settings to defaults
- `/healerwatch help` - Show available commands
- `/hwatch`, `/hw` - Short aliases for all commands above

---

## Configuration Options

**Display Settings**
- Enable/Disable addon
- Show average mana
- Sort healers by mana or name
- Lock frame position
- Tooltip position (left or right of frame, auto-flips when insufficient space)
- Separate cooldown frame toggle

**Healer Status Indicators**
- Show Drinking, Innervate, Mana Tide, Symbol of Hope, Shadowfiend, Soulstone, Rebirth status
- Show buff durations
- Show potion cooldowns
- Text or icon status display
- Row hover highlight
- Click-to-request cooldowns
- Innervate request mode (Target Menu / Auto: Self / Auto: Lowest Mana)
- Innervate target threshold (% mana to show in request menus, only in Target Menu mode)

**Recovery Cooldowns**
- Show/hide cooldown tracking section
- Per-cooldown toggles (Innervate, Mana Tide, Symbol of Hope, Rebirth, Soulstone)
- Display mode: text, icons, or icons with labels
- Icon size

**Appearance**
- Font size
- Scale
- Display opacity
- Header background

**Chat Warnings**
- Enable/Disable warning messages
- Mana threshold percentage
- Warning cooldown (seconds)

**Mana Color Thresholds**
- Green, yellow, and orange percentage thresholds

---

## License

MIT License - Open source and free to use.

---

## Feedback & Issues

Found a bug or have a suggestion? Post a comment on this addon's CurseForge page, reach me on Discord: `_cmos`, or open an issue on GitHub: https://github.com/clearcmos/HealerWatch
