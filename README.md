# HealerWatch

## Early Release

This addon is currently experimental and may have bugs. It is being actively developed and improved. If you encounter any issues or have suggestions, please post a comment on the addon page - your feedback helps!

**HealerWatch** monitors healer mana and raid cooldowns in group content, with click-to-request coordination for cooldowns like Innervate, Rebirth, and Soulstone. It automatically detects healers via talent inspection and displays color-coded mana percentages with status indicators. Highly customizable with a live preview.

Built specifically for **TBC Classic Anniversary**.

![HealerWatch](https://github.com/clearcmos/HealerWatch/blob/main/assets/image1.png?raw=true)

---

## Features

- **Smart healer detection** - Automatically identifies healers by inspecting their talent spec. No manual role assignment needed.
- **Color-coded mana display** - Shows each healer's mana percentage with color coding (green/yellow/orange/red)
- **Average mana** - Displays the average mana across all healers at the top
- **Status indicators** - Shows when healers are Drinking, have Innervate, Symbol of Hope, or Mana Tide Totem active, with optional durations. Text or icon display modes.
- **Potion tracking** - Tracks potion cooldowns (2 min) via combat log
- **Soulstone indicator** - Purple "SS" on dead healers who have a soulstone
- **Dead healer pulse** - Amber glow on dead healers when a Rebirth is available and they have no pending rez. Click to auto-whisper the best available druid.
- **Dead healer accept** - Clicking a dead healer who already has a Soulstone or Rebirth buff whispers them to accept it
- **Raid cooldown tracking** - Monitors Innervate, Mana Tide, Rebirth, Soulstone, and Symbol of Hope. Shows "Ready (N)" with charge count or countdown timer. Each cooldown individually toggleable. Timers persist across /reload.
- **Request pulse** - Amber "Request" glow on Mana Tide and Symbol of Hope rows when an eligible healer in the caster's subgroup has low mana
- **Cooldown display modes** - Text only, icons only, or icons with labels
- **Click-to-request cooldowns** - Click a healer row to see available spells (auto-routes to best caster), or click a cooldown row for target selection. Bear-form druids are deprioritized for Innervate/Rebirth. Rebirth targets dead players only; Soulstone targets alive players only
- **Dead/DC detection** - Grey indicators for dead or disconnected healers
- **Chat warnings** - Optional automatic warnings to party/raid when healer mana drops below a configurable threshold
- **Single-broadcaster election** - When multiple players have HealerWatch, only one sends chat warnings. Auto-elected by rank (leader > assist > alphabetical), with manual override via `/hwatch sync`
- **Cross-zone cooldown sync** - HealerWatch users share cooldown states via addon messages, keeping timers accurate even when group members are in different zones
- **Sorting** - Sort healers by lowest mana first or alphabetically
- **Split or merged display** - Raid cooldowns in their own independently movable frame or combined with healer mana
- **Resizable frames** - Drag the corner handle to resize (appears on hover when unlocked)
- **Fully configurable** - Options panel with font size, scale, opacity, color thresholds, per-cooldown toggles, and more
- **Live preview** - See your changes instantly with animated mock data while configuring

---

## Usage

Type `/healerwatch` to open the options panel.

### Slash Commands

- `/healerwatch` - Open options panel
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

**Healer Status Indicators**
- Show Drinking, Innervate, Mana Tide, Symbol of Hope, Soulstone, Rebirth status
- Show buff durations
- Show potion cooldowns
- Text or icon status display
- Click-to-request cooldowns

**Raid Cooldowns**
- Show/hide raid cooldown section
- Per-cooldown toggles (Innervate, Mana Tide, Symbol of Hope, Rebirth, Soulstone)
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
- Broadcaster status and sync window button (when multiple HealerWatch users are present)

**Mana Color Thresholds**
- Green, yellow, and orange percentage thresholds

---

## License

MIT License - Open source and free to use.

---

## Feedback & Issues

Found a bug or have a suggestion? Reach me on Discord: `_cmos` or open an issue on GitHub: https://github.com/clearcmos/HealerWatch
