# HealerMana

**HealerMana** tracks healer mana in group content with smart healer detection via talent inspection.

Built specifically for **TBC Classic Anniversary**.

---

## Features

- **Smart healer detection** - Automatically identifies healers by inspecting their talent spec. No manual role assignment needed.
- **Color-coded mana display** - Shows each healer's mana percentage with color coding (green/yellow/orange/red)
- **Average mana** - Displays the average mana across all healers at the top
- **Status indicators** - Shows when healers are Drinking, have Innervate, or Mana Tide Totem active, with optional durations
- **Potion tracking** - Tracks potion cooldowns (2 min) via combat log
- **Raid cooldown tracking** - Monitors Innervate, Mana Tide, Bloodlust/Heroism, Power Infusion, Divine Intervention, Rebirth, and Lay on Hands. Shows "Ready" or countdown timer per caster. Class-baseline cooldowns detected automatically on group join.
- **Dead/DC detection** - Grey indicators for dead or disconnected healers
- **Chat warnings** - Optional automatic warnings to party/raid when healer mana drops below configurable thresholds
- **Sorting** - Sort healers by lowest mana first or alphabetically
- **Resizable frame** - Drag the corner handle to resize (appears on hover when unlocked)
- **Fully configurable** - Options panel with font size, scale, opacity, color thresholds, warning thresholds, and more
- **Live preview** - See your changes instantly with animated mock data while configuring

---

## Usage

Type `/hm` to open the options panel.

### Slash Commands

- `/hm` - Open options panel
- `/hm lock` - Toggle frame lock (drag to reposition when unlocked)
- `/hm test` - Show test data to preview the display
- `/hm reset` - Reset all settings to defaults
- `/hm help` - Show available commands

---

## Configuration Options

**Display Settings**
- Enable/Disable addon
- Show when solo
- Show average mana
- Show Drinking, Innervate, Mana Tide status
- Show potion cooldowns
- Show raid cooldowns
- Shortened status labels
- Show buff durations
- Lock frame position

**Chat Warnings**
- Enable/Disable warning messages
- Warning cooldown (seconds)
- High, medium, and low mana thresholds

**Appearance**
- Font size
- Scale
- Display opacity
- Options panel opacity

**Mana Color Thresholds**
- Green, yellow, and orange percentage thresholds

**Sorting**
- Lowest mana first or alphabetical

---

## License

MIT License - Open source and free to use.

---

## Feedback & Issues

Found a bug or have a suggestion? Reach me on Discord: `_cmos` or open an issue on GitHub: https://github.com/clearcmos/HealerMana
