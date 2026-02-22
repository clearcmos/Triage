# Triage

**Triage** tracks healer mana and raid cooldowns in group content. Automatically detects healers via talent inspection, displays color-coded mana bars with status indicators, and monitors key cooldowns like Innervate, Rebirth, Bloodlust, and more with ready/countdown timers.

Built specifically for **TBC Classic Anniversary**.

---

## Features

- **Smart healer detection** - Automatically identifies healers by inspecting their talent spec. No manual role assignment needed.
- **Color-coded mana display** - Shows each healer's mana percentage with color coding (green/yellow/orange/red)
- **Average mana** - Displays the average mana across all healers at the top
- **Status indicators** - Shows when healers are Drinking, have Innervate, Symbol of Hope, or Mana Tide Totem active, with optional durations. Text or icon display modes.
- **Potion tracking** - Tracks potion cooldowns (2 min) via combat log
- **Soulstone indicator** - Purple "SS" on dead healers who have a soulstone
- **Raid cooldown tracking** - Monitors Innervate, Mana Tide, Bloodlust/Heroism, Power Infusion, Rebirth, Lay on Hands, Soulstone, and Symbol of Hope. Shows "Ready" or countdown timer per caster. Each cooldown individually toggleable.
- **Cooldown display modes** - Text only, icons only, or icons with labels
- **Click-to-request cooldowns** - Click a healer row or cooldown row to whisper a request
- **Dead/DC detection** - Grey indicators for dead or disconnected healers
- **Chat warnings** - Optional automatic warnings to party/raid when healer mana drops below a configurable threshold
- **Sorting** - Sort healers by lowest mana first or alphabetically
- **Split or merged display** - Raid cooldowns in their own independently movable frame or combined with healer mana
- **Resizable frames** - Drag the corner handle to resize (appears on hover when unlocked)
- **Fully configurable** - Options panel with font size, scale, opacity, color thresholds, per-cooldown toggles, and more
- **Live preview** - See your changes instantly with animated mock data while configuring

---

## Usage

Type `/triage` to open the options panel.

### Slash Commands

- `/triage` - Open options panel
- `/triage lock` - Toggle frame lock (drag to reposition when unlocked)
- `/triage test` - Show test data to preview the display
- `/triage reset` - Reset all settings to defaults
- `/triage help` - Show available commands
- `/tr` - Short alias for all commands above

---

## Configuration Options

**Display Settings**
- Enable/Disable addon
- Show average mana
- Sort healers by mana or name
- Lock frame position

**Healer Status Indicators**
- Show Drinking, Innervate, Mana Tide, Symbol of Hope, Soulstone, Rebirth status
- Show buff durations
- Show potion cooldowns
- Text or icon status display
- Click-to-request cooldowns

**Raid Cooldowns**
- Show/hide raid cooldown section
- Per-cooldown toggles (Innervate, Mana Tide, Bloodlust/Heroism, Power Infusion, Symbol of Hope, Rebirth, Lay on Hands, Soulstone)
- Display mode: text, icons, or icons with labels
- Icon size
- Split cooldowns into separate frame

**Appearance**
- Font size
- Scale
- Display opacity
- Row highlights
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

Found a bug or have a suggestion? Reach me on Discord: `_cmos` or open an issue on GitHub: https://github.com/clearcmos/Triage
