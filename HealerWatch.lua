-- HealerWatch: Tracks healer mana in group content with smart healer detection
-- For WoW Classic Anniversary Edition (2.5.5)

local addonName = ...

--------------------------------------------------------------------------------
-- Configuration Defaults
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    enabled = true,
    locked = false,
    fontSize = 12,
    scale = 1.0,
    bgOpacity = 0.6,
    frameX = nil,
    frameY = nil,
    showDrinking = true,
    showInnervate = true,
    showManaTide = true,
    showSoulstone = true,
    showRebirth = true,
    showSymbolOfHope = true,
    showPotionCooldown = true,
    showAverageMana = true,
    showStatusDuration = false,
    sendWarnings = false,
    warningThreshold = 10,
    warningCooldown = 30,
    colorThresholdGreen = 75,
    colorThresholdYellow = 50,
    colorThresholdOrange = 25,
    sortBy = "mana",
    showRaidCooldowns = true,
    splitFrames = false,
    frameWidth = nil,
    frameHeight = nil,
    cdFrameX = nil,
    cdFrameY = nil,
    cdFrameWidth = nil,
    cdFrameHeight = nil,
    statusIcons = true,
    cooldownDisplayMode = "icons_labels",  -- "text", "icons", "icons_labels"
    iconSize = 16,
    showRowHighlight = true,
    enableCdRequest = true,
    innervateRequestThreshold = 100,
    headerBackground = true,
    cdInnervate = true,
    cdManaTide = true,
    -- cdBloodlustHeroism = true,  -- disabled for now
    -- cdPowerInfusion = true,    -- disabled for now
    cdSymbolOfHope = true,
    cdRebirth = true,
    cdSoulstone = true,
    cdShadowfiend = false,
    tooltipAnchor = "left",  -- "left" or "right"; adapts to screen space regardless
};

--------------------------------------------------------------------------------
-- Local References
--------------------------------------------------------------------------------

local band = bit.band;
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo;
local GetPlayerInfoByGUID = GetPlayerInfoByGUID;
local SendAddonMessage = C_ChatInfo.SendAddonMessage;

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local HEALER_CAPABLE_CLASSES = {
    ["PRIEST"] = true,
    ["DRUID"] = true,
    ["PALADIN"] = true,
    ["SHAMAN"] = true,
};

-- Which talent tab index is a healing spec, per class (TBC Classic)
local HEALING_TALENT_TABS = {
    ["PRIEST"] = { [1] = true, [2] = true },  -- Discipline, Holy
    ["DRUID"] = { [3] = true },                -- Restoration
    ["PALADIN"] = { [1] = true },              -- Holy
    ["SHAMAN"] = { [3] = true },               -- Restoration
};

local POTION_SPELL_IDS = {
    -- Mana Potions
    [437] = true,      -- Minor Mana Potion
    [438] = true,      -- Lesser Mana Potion
    [2023] = true,     -- Mana Potion
    [11903] = true,    -- Greater Mana Potion
    [17530] = true,    -- Superior Mana Potion
    [17531] = true,    -- Major Mana Potion
    [28499] = true,    -- Super Mana Potion
    -- Healing Potions
    [439] = true,      -- Minor Healing Potion
    [440] = true,      -- Lesser Healing Potion
    [441] = true,      -- Healing Potion
    [2024] = true,     -- Greater Healing Potion
    [4042] = true,     -- Superior Healing Potion
    [17534] = true,    -- Major Healing Potion
    [28495] = true,    -- Super Healing Potion
    -- Protection Potions
    [17543] = true,    -- Greater Fire Protection Potion
    [17548] = true,    -- Greater Shadow Protection Potion
    [17546] = true,    -- Greater Nature Protection Potion
    [17544] = true,    -- Greater Frost Protection Potion
    [17549] = true,    -- Greater Arcane Protection Potion
    -- Utility Potions
    [2379] = true,     -- Swiftness Potion
    [3169] = true,     -- Limited Invulnerability Potion
    [6615] = true,     -- Free Action Potion
    -- TBC Potions
    [28507] = true,    -- Haste Potion
    [28508] = true,    -- Destruction Potion
    [28511] = true,    -- Ironshield Potion
    -- Dark Rune / Demonic Rune
    [17484] = true,    -- Dark Rune (mana from health)
    [16666] = true,    -- Demonic Rune
    -- Fel Mana Potion
    [38929] = true,    -- Fel Mana Potion
};

local POTION_COOLDOWN_DURATION = 120;
local POWER_TYPE_MANA = 0;

-- Spell names (localized via GetSpellInfo with English fallbacks)
local INNERVATE_SPELL_ID = 29166;
local INNERVATE_SPELL_NAME = GetSpellInfo(29166) or "Innervate";
local MANA_TIDE_BUFF_NAME = GetSpellInfo(16191) or "Mana Tide Totem";
local DRINKING_SPELL_NAME = GetSpellInfo(430) or "Drink";
local MANA_TIDE_CAST_SPELL_ID = 16190;
local BLOODLUST_SPELL_ID = 2825;
local HEROISM_SPELL_ID = 32182;
local POWER_INFUSION_SPELL_ID = 10060;
local SYMBOL_OF_HOPE_SPELL_ID = 32548;
-- Shadowfiend spell ID: 34433 (inlined to avoid 200-local limit)
local SYMBOL_OF_HOPE_SPELL_NAME = GetSpellInfo(32548) or "Symbol of Hope";
-- Soulstone Resurrection buff IDs (applied to target when warlock uses soulstone)
local SOULSTONE_BUFF_IDS = {
    [20707] = true,    -- Soulstone Resurrection (Minor)
    [20762] = true,    -- Soulstone Resurrection (Lesser)
    [20763] = true,    -- Soulstone Resurrection (Greater)
    [20764] = true,    -- Soulstone Resurrection (Major)
    [20765] = true,    -- Soulstone Resurrection (Master)
    [27239] = true,    -- Soulstone Resurrection (TBC)
};
local SOULSTONE_SPELL_NAME = GetSpellInfo(20707) or "Soulstone Resurrection";

-- Rebirth spell IDs (all ranks)
local REBIRTH_SPELL_IDS = {
    [20484] = true,  -- Rank 1
    [20739] = true,  -- Rank 2
    [20742] = true,  -- Rank 3
    [20747] = true,  -- Rank 4
    [20748] = true,  -- Rank 5
    [26994] = true,  -- Rank 6
};

-- Status icon textures for icon mode (keyed by status identifier)
local STATUS_ICONS = {
    drinking     = select(3, GetSpellInfo(430))   or 132794,   -- Drink
    innervate    = select(3, GetSpellInfo(29166))  or 136048,   -- Innervate
    manaTide     = select(3, GetSpellInfo(16191))  or 135861,   -- Mana Tide Totem
    soulstone    = select(3, GetSpellInfo(20707))  or 136210,   -- Soulstone Resurrection
    rebirth      = select(3, GetSpellInfo(20484))  or 136080,   -- Rebirth
    symbolOfHope = select(3, GetSpellInfo(32548))  or 135982,   -- Symbol of Hope
    potion       = 134762,                                       -- Generic potion (inv_potion_137)
};

-- Raid-wide cooldown spells tracked at the bottom of the display
-- Multi-rank spells share a single info table referenced by all rank IDs
local RAID_COOLDOWN_SPELLS = {
    [INNERVATE_SPELL_ID] = {
        name = INNERVATE_SPELL_NAME,
        icon = select(3, GetSpellInfo(INNERVATE_SPELL_ID)) or 136048,
        duration = 360,
    },
    [MANA_TIDE_CAST_SPELL_ID] = {
        name = MANA_TIDE_BUFF_NAME,
        icon = select(3, GetSpellInfo(MANA_TIDE_CAST_SPELL_ID)) or 135861,
        duration = 300,
    },
    [BLOODLUST_SPELL_ID] = {
        name = GetSpellInfo(BLOODLUST_SPELL_ID) or "Bloodlust",
        icon = select(3, GetSpellInfo(BLOODLUST_SPELL_ID)) or 136012,
        duration = 600,
    },
    [HEROISM_SPELL_ID] = {
        name = GetSpellInfo(HEROISM_SPELL_ID) or "Heroism",
        icon = select(3, GetSpellInfo(HEROISM_SPELL_ID)) or 132998,
        duration = 600,
    },
    [POWER_INFUSION_SPELL_ID] = {
        name = GetSpellInfo(POWER_INFUSION_SPELL_ID) or "Power Infusion",
        icon = select(3, GetSpellInfo(POWER_INFUSION_SPELL_ID)) or 135939,
        duration = 180,
    },
    [SYMBOL_OF_HOPE_SPELL_ID] = {
        name = SYMBOL_OF_HOPE_SPELL_NAME,
        icon = select(3, GetSpellInfo(SYMBOL_OF_HOPE_SPELL_ID)) or 135982,
        duration = 300,
    },
    [34433] = {
        name = GetSpellInfo(34433) or "Shadowfiend",
        icon = select(3, GetSpellInfo(34433)) or 136199,
        duration = 300,
    },
};

-- Rebirth (6 ranks, all same CD) — shared info referenced by each rank ID
local rebirthInfo = {
    name = GetSpellInfo(20484) or "Rebirth",
    icon = select(3, GetSpellInfo(20484)) or 136080,
    duration = 1200,
};
RAID_COOLDOWN_SPELLS[20484] = rebirthInfo;  -- Rank 1
RAID_COOLDOWN_SPELLS[20739] = rebirthInfo;  -- Rank 2
RAID_COOLDOWN_SPELLS[20742] = rebirthInfo;  -- Rank 3
RAID_COOLDOWN_SPELLS[20747] = rebirthInfo;  -- Rank 4
RAID_COOLDOWN_SPELLS[20748] = rebirthInfo;  -- Rank 5
RAID_COOLDOWN_SPELLS[26994] = rebirthInfo;  -- Rank 6

-- Soulstone Resurrection (6 ranks, tracked via SPELL_AURA_APPLIED on target)
-- When the buff is applied, the warlock's Create Soulstone is on CD for 30 min
local soulstoneInfo = {
    name = "Soulstone",
    icon = select(3, GetSpellInfo(20707)) or 136210,
    duration = 1800,
};
RAID_COOLDOWN_SPELLS[20707] = soulstoneInfo;  -- Minor
RAID_COOLDOWN_SPELLS[20762] = soulstoneInfo;  -- Lesser
RAID_COOLDOWN_SPELLS[20763] = soulstoneInfo;  -- Greater
RAID_COOLDOWN_SPELLS[20764] = soulstoneInfo;  -- Major
RAID_COOLDOWN_SPELLS[20765] = soulstoneInfo;  -- Master
RAID_COOLDOWN_SPELLS[27239] = soulstoneInfo;  -- TBC

-- Canonical spell ID for multi-rank spells (any rank → rank 1 for consistent keys)
local CANONICAL_SPELL_ID = {
    [20484] = 20484, [20739] = 20484, [20742] = 20484,
    [20747] = 20484, [20748] = 20484, [26994] = 20484,  -- Rebirth
    [20707] = 20707, [20762] = 20707, [20763] = 20707,
    [20764] = 20707, [20765] = 20707, [27239] = 20707,  -- Soulstone
};

-- Per-cooldown toggle keys (canonical spell ID → db setting key)
local COOLDOWN_SETTING_KEY = {
    [INNERVATE_SPELL_ID]           = "cdInnervate",
    [MANA_TIDE_CAST_SPELL_ID]     = "cdManaTide",
    -- [BLOODLUST_SPELL_ID]          = "cdBloodlustHeroism",  -- disabled for now
    -- [HEROISM_SPELL_ID]            = "cdBloodlustHeroism",  -- disabled for now
    -- [POWER_INFUSION_SPELL_ID]     = "cdPowerInfusion",     -- disabled for now
    [SYMBOL_OF_HOPE_SPELL_ID]     = "cdSymbolOfHope",
    [34433]        = "cdShadowfiend",
    [20484]                        = "cdRebirth",
    [20707]                        = "cdSoulstone",
};

-- Class-baseline raid cooldowns (every member of the class has these)
local CLASS_COOLDOWN_SPELLS = {
    ["DRUID"] = { INNERVATE_SPELL_ID, 20484 },                   -- Innervate, Rebirth
    -- Paladin: no class-baseline cooldowns tracked
    ["PRIEST"] = { 34433 },                         -- Shadowfiend
    ["WARLOCK"] = { 20707 },                                      -- Soulstone
    -- Shaman BL/Heroism handled separately (faction-dependent)
};

-- Talent-based cooldowns to check for player via IsSpellKnown
local TALENT_COOLDOWN_SPELLS = {
    ["SHAMAN"] = { MANA_TIDE_CAST_SPELL_ID },
    -- ["PRIEST"] = { POWER_INFUSION_SPELL_ID },  -- disabled for now
};

-- Race-baseline cooldowns (seeded for all members of matching class+race)
local RACE_COOLDOWN_SPELLS = {
    -- Symbol of Hope is a Draenei Priest racial (all Draenei priests have it)
    ["PRIEST-Draenei"] = { SYMBOL_OF_HOPE_SPELL_ID },
};

--------------------------------------------------------------------------------
-- State Variables
--------------------------------------------------------------------------------

local db;

-- Healer tracking: healers[guid] = { unit, name, classFile, isHealer, manaPercent, ... }
local healers = {};

-- Inspection queue
local inspectQueue = {};
local inspectPending = nil;
local lastInspectTime = 0;
local INSPECT_COOLDOWN = 2.5;
local inspectPaused = false;
local inspectRetries = {};       -- guid -> attempt count
local INSPECT_MAX_RETRIES = 3;
local INSPECT_REQUEUE_INTERVAL = 5.0;

-- Addon communication for cross-zone cooldown sync
local ADDON_MSG_PREFIX = "HealerWatch";
local playerGUID;
local isFreshLogin = false;  -- true during fresh login (not /reload), cleared after delayed CD verify

-- Broadcaster election system
local ADDON_VERSION = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or
                      GetAddOnMetadata and GetAddOnMetadata(addonName, "Version") or "1.0.0";
local healerWatchUsers = {};           -- name -> { name, version, guid, unit, lastSeen, rank }
local overrideBroadcaster = nil;  -- manual override target name (nil = auto-elect)
local HEARTBEAT_INTERVAL = 30;
local STALE_TIMEOUT = 90;
local heartbeatElapsed = 0;
local lastHelloTime = 0;
local HELLO_REPLY_COOLDOWN = 5;

-- Persistent healer row frames (never recycled)
local activeRows = {};

-- Reusable table caches (avoid per-frame allocations)
local sortedCache = {};
local rowDataCache = {};
local statusLabelParts = {};
local statusDurParts = {};
local statusIconParts = {};

-- Raid cooldown tracking
local raidCooldowns = {};
local activeCdRows = {};
local savedRaidCooldowns = nil;

-- Spell-grouped cooldown cache
local spellGroupCache = {};
local sortedSpellGroupCache = {};
local deadCache = {};

-- Reusable scan tables
local seenGUIDs = {};
local syncParts = {};

-- Subgroup tracking: guid -> subgroup number (1-8)
local memberSubgroups = {};
local savedMemberSubgroups = nil;

-- Context menu state
local contextMenuFrame;
local contextMenuVisible = false;

-- Cooldown frame state
local cdContentMinWidth = 120;
local cdContentMinHeight = 30;
local cdResizeState = { dragging = false, cursorX = nil, cursorY = nil, w = nil, h = nil };

-- Warning state
local lastWarningTime = 0;
local warningTriggered = false;

-- Whisper throttle (misclick protection)
local lastWhisperTime = 0;
local WHISPER_COOLDOWN = 1.0;

-- Menu dismiss suppression (prevents click-through when closing menu)
local menuDismissTime = 0;

-- Delayed rescan dedup flag (for cross-zone late-arriving member data)
local pendingRescan = false;

-- Update throttling
local updateElapsed = 0;
local UPDATE_INTERVAL = 0.2;
local inspectElapsed = 0;

-- Preview state
local previewActive = false;
local savedHealers = nil;
local previewGroupMembers = {};

-- Forward declarations
local RefreshDisplay;
local ScanGroupComposition;
local StartPreview;
local StopPreview;
local UpdateCdResizeHandleVisibility;
local HideContextMenu;
local ShowCooldownRequestMenu;
local ShowCdRowRequestMenu;
local CD_REQUEST_CONFIG;
local ShowTargetSubmenu;
local SyncFrame;
local RefreshSyncFrame;

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local groupMembersCache = {};

local function IterateGroupMembers()
    wipe(groupMembersCache);
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i;
            if UnitExists(unit) then
                tinsert(groupMembersCache, unit);
            end
        end
    elseif IsInGroup() then
        tinsert(groupMembersCache, "player");
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i;
            if UnitExists(unit) then
                tinsert(groupMembersCache, unit);
            end
        end
    end
    return groupMembersCache;
end

local function GetManaColor(percent)
    if percent >= db.colorThresholdGreen then
        return 0.0, 1.0, 0.0;
    elseif percent >= db.colorThresholdYellow then
        return 1.0, 1.0, 0.0;
    elseif percent >= db.colorThresholdOrange then
        return 1.0, 0.5, 0.0;
    else
        return 1.0, 0.0, 0.0;
    end
end

local function GetClassColor(classFile)
    local color = RAID_CLASS_COLORS[classFile];
    if color then
        return color.r, color.g, color.b;
    end
    return 1, 1, 1;
end

-- Check if a caster (by GUID) is dead. Checks healers table first, falls back to group scan.
local function IsCasterDead(guid)
    if previewActive then
        local hdata = healers[guid];
        return hdata and hdata.manaPercent == -2;
    end
    local hdata = healers[guid];
    if hdata and hdata.unit and UnitExists(hdata.unit) then
        return UnitIsDeadOrGhost(hdata.unit);
    end
    for _, u in ipairs(IterateGroupMembers()) do
        if UnitGUID(u) == guid then
            return UnitIsDeadOrGhost(u);
        end
    end
    return false;
end

local function IsUnitInBearForm(guid)
    local units = IterateGroupMembers();
    for _, unit in ipairs(units) do
        if UnitGUID(unit) == guid then
            for i = 1, 40 do
                local bname, _, _, _, _, _, _, _, _, bsid = UnitBuff(unit, i);
                if not bname then break; end
                if bsid == 5487 or bsid == 9634 then return true; end
            end
            return false;
        end
    end
    return false;
end

-- Measure helper: get pixel width of a string at a given font size
-- Measurement FontString lives on UIParent (always visible = reliable GetStringWidth)
local measureFS;
local function MeasureText(text, fontSize)
    if not measureFS then
        measureFS = UIParent:CreateFontString(nil, "OVERLAY");
    end
    measureFS:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE");
    measureFS:SetText(text);
    return measureFS:GetStringWidth();
end

local function FormatDuration(expirationTime, now)
    if not db.showStatusDuration or expirationTime == 0 then return ""; end
    local remaining = expirationTime - now;
    if remaining <= 0 then return ""; end
    return format("%ds", floor(remaining));
end

-- Returns: statusLabel, statusDuration, statusIconData
-- statusLabel/statusDuration: colored text strings for text mode
-- statusIconData: array of {icon, duration} entries for icon mode
local function FormatStatusText(data)
    wipe(statusLabelParts);
    wipe(statusDurParts);
    wipe(statusIconParts);
    local now = GetTime();

    -- Priority order: Soulstone (dead) > Rebirth (dead) > Innervate > Symbol of Hope > Mana Tide > Drinking > Potion

    -- Soulstone shown on dead healers (manaPercent == -2)
    if db.showSoulstone and data.hasSoulstone and data.manaPercent == -2 then
        tinsert(statusLabelParts, "|cff9482c9Soulstone|r");
        tinsert(statusDurParts, "");
        tinsert(statusIconParts, { icon = STATUS_ICONS.soulstone, duration = "" });
    end

    -- Rebirth shown on dead healers who have a pending battle rez
    if db.showRebirth and data.hasRebirth and data.manaPercent == -2 then
        tinsert(statusLabelParts, "|cffff7d0aRebirth|r");
        tinsert(statusDurParts, "");
        tinsert(statusIconParts, { icon = STATUS_ICONS.rebirth, duration = "" });
    end

    if data.hasInnervate and db.showInnervate then
        tinsert(statusLabelParts, "|cffba55d3Innervate|r");
        local dur = FormatDuration(data.innervateExpiry, now);
        tinsert(statusDurParts, dur);
        tinsert(statusIconParts, { icon = STATUS_ICONS.innervate, duration = dur });
    end
    if data.hasSymbolOfHope and db.showSymbolOfHope then
        tinsert(statusLabelParts, "|cffffff80Symbol of Hope|r");
        local dur = FormatDuration(data.symbolOfHopeExpiry, now);
        tinsert(statusDurParts, dur);
        tinsert(statusIconParts, { icon = STATUS_ICONS.symbolOfHope, duration = dur });
    end
    if data.hasManaTide and db.showManaTide then
        tinsert(statusLabelParts, "|cff00c8ffMana Tide|r");
        local dur = FormatDuration(data.manaTideExpiry, now);
        tinsert(statusDurParts, dur);
        tinsert(statusIconParts, { icon = STATUS_ICONS.manaTide, duration = dur });
    end
    if data.isDrinking and db.showDrinking then
        tinsert(statusLabelParts, "|cff55ccffDrinking|r");
        local dur = FormatDuration(data.drinkExpiry, now);
        tinsert(statusDurParts, dur);
        tinsert(statusIconParts, { icon = STATUS_ICONS.drinking, duration = dur });
    end
    if db.showPotionCooldown and data.potionExpiry and data.potionExpiry > now
            and not (data.hasInnervate and db.showInnervate)
            and not (data.hasSymbolOfHope and db.showSymbolOfHope)
            and not (data.hasManaTide and db.showManaTide)
            and not (data.isDrinking and db.showDrinking) then
        local remaining = floor(data.potionExpiry - now);
        local minutes = floor(remaining / 60);
        local seconds = remaining % 60;
        tinsert(statusLabelParts, "|cffffaa00Potion|r");
        local dur = format("%d:%02d", minutes, seconds);
        tinsert(statusDurParts, dur);
        tinsert(statusIconParts, { icon = STATUS_ICONS.potion, duration = dur });
    end

    if #statusLabelParts == 0 then return "", "", statusIconParts; end

    -- Primary status: label in first FontString, duration in second
    local labelStr = statusLabelParts[1];
    local durStr = statusDurParts[1];

    -- Additional statuses: append full "Label Dur" to duration string
    for i = 2, #statusLabelParts do
        local extra = statusLabelParts[i];
        if statusDurParts[i] ~= "" then
            extra = extra .. " " .. statusDurParts[i];
        end
        if durStr ~= "" then
            durStr = durStr .. "  " .. extra;
        else
            durStr = extra;
        end
    end

    return labelStr, durStr, statusIconParts;
end

--------------------------------------------------------------------------------
-- Broadcaster Election
--------------------------------------------------------------------------------

local function GetPlayerRank(unit)
    if IsInRaid() then
        local raidIndex = tonumber(unit:match("(%d+)$"));
        if raidIndex then
            local _, rank = GetRaidRosterInfo(raidIndex);
            if rank == 2 then return 2; end  -- leader
            if rank == 1 then return 1; end  -- assistant
        end
        return 0;
    else
        if UnitIsGroupLeader(unit) then return 2; end
        return 0;
    end
end

local function RegisterSelf()
    local name = UnitName("player");
    if not name then return; end
    local guid = UnitGUID("player");
    local rank = 0;
    -- Find our unit token in group for rank lookup
    for _, u in ipairs(IterateGroupMembers()) do
        if UnitIsUnit(u, "player") then
            rank = GetPlayerRank(u);
            break;
        end
    end
    healerWatchUsers[name] = {
        name = name,
        version = ADDON_VERSION,
        guid = guid,
        lastSeen = GetTime(),
        rank = rank,
    };
end

local function BroadcastHello()
    if not IsInGroup() then return; end
    local dist = IsInRaid() and "RAID" or "PARTY";
    SendAddonMessage(ADDON_MSG_PREFIX, "HELLO:" .. ADDON_VERSION, dist);
    lastHelloTime = GetTime();
end

local function GetBroadcaster()
    -- Manual override takes priority (if the target is still known)
    if overrideBroadcaster and healerWatchUsers[overrideBroadcaster] then
        return overrideBroadcaster;
    end

    -- Deterministic election: highest rank wins, then alphabetical name
    local best = nil;
    for _, user in pairs(healerWatchUsers) do
        if not best then
            best = user;
        elseif user.rank > best.rank then
            best = user;
        elseif user.rank == best.rank and user.name < best.name then
            best = user;
        end
    end
    return best and best.name or UnitName("player");
end

local function IsBroadcaster()
    return GetBroadcaster() == UnitName("player");
end

--------------------------------------------------------------------------------
-- Healer Detection Engine
--------------------------------------------------------------------------------

local function IsHealerCapableClass(unit)
    local _, classFile = UnitClass(unit);
    return HEALER_CAPABLE_CLASSES[classFile] == true, classFile;
end

local function QueueInspect(unit)
    local guid = UnitGUID(unit);
    if not guid then return; end

    -- Don't queue if already queued
    for _, entry in ipairs(inspectQueue) do
        if entry.guid == guid then return; end
    end

    -- Don't re-queue if inspect is confirmed or class can't heal
    local data = healers[guid];
    if data then
        if data.inspectConfirmed or not HEALER_CAPABLE_CLASSES[data.classFile] then return; end
    end

    tinsert(inspectQueue, { unit = unit, guid = guid });
end

local function CheckSelfSpec()
    local guid = UnitGUID("player");
    if not guid or not healers[guid] then return; end

    local _, classFile = UnitClass("player");
    if not HEALER_CAPABLE_CLASSES[classFile] then
        healers[guid].isHealer = false;
        healers[guid].inspectConfirmed = true;
        return;
    end

    -- Use C_SpecializationInfo with activeGroup (the correct Classic Anniversary API)
    local activeGroup = 1;
    if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
        local ok, result = pcall(C_SpecializationInfo.GetActiveSpecGroup, false, false);
        if ok and result then activeGroup = result; end
    end

    local maxPoints = 0;
    local primaryTab = nil;
    local primaryRole = nil;

    for i = 1, 3 do
        local ok, _, _, _, _, role, _, pointsSpent =
            pcall(C_SpecializationInfo.GetSpecializationInfo, i, false, false, nil, nil, activeGroup);
        if ok and pointsSpent and pointsSpent > maxPoints then
            maxPoints = pointsSpent;
            primaryTab = i;
            primaryRole = role;
        end
    end

    if maxPoints > 0 and primaryTab then
        healers[guid].inspectConfirmed = true;
        if primaryRole == "HEALER" then
            healers[guid].isHealer = true;
        elseif primaryRole then
            healers[guid].isHealer = false;
        else
            local healTabs = HEALING_TALENT_TABS[classFile];
            healers[guid].isHealer = (healTabs and healTabs[primaryTab]) or false;
        end
    else
        healers[guid].isHealer = (GetNumGroupMembers() <= 5);
    end
end

-- Broadcast own spec to other HealerWatch users via addon message
local function BroadcastSpec()
    if not IsInGroup() then return; end
    local guid = UnitGUID("player");
    if not guid or not healers[guid] then return; end
    local data = healers[guid];
    if not data.inspectConfirmed then return; end
    local isHealer = data.isHealer and "1" or "0";
    local dist = IsInRaid() and "RAID" or "PARTY";
    SendAddonMessage(ADDON_MSG_PREFIX, "SPEC:" .. isHealer, dist);
end

local function ProcessInspectResult(inspecteeGUID)
    if inspectPending ~= inspecteeGUID then return; end

    local data = healers[inspecteeGUID];
    if not data or not data.unit then
        ClearInspectPlayer();
        inspectPending = nil;
        return;
    end

    local _, classFile = UnitClass(data.unit);
    if not classFile then
        ClearInspectPlayer();
        inspectPending = nil;
        return;
    end

    -- Use C_SpecializationInfo with activeGroup (the correct Classic Anniversary API)
    local activeGroup = 1;
    if C_SpecializationInfo and C_SpecializationInfo.GetActiveSpecGroup then
        local ok, result = pcall(C_SpecializationInfo.GetActiveSpecGroup, true, false);
        if ok and result then activeGroup = result; end
    end

    local maxPoints = 0;
    local primaryTab = nil;
    local primaryRole = nil;

    for i = 1, 3 do
        local ok, _, _, _, _, role, _, pointsSpent =
            pcall(C_SpecializationInfo.GetSpecializationInfo, i, true, false, nil, nil, activeGroup);
        if ok and pointsSpent and pointsSpent > maxPoints then
            maxPoints = pointsSpent;
            primaryTab = i;
            primaryRole = role;
        end
    end

    if not HEALER_CAPABLE_CLASSES[classFile] then
        ClearInspectPlayer();
        inspectPending = nil;
        return;
    end

    if maxPoints > 0 and primaryTab then
        data.inspectConfirmed = true;
        if primaryRole == "HEALER" then
            data.isHealer = true;
        elseif primaryRole then
            data.isHealer = false;
        else
            local healTabs = HEALING_TALENT_TABS[classFile];
            data.isHealer = (healTabs and healTabs[primaryTab]) or false;
        end
    else
        -- API returned no data; assume healer in small groups, retry in raids
        if GetNumGroupMembers() <= 5 then
            data.isHealer = true;
        end
        -- Don't mark inspectConfirmed — keep retrying
    end

    ClearInspectPlayer();
    inspectPending = nil;
end

local INSPECT_TIMEOUT = 10;

local function ProcessInspectQueue()
    if inspectPaused then return; end

    local now = GetTime();

    -- Clear stale pending inspect (INSPECT_READY may have been lost)
    if inspectPending then
        if now - lastInspectTime > INSPECT_TIMEOUT then
            ClearInspectPlayer();
            inspectPending = nil;
        else
            return;
        end
    end

    if #inspectQueue == 0 then return; end
    if now - lastInspectTime < INSPECT_COOLDOWN then return; end

    while #inspectQueue > 0 do
        local entry = tremove(inspectQueue, 1);
        local guid = entry.guid;
        local unit = entry.unit;

        if UnitExists(unit) and UnitGUID(unit) == guid and UnitIsVisible(unit)
            and CheckInteractDistance(unit, 4) then
            local canInspect = false;
            local ok, result = pcall(CanInspect, unit);
            if ok then canInspect = result; end

            if canInspect then
                NotifyInspect(unit);
                inspectPending = guid;
                lastInspectTime = now;
                return;
            end
        end

        -- Track failed attempts and apply fallback
        inspectRetries[guid] = (inspectRetries[guid] or 0) + 1;
        if inspectRetries[guid] >= INSPECT_MAX_RETRIES then
            local data = healers[guid];
            if data and data.isHealer == nil then
                -- In 5-man groups, assume healer-capable classes are healers
                -- In raids, leave as nil (don't show unconfirmed)
                if GetNumGroupMembers() <= 5 then
                    data.isHealer = true;
                else
                    data.isHealer = false;
                end
            end
            -- Reset retries so we keep trying when they come in range
            inspectRetries[guid] = 0;
        end
    end
end

--------------------------------------------------------------------------------
-- Group Scanning
--------------------------------------------------------------------------------

-- Seed a single cooldown entry; for the local player, check GetSpellCooldown()
local function SeedCooldown(guid, name, classFile, spellId, unit)
    local canonical = CANONICAL_SPELL_ID[spellId] or spellId;
    local key = guid .. "-" .. canonical;
    local isLocalPlayer = unit and UnitIsUnit(unit, "player");

    -- For non-local players, don't overwrite existing entries (may have CLEU/sync data).
    -- For local player, always re-seed so GetSpellCooldown overrides stale savedCooldowns
    -- (savedCooldowns use GetTime()-based expiryTimes that become invalid across client restarts).
    if raidCooldowns[key] and not isLocalPlayer then return; end

    local cdInfo = RAID_COOLDOWN_SPELLS[spellId];
    if not cdInfo then return; end

    local expiryTime = 0;  -- default: "Ready"

    -- For the local player, check actual cooldown state.
    -- Skip on fresh login — GetSpellCooldown can return phantom cooldowns before spell data
    -- is fully synced from the server. A delayed re-verification runs after login stabilizes.
    -- Skip Soulstone buff IDs — they are non-castable spell IDs with unreliable CD data.
    if isLocalPlayer and not isFreshLogin and not SOULSTONE_BUFF_IDS[spellId] then
        local start, dur = GetSpellCooldown(spellId);
        if start and start > 0 and dur and dur > 1.5 then  -- ignore GCD
            expiryTime = start + dur;
        end
    end

    raidCooldowns[key] = {
        sourceGUID = guid,
        name = name or "Unknown",
        classFile = classFile or "UNKNOWN",
        spellId = canonical,
        icon = cdInfo.icon,
        spellName = cdInfo.name,
        expiryTime = expiryTime,
    };
end

ScanGroupComposition = function()
    -- Restore cooldown state saved before last /reload.
    -- GetTime() is continuous across reloads so expiryTime values remain valid.
    -- On fresh login (client restart), GetTime() resets so saved values are invalid — discard.
    if db and db.savedCooldowns and not isFreshLogin then
        for key, entry in pairs(db.savedCooldowns) do
            if not raidCooldowns[key] then
                raidCooldowns[key] = entry;
            end
        end
    end
    db.savedCooldowns = nil;

    -- Clear inspect queue (will re-queue unresolved members below)
    wipe(inspectQueue);
    -- Don't wipe inspectRetries — preserve progress across roster updates
    -- Don't clear inspectPending — let in-flight inspect complete

    wipe(seenGUIDs);
    local units = IterateGroupMembers();

    for _, unit in ipairs(units) do
        local guid = UnitGUID(unit);
        if guid then
            seenGUIDs[guid] = true;

            -- Track subgroup for cooldown scope checks
            if IsInRaid() then
                local raidIndex = tonumber(unit:match("(%d+)$"));
                if raidIndex then
                    local _, _, subgroup = GetRaidRosterInfo(raidIndex);
                    memberSubgroups[guid] = subgroup or 1;
                end
            else
                memberSubgroups[guid] = 1;
            end

            local isCapable, classFile = IsHealerCapableClass(unit);
            local name = UnitName(unit);
            local assignedHealer = (UnitGroupRolesAssigned(unit) == "HEALER");

            if not healers[guid] then
                healers[guid] = {
                    guid = guid,
                    unit = unit,
                    name = name or "Unknown",
                    classFile = classFile or "UNKNOWN",
                    isHealer = nil,
                    inspectConfirmed = false,
                    manaPercent = 100,
                    isDrinking = false,
                    hasInnervate = false,
                    hasManaTide = false,
                    hasSoulstone = false,
                    hasRebirth = false,
                    hasSymbolOfHope = false,
                    symbolOfHopeExpiry = 0,
                    potionExpiry = 0,
                };
            end

            -- Always update unit token and name (can change on roster change)
            healers[guid].unit = unit;
            healers[guid].name = name or healers[guid].name;
            if classFile then healers[guid].classFile = classFile; end

            if not isCapable then
                healers[guid].isHealer = false;
                healers[guid].inspectConfirmed = true;
            elseif not healers[guid].inspectConfirmed then
                -- Self: check directly, others: queue inspect
                if UnitIsUnit(unit, "player") then
                    CheckSelfSpec();
                    BroadcastSpec();
                else
                    -- Provisional display while waiting for talent inspect:
                    -- 5-man: assume healer-capable = healer
                    -- Raid: use assigned role as hint (better than showing nothing)
                    if healers[guid].isHealer == nil then
                        if GetNumGroupMembers() <= 5 then
                            healers[guid].isHealer = true;
                        elseif assignedHealer then
                            healers[guid].isHealer = true;
                        end
                    end
                    -- Only queue inspect if unit is visible (in range)
                    if UnitIsVisible(unit) then
                        QueueInspect(unit);
                    end
                end
            end
        end
    end

    -- Remove entries for players who left
    for guid in pairs(healers) do
        if not seenGUIDs[guid] then
            healers[guid] = nil;
            inspectRetries[guid] = nil;
        end
    end
    for guid in pairs(memberSubgroups) do
        if not seenGUIDs[guid] then
            memberSubgroups[guid] = nil;
        end
    end

    -- Remove raid cooldowns from departed members
    for key, entry in pairs(raidCooldowns) do
        if not seenGUIDs[entry.sourceGUID] then
            raidCooldowns[key] = nil;
        end
    end

    -- Remove healerWatchUsers entries for players who left
    for uname, udata in pairs(healerWatchUsers) do
        if udata.guid and not seenGUIDs[udata.guid] then
            healerWatchUsers[uname] = nil;
            if overrideBroadcaster == uname then
                overrideBroadcaster = nil;
            end
        end
    end

    -- Seed "Ready" cooldowns for class-baseline abilities
    for _, unit in ipairs(units) do
        local guid = UnitGUID(unit);
        if guid then
            local _, classFile = UnitClass(unit);
            local name = UnitName(unit);

            -- Class-baseline cooldowns
            local spells = CLASS_COOLDOWN_SPELLS[classFile];
            if spells then
                for _, spellId in ipairs(spells) do
                    SeedCooldown(guid, name, classFile, spellId, unit);
                end
            end

            -- Shaman: BL/Heroism based on faction (disabled for now)
            -- if classFile == "SHAMAN" then
            --     local faction = UnitFactionGroup(unit);
            --     local blSpellId = (faction == "Horde") and BLOODLUST_SPELL_ID or HEROISM_SPELL_ID;
            --     SeedCooldown(guid, name, classFile, blSpellId, unit);
            -- end

            -- Race-baseline cooldowns (e.g., Symbol of Hope for Draenei Priests)
            local _, raceFile = UnitRace(unit);
            if raceFile and classFile then
                local raceSpells = RACE_COOLDOWN_SPELLS[classFile .. "-" .. raceFile];
                if raceSpells then
                    for _, spellId in ipairs(raceSpells) do
                        SeedCooldown(guid, name, classFile, spellId, unit);
                    end
                end
            end

            -- Player only: check talent-based cooldowns via IsSpellKnown
            if UnitIsUnit(unit, "player") then
                local talentSpells = TALENT_COOLDOWN_SPELLS[classFile];
                if talentSpells then
                    for _, spellId in ipairs(talentSpells) do
                        if IsSpellKnown(spellId) then
                            SeedCooldown(guid, name, classFile, spellId, unit);
                        end
                    end
                end
            end
        end
    end

    -- Broadcast our cooldown states to the group so cross-zone members get accurate data
    if playerGUID and IsInGroup() then
        wipe(syncParts);
        for key, entry in pairs(raidCooldowns) do
            if entry.sourceGUID == playerGUID then
                local remaining = 0;
                if entry.expiryTime > 0 then
                    remaining = floor(entry.expiryTime - GetTime());
                    if remaining < 0 then remaining = 0; end
                end
                tinsert(syncParts, format("%d:%d", entry.spellId, remaining));
            end
        end
        if #syncParts > 0 then
            local dist = IsInRaid() and "RAID" or "PARTY";
            SendAddonMessage(ADDON_MSG_PREFIX, "SYNC:" .. table.concat(syncParts, ","), dist);
        end
    end

end

-- Hoisted sort comparators (avoid closure allocation per call)
local function SortByManaAsc(a, b)
    return a.manaPercent < b.manaPercent;
end
local function SortByNameAsc(a, b)
    return a.name < b.name;
end
local function SortCastersByAvailability(a, b)
    if a.isDead ~= b.isDead then return not a.isDead; end
    local now = GetTime();
    local aReady = (not a.isDead and a.expiryTime <= now);
    local bReady = (not b.isDead and b.expiryTime <= now);
    if aReady ~= bReady then return aReady; end
    if not a.isDead and not b.isDead then
        return a.expiryTime < b.expiryTime;
    end
    return a.name < b.name;
end
-- Sort comparator inlined at call site (cannot hoist to file scope due to 200-local limit)

local function GetSortedHealers()
    wipe(sortedCache);
    for guid, data in pairs(healers) do
        if data.isHealer then
            tinsert(sortedCache, data);
        end
    end

    if db.sortBy == "mana" then
        sort(sortedCache, SortByManaAsc);
    else
        sort(sortedCache, SortByNameAsc);
    end

    return sortedCache;
end

-- Group raidCooldowns by spellId, sort casters by availability (alive+ready first)
-- Returns sorted array of { spellId, spellName, icon, casters = { {guid, name, classFile, expiryTime, isDead}, ... } }
local function GroupCooldownsBySpell()
    wipe(spellGroupCache);
    wipe(sortedSpellGroupCache);

    -- Cache dead status per GUID to avoid repeated group scans
    wipe(deadCache);

    for _, entry in pairs(raidCooldowns) do
        local sid = entry.spellId;
        local settingKey = COOLDOWN_SETTING_KEY[sid];
        if not (settingKey and not db[settingKey]) then
            if not spellGroupCache[sid] then
                spellGroupCache[sid] = {
                    spellId = sid,
                    spellName = entry.spellName,
                    icon = entry.icon,
                    casters = {},
                };
            end
            local guid = entry.sourceGUID;
            if deadCache[guid] == nil then
                deadCache[guid] = IsCasterDead(guid);
            end
            -- Skip dead casters entirely
            if not deadCache[guid] then
                tinsert(spellGroupCache[sid].casters, {
                    guid = guid,
                    name = entry.name,
                    classFile = entry.classFile,
                    expiryTime = entry.expiryTime,
                    lastCastTime = entry.lastCastTime or 0,
                    isDead = false,
                });
            end
        end
    end

    for _, group in pairs(spellGroupCache) do
        if #group.casters > 0 then
            -- Sort casters: alive+ready first, then shortest CD
            sort(group.casters, SortCastersByAvailability);
            tinsert(sortedSpellGroupCache, group);
        end
    end

    sort(sortedSpellGroupCache, function(a, b)
        local aReq = CD_REQUEST_CONFIG[a.spellId] and CD_REQUEST_CONFIG[a.spellId].subgroupAware;
        local bReq = CD_REQUEST_CONFIG[b.spellId] and CD_REQUEST_CONFIG[b.spellId].subgroupAware;
        if aReq ~= bReq then return aReq and true or false; end
        return a.spellName < b.spellName;
    end);

    return sortedSpellGroupCache;
end

--------------------------------------------------------------------------------
-- Mana Updating
--------------------------------------------------------------------------------

local function UpdateManaValues()
    for guid, data in pairs(healers) do
        if data.isHealer and data.unit and UnitExists(data.unit) then
            if UnitIsDeadOrGhost(data.unit) then
                data.manaPercent = -2;
            elseif not UnitIsConnected(data.unit) then
                data.manaPercent = -1;
            else
                -- No longer dead — clear pending rebirth
                if data.hasRebirth then data.hasRebirth = false; end
                local manaMax = UnitPowerMax(data.unit, POWER_TYPE_MANA);
                if manaMax > 0 then
                    local mana = UnitPower(data.unit, POWER_TYPE_MANA);
                    data.manaPercent = floor((mana / manaMax) * 100 + 0.5);
                else
                    data.manaPercent = 0;
                end
            end
        end
    end
end

local function GetAverageMana()
    local total = 0;
    local count = 0;
    for guid, data in pairs(healers) do
        if data.isHealer and data.manaPercent >= 0 then
            total = total + data.manaPercent;
            count = count + 1;
        end
    end
    if count == 0 then return 100; end
    return floor(total / count + 0.5);
end

--------------------------------------------------------------------------------
-- Buff/Status Tracking
--------------------------------------------------------------------------------

local function UpdateUnitBuffs(unit)
    local guid = UnitGUID(unit);
    if not guid then return; end
    local data = healers[guid];
    if not data or not data.isHealer then return; end

    data.isDrinking = false;
    data.hasInnervate = false;
    data.hasManaTide = false;
    data.hasSoulstone = false;
    data.hasSymbolOfHope = false;
    data.drinkExpiry = 0;
    data.innervateExpiry = 0;
    data.manaTideExpiry = 0;
    data.symbolOfHopeExpiry = 0;

    local i = 1;
    while true do
        local name, _, _, _, _, expirationTime, _, _, _, spellId = UnitBuff(unit, i);
        if not name then break; end

        if name == DRINKING_SPELL_NAME or name == "Drink" or name == "Food & Drink" then
            data.isDrinking = true;
            data.drinkExpiry = expirationTime or 0;
        end

        if spellId == INNERVATE_SPELL_ID or name == INNERVATE_SPELL_NAME then
            data.hasInnervate = true;
            data.innervateExpiry = expirationTime or 0;
        end

        if name == MANA_TIDE_BUFF_NAME or name == "Mana Tide" then
            data.hasManaTide = true;
            data.manaTideExpiry = expirationTime or 0;
        end

        if SOULSTONE_BUFF_IDS[spellId] or name == SOULSTONE_SPELL_NAME then
            data.hasSoulstone = true;
        end

        if spellId == SYMBOL_OF_HOPE_SPELL_ID or name == SYMBOL_OF_HOPE_SPELL_NAME then
            data.hasSymbolOfHope = true;
            data.symbolOfHopeExpiry = expirationTime or 0;
        end

        i = i + 1;
    end
end

--------------------------------------------------------------------------------
-- Potion Tracking via Combat Log
--------------------------------------------------------------------------------

local function ProcessCombatLog()
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, _, _, _, spellId =
        CombatLogGetCurrentEventInfo();

    -- Potion tracking (SPELL_CAST_SUCCESS only)
    if subevent == "SPELL_CAST_SUCCESS" then
        if POTION_SPELL_IDS[spellId] then
            local data = healers[sourceGUID];
            if data and data.isHealer then
                data.potionExpiry = GetTime() + POTION_COOLDOWN_DURATION;
            end
        end
    end

    -- Raid cooldown tracking (SPELL_CAST_SUCCESS for most, SPELL_AURA_APPLIED for soulstone)
    local cdInfo = RAID_COOLDOWN_SPELLS[spellId];
    if cdInfo and db.showRaidCooldowns and COOLDOWN_SETTING_KEY[CANONICAL_SPELL_ID[spellId] or spellId] then
        local now = GetTime();
        if subevent == "SPELL_CAST_SUCCESS" and not SOULSTONE_BUFF_IDS[spellId] then
            if sourceFlags and band(sourceFlags, 0x07) ~= 0 then
                local _, engClass = GetPlayerInfoByGUID(sourceGUID);
                local canonical = CANONICAL_SPELL_ID[spellId] or spellId;
                local key = sourceGUID .. "-" .. canonical;
                local existing = raidCooldowns[key];
                if existing then
                    existing.name = sourceName or "Unknown";
                    existing.classFile = engClass or "UNKNOWN";
                    existing.icon = cdInfo.icon;
                    existing.spellName = cdInfo.name;
                    existing.expiryTime = now + cdInfo.duration;
                    existing.lastCastTime = now;
                else
                    raidCooldowns[key] = {
                        sourceGUID = sourceGUID,
                        name = sourceName or "Unknown",
                        classFile = engClass or "UNKNOWN",
                        spellId = canonical,
                        icon = cdInfo.icon,
                        spellName = cdInfo.name,
                        expiryTime = now + cdInfo.duration,
                        lastCastTime = now,
                    };
                end
                -- Broadcast to group if this is the player's own cast
                if sourceGUID == playerGUID and IsInGroup() then
                    local dist = IsInRaid() and "RAID" or "PARTY";
                    SendAddonMessage(ADDON_MSG_PREFIX, format("CD:%d:%d", canonical, cdInfo.duration), dist);
                end
            end
        elseif subevent == "SPELL_AURA_APPLIED" and SOULSTONE_BUFF_IDS[spellId] then
            -- Soulstone: source is the warlock, dest gets the buff
            if sourceFlags and band(sourceFlags, 0x07) ~= 0 then
                local _, engClass = GetPlayerInfoByGUID(sourceGUID);
                local canonical = CANONICAL_SPELL_ID[spellId] or spellId;
                local key = sourceGUID .. "-" .. canonical;
                local existing = raidCooldowns[key];
                if existing then
                    existing.name = sourceName or "Unknown";
                    existing.classFile = engClass or "UNKNOWN";
                    existing.icon = cdInfo.icon;
                    existing.spellName = cdInfo.name;
                    existing.expiryTime = now + cdInfo.duration;
                    existing.lastCastTime = now;
                else
                    raidCooldowns[key] = {
                        sourceGUID = sourceGUID,
                        name = sourceName or "Unknown",
                        classFile = engClass or "UNKNOWN",
                        spellId = canonical,
                        icon = cdInfo.icon,
                        spellName = cdInfo.name,
                        expiryTime = now + cdInfo.duration,
                        lastCastTime = now,
                    };
                end
                -- Broadcast to group if this is the player's own cast
                if sourceGUID == playerGUID and IsInGroup() then
                    local dist = IsInRaid() and "RAID" or "PARTY";
                    SendAddonMessage(ADDON_MSG_PREFIX, format("CD:%d:%d", canonical, cdInfo.duration), dist);
                end
            end
            -- Mark the healer who received the soulstone
            if destGUID then
                local data = healers[destGUID];
                if data and data.isHealer then
                    data.hasSoulstone = true;
                end
            end
        end
    end

    -- Clear soulstone on healer when buff is removed
    if subevent == "SPELL_AURA_REMOVED" and SOULSTONE_BUFF_IDS[spellId] then
        if destGUID then
            local data = healers[destGUID];
            if data then
                data.hasSoulstone = false;
            end
        end
    end

    -- Mark healer as having pending Rebirth (cast on them while dead)
    if subevent == "SPELL_CAST_SUCCESS" and REBIRTH_SPELL_IDS[spellId] then
        if destGUID then
            local data = healers[destGUID];
            if data and data.isHealer then
                data.hasRebirth = true;
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Warning System
--------------------------------------------------------------------------------

local function CheckManaWarnings()
    if not db.sendWarnings then return; end
    if not IsInGroup() then return; end
    if not IsBroadcaster() then return; end

    -- Only warn in combat, or out of combat inside a dungeon/raid
    if not InCombatLockdown() then
        local _, instanceType = GetInstanceInfo();
        if instanceType ~= "party" and instanceType ~= "raid" then return; end
    end

    local now = GetTime();
    if now - lastWarningTime < db.warningCooldown then return; end

    local avgMana = GetAverageMana();

    -- Reset warning if mana recovered above threshold
    if avgMana > db.warningThreshold then
        warningTriggered = false;
        return;
    end

    if warningTriggered then return; end

    local chatType = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY");
    SendChatMessage(format("[HealerWatch] Healer mana low! Average: %d%%", avgMana), chatType);
    warningTriggered = true;
    lastWarningTime = now;
end

--------------------------------------------------------------------------------
-- Display Frame
--------------------------------------------------------------------------------

local HealerWatchFrame = CreateFrame("Frame", "HealerWatchMainFrame", UIParent, "BackdropTemplate");
HealerWatchFrame:SetSize(220, 30);
HealerWatchFrame:SetFrameStrata("MEDIUM");
HealerWatchFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, tileSize = 16,
});
HealerWatchFrame:SetBackdropColor(0, 0, 0, 0.7);
HealerWatchFrame:SetClampedToScreen(true);
HealerWatchFrame:SetMovable(true);
HealerWatchFrame:EnableMouse(true);
HealerWatchFrame:Hide();

-- Header background highlight
HealerWatchFrame.titleBg = HealerWatchFrame:CreateTexture(nil, "BORDER");
HealerWatchFrame.titleBg:SetColorTexture(0.2, 0.2, 0.2, 0.5);
HealerWatchFrame.titleBg:Hide();

-- Title / average mana text
HealerWatchFrame.title = HealerWatchFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
HealerWatchFrame.title:SetPoint("TOPLEFT", 10, -8);
HealerWatchFrame.title:SetJustifyH("LEFT");

-- Separator line below header
HealerWatchFrame.separator = HealerWatchFrame:CreateTexture(nil, "ARTWORK");
HealerWatchFrame.separator:SetHeight(1);
HealerWatchFrame.separator:SetColorTexture(0.5, 0.5, 0.5, 0.4);
HealerWatchFrame.separator:Hide();

-- Cooldown section title (merged mode)
HealerWatchFrame.cdTitleBg = HealerWatchFrame:CreateTexture(nil, "BORDER");
HealerWatchFrame.cdTitleBg:SetColorTexture(0.2, 0.2, 0.2, 0.5);
HealerWatchFrame.cdTitleBg:Hide();

HealerWatchFrame.cdTitle = HealerWatchFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
HealerWatchFrame.cdTitle:SetJustifyH("LEFT");
HealerWatchFrame.cdTitle:SetText("Cooldowns");
HealerWatchFrame.cdTitle:Hide();

-- Separator line above cooldown section
HealerWatchFrame.cdSeparator = HealerWatchFrame:CreateTexture(nil, "ARTWORK");
HealerWatchFrame.cdSeparator:SetHeight(1);
HealerWatchFrame.cdSeparator:SetColorTexture(0.5, 0.5, 0.5, 0.4);
HealerWatchFrame.cdSeparator:Hide();

-- Drag handlers
HealerWatchFrame:RegisterForDrag("LeftButton");
HealerWatchFrame:SetScript("OnDragStart", function(self)
    if db and not db.locked then
        self:StartMoving();
    end
end);
HealerWatchFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing();
    if db then
        -- Re-anchor at TOPLEFT/BOTTOMLEFT for consistent save/restore
        local left, top = self:GetLeft(), self:GetTop();
        self:ClearAllPoints();
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top);
        db.frameX = left;
        db.frameY = top;
    end
end);

-- Resize handle (appears on hover when unlocked)
local resizeHandle = CreateFrame("Frame", nil, HealerWatchFrame);
resizeHandle:SetSize(16, 16);
resizeHandle:SetPoint("BOTTOMRIGHT", 0, 0);
resizeHandle:EnableMouse(true);
resizeHandle.tex = resizeHandle:CreateTexture(nil, "OVERLAY");
resizeHandle.tex:SetAllPoints();
resizeHandle.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up");
resizeHandle.tex:SetVertexColor(0.6, 0.6, 0.6);
resizeHandle:Hide();
HealerWatchFrame.resizeHandle = resizeHandle;

local WIDTH_MIN = 120;
local WIDTH_MAX = 600;
local HEIGHT_MIN = 30;
local HEIGHT_MAX = 600;
local contentMinWidth = WIDTH_MIN;
local contentMinHeight = HEIGHT_MIN;
local resizeStartCursorX, resizeStartCursorY, resizeStartW, resizeStartH;
local resizeDragging = false;

resizeHandle:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return; end
    resizeDragging = true;
    self.tex:SetVertexColor(1, 1, 1);
    local effectiveScale = HealerWatchFrame:GetEffectiveScale();
    resizeStartCursorX, resizeStartCursorY = GetCursorPosition();
    resizeStartW = HealerWatchFrame:GetWidth();
    resizeStartH = HealerWatchFrame:GetHeight();

    self:SetScript("OnUpdate", function()
        local cursorX, cursorY = GetCursorPosition();
        local dx = (cursorX - resizeStartCursorX) / effectiveScale;
        local dy = (resizeStartCursorY - cursorY) / effectiveScale;
        local newW = max(contentMinWidth, min(WIDTH_MAX, resizeStartW + dx));
        local newH = max(contentMinHeight, min(HEIGHT_MAX, resizeStartH + dy));
        db.frameWidth = floor(newW + 0.5);
        db.frameHeight = floor(newH + 0.5);
        HealerWatchFrame:SetWidth(db.frameWidth);
        HealerWatchFrame:SetHeight(db.frameHeight);
    end);
end);

resizeHandle:SetScript("OnMouseUp", function(self)
    resizeDragging = false;
    self.tex:SetVertexColor(0.6, 0.6, 0.6);
    self:SetScript("OnUpdate", nil);
end);

local function UpdateResizeHandleVisibility()
    if db and db.locked then
        if not resizeDragging then
            resizeHandle:Hide();
        end
        return;
    end
    if resizeDragging then return; end
    if HealerWatchFrame:IsMouseOver() or resizeHandle:IsMouseOver() then
        resizeHandle:Show();
    else
        resizeHandle:Hide();
    end
end

HealerWatchFrame:HookScript("OnEnter", function() UpdateResizeHandleVisibility(); end);
HealerWatchFrame:HookScript("OnLeave", function() UpdateResizeHandleVisibility(); end);
resizeHandle:SetScript("OnEnter", function()
    if not resizeDragging then resizeHandle.tex:SetVertexColor(1, 1, 1); end
    UpdateResizeHandleVisibility();
end);
resizeHandle:SetScript("OnLeave", function()
    if not resizeDragging then resizeHandle.tex:SetVertexColor(0.6, 0.6, 0.6); end
    UpdateResizeHandleVisibility();
end);

--------------------------------------------------------------------------------
-- Cooldown Display Frame (split mode)
--------------------------------------------------------------------------------

local CooldownFrame = CreateFrame("Frame", "HealerWatchCooldownFrame", UIParent, "BackdropTemplate");
CooldownFrame:SetSize(220, 30);
CooldownFrame:SetFrameStrata("MEDIUM");
CooldownFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, tileSize = 16,
});
CooldownFrame:SetBackdropColor(0, 0, 0, 0.7);
CooldownFrame:SetClampedToScreen(true);
CooldownFrame:SetMovable(true);
CooldownFrame:EnableMouse(true);
CooldownFrame:Hide();

-- Header background highlight
CooldownFrame.titleBg = CooldownFrame:CreateTexture(nil, "BORDER");
CooldownFrame.titleBg:SetColorTexture(0.2, 0.2, 0.2, 0.5);
CooldownFrame.titleBg:Hide();

-- Title for cooldown frame
CooldownFrame.title = CooldownFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
CooldownFrame.title:SetPoint("TOPLEFT", 10, -8);
CooldownFrame.title:SetJustifyH("LEFT");
CooldownFrame.title:SetText("Cooldowns");

-- Separator line below header
CooldownFrame.separator = CooldownFrame:CreateTexture(nil, "ARTWORK");
CooldownFrame.separator:SetHeight(1);
CooldownFrame.separator:SetColorTexture(0.5, 0.5, 0.5, 0.4);
CooldownFrame.separator:Hide();

-- Drag handlers
CooldownFrame:RegisterForDrag("LeftButton");
CooldownFrame:SetScript("OnDragStart", function(self)
    if db and not db.locked then
        self:StartMoving();
    end
end);
CooldownFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing();
    if db then
        local left, top = self:GetLeft(), self:GetTop();
        self:ClearAllPoints();
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top);
        db.cdFrameX = left;
        db.cdFrameY = top;
    end
end);

-- Resize handle for cooldown frame (appears on hover when unlocked)
local cdResizeHandle = CreateFrame("Frame", nil, CooldownFrame);
cdResizeHandle:SetSize(16, 16);
cdResizeHandle:SetPoint("BOTTOMRIGHT", 0, 0);
cdResizeHandle:EnableMouse(true);
cdResizeHandle.tex = cdResizeHandle:CreateTexture(nil, "OVERLAY");
cdResizeHandle.tex:SetAllPoints();
cdResizeHandle.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up");
cdResizeHandle.tex:SetVertexColor(0.6, 0.6, 0.6);
cdResizeHandle:Hide();
CooldownFrame.resizeHandle = cdResizeHandle;

cdResizeHandle:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return; end
    cdResizeState.dragging = true;
    self.tex:SetVertexColor(1, 1, 1);
    local effectiveScale = CooldownFrame:GetEffectiveScale();
    cdResizeState.cursorX, cdResizeState.cursorY = GetCursorPosition();
    cdResizeState.w = CooldownFrame:GetWidth();
    cdResizeState.h = CooldownFrame:GetHeight();

    self:SetScript("OnUpdate", function()
        local cursorX, cursorY = GetCursorPosition();
        local dx = (cursorX - cdResizeState.cursorX) / effectiveScale;
        local dy = (cdResizeState.cursorY - cursorY) / effectiveScale;
        local newW = max(cdContentMinWidth, min(WIDTH_MAX, cdResizeState.w + dx));
        local newH = max(cdContentMinHeight, min(HEIGHT_MAX, cdResizeState.h + dy));
        db.cdFrameWidth = floor(newW + 0.5);
        db.cdFrameHeight = floor(newH + 0.5);
        CooldownFrame:SetWidth(db.cdFrameWidth);
        CooldownFrame:SetHeight(db.cdFrameHeight);
    end);
end);

cdResizeHandle:SetScript("OnMouseUp", function(self)
    cdResizeState.dragging = false;
    self.tex:SetVertexColor(0.6, 0.6, 0.6);
    self:SetScript("OnUpdate", nil);
end);

UpdateCdResizeHandleVisibility = function()
    if db and db.locked then
        if not cdResizeState.dragging then
            cdResizeHandle:Hide();
        end
        return;
    end
    if cdResizeState.dragging then return; end
    if CooldownFrame:IsMouseOver() or cdResizeHandle:IsMouseOver() then
        cdResizeHandle:Show();
    else
        cdResizeHandle:Hide();
    end
end

CooldownFrame:HookScript("OnEnter", function() UpdateCdResizeHandleVisibility(); end);
CooldownFrame:HookScript("OnLeave", function() UpdateCdResizeHandleVisibility(); end);
cdResizeHandle:SetScript("OnEnter", function()
    if not cdResizeState.dragging then cdResizeHandle.tex:SetVertexColor(1, 1, 1); end
    UpdateCdResizeHandleVisibility();
end);
cdResizeHandle:SetScript("OnLeave", function()
    if not cdResizeState.dragging then cdResizeHandle.tex:SetVertexColor(0.6, 0.6, 0.6); end
    UpdateCdResizeHandleVisibility();
end);

--------------------------------------------------------------------------------
-- Row Frame Pool
--------------------------------------------------------------------------------

local function CreateRowFrame()
    local frame = CreateFrame("Button", nil, HealerWatchFrame);
    frame:SetSize(400, 16);
    frame:RegisterForClicks("AnyDown");
    frame:Hide();

    -- Row highlight (gated on db.showRowHighlight)
    local hl = frame:CreateTexture(nil, "BACKGROUND");
    hl:SetAllPoints();
    hl:SetColorTexture(1, 1, 1, 0.1);
    hl:Hide();
    frame.highlight = hl;

    frame:SetScript("OnEnter", function(self)
        if db and db.showRowHighlight then self.highlight:Show(); end
        if contextMenuVisible then return; end
        -- Recovery cooldown tooltip
        local guid = self.healerGUID;
        local hdata = guid and healers[guid];
        if not hdata then return; end
        -- Unconfirmed healer: show explanatory tooltip instead of cooldown tooltip
        if not hdata.inspectConfirmed then
            if not self.healerTooltip then
                local tip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate");
                tip:SetFrameStrata("TOOLTIP");
                tip:SetFrameLevel(200);
                tip:SetBackdrop({
                    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 12,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 },
                });
                tip:SetBackdropColor(0, 0, 0, 0.9);
                tip:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8);
                tip:SetClampedToScreen(true);
                tip:Hide();
                tip.rows = {};
                self.healerTooltip = tip;
            end
            local tip = self.healerTooltip;
            local fontSize = 12;
            local rowHeight = fontSize + 4;
            local pad = 6;
            -- Ensure we have enough FontStrings for 3 lines
            for i = 1, 3 do
                if not tip.rows[i] then
                    tip.rows[i] = {};
                    tip.rows[i].spell = tip:CreateFontString(nil, "OVERLAY");
                    tip.rows[i].spell:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE");
                    tip.rows[i].spell:SetJustifyH("LEFT");
                    tip.rows[i].status = tip:CreateFontString(nil, "OVERLAY");
                    tip.rows[i].status:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE");
                    tip.rows[i].status:SetJustifyH("LEFT");
                end
            end
            -- Line 1: healer name in class color
            local cr, cg, cb = GetClassColor(hdata.classFile);
            tip.rows[1].spell:SetText(hdata.name);
            tip.rows[1].spell:SetTextColor(cr, cg, cb);
            tip.rows[1].spell:ClearAllPoints();
            tip.rows[1].spell:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -pad);
            tip.rows[1].spell:Show();
            tip.rows[1].status:Hide();
            -- Line 2: "Spec Unconfirmed"
            tip.rows[2].spell:SetText("Spec Unconfirmed");
            tip.rows[2].spell:SetTextColor(0.7, 0.7, 0.7);
            tip.rows[2].spell:ClearAllPoints();
            tip.rows[2].spell:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -pad - rowHeight);
            tip.rows[2].spell:Show();
            tip.rows[2].status:Hide();
            -- Line 3: explanation
            tip.rows[3].spell:SetText("Move closer to inspect talents.");
            tip.rows[3].spell:SetTextColor(0.5, 0.5, 0.5);
            tip.rows[3].spell:ClearAllPoints();
            tip.rows[3].spell:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, -pad - rowHeight * 2);
            tip.rows[3].spell:Show();
            tip.rows[3].status:Hide();
            -- Hide any extra rows from previous cooldown tooltip use
            for i = 4, #tip.rows do
                tip.rows[i].spell:Hide();
                tip.rows[i].status:Hide();
            end
            -- Size and position
            local maxW = 0;
            for i = 1, 3 do
                local w = tip.rows[i].spell:GetStringWidth();
                if w > maxW then maxW = w; end
            end
            tip:SetSize(maxW + pad * 2, pad * 2 + 3 * rowHeight);
            tip:ClearAllPoints();
            local parent = self:GetParent() or self;
            local frameLeft = parent:GetLeft() or self:GetLeft();
            local screenW = GetScreenWidth() * self:GetEffectiveScale();
            local frameRight = parent:GetRight() or self:GetRight();
            local spaceLeft = frameLeft and (frameLeft * self:GetEffectiveScale()) or 0;
            local spaceRight = frameRight and (screenW - frameRight * self:GetEffectiveScale()) or 0;
            local preferLeft = db.tooltipAnchor == "left";
            if preferLeft then
                if spaceLeft >= (maxW + pad * 2) + 8 then
                    tip:SetPoint("RIGHT", self, "LEFT", -18, 0);
                else
                    tip:SetPoint("LEFT", self, "RIGHT", 10, 0);
                end
            else
                if spaceRight >= (maxW + pad * 2) + 8 then
                    tip:SetPoint("LEFT", self, "RIGHT", 10, 0);
                else
                    tip:SetPoint("RIGHT", self, "LEFT", -18, 0);
                end
            end
            tip:Show();
            return;
        end
        -- Build spell list per class (inline to avoid file-scope local)
        local cls = hdata.classFile;
        local tooltipSpells;
        if cls == "DRUID" then
            tooltipSpells = { INNERVATE_SPELL_ID, 20484 };
        elseif cls == "SHAMAN" then
            tooltipSpells = { MANA_TIDE_CAST_SPELL_ID };
        elseif cls == "PRIEST" then
            tooltipSpells = { 34433, SYMBOL_OF_HOPE_SPELL_ID };
        end
        if not tooltipSpells then return; end
        local hasContent = false;
        for _, sid in ipairs(tooltipSpells) do
            if raidCooldowns[guid .. "-" .. sid] then hasContent = true; break; end
        end
        if not hasContent then return; end
        if not self.healerTooltip then
            local tip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate");
            tip:SetFrameStrata("TOOLTIP");
            tip:SetFrameLevel(200);
            tip:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            });
            tip:SetBackdropColor(0, 0, 0, 0.9);
            tip:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8);
            tip:SetClampedToScreen(true);
            tip:Hide();
            tip.rows = {};
            self.healerTooltip = tip;
        end
        local tip = self.healerTooltip;
        local now = GetTime();
        local fontSize = 12;
        local rowHeight = fontSize + 4;
        local pad = 6;
        local colGap = 8;
        local maxSpellW = 0;
        local maxStatusW = 0;
        local count = 0;
        for i, sid in ipairs(tooltipSpells) do
            local entry = raidCooldowns[guid .. "-" .. sid];
            if entry then
                count = count + 1;
                local row = tip.rows[count];
                if not row then
                    row = {};
                    row.spell = tip:CreateFontString(nil, "OVERLAY");
                    row.spell:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE");
                    row.spell:SetJustifyH("LEFT");
                    row.status = tip:CreateFontString(nil, "OVERLAY");
                    row.status:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE");
                    row.status:SetJustifyH("LEFT");
                    tip.rows[count] = row;
                end
                row.spell:SetText(entry.spellName);
                row.spell:SetTextColor(1, 1, 1);
                if entry.expiryTime <= now then
                    row.status:SetText("Ready");
                    row.status:SetTextColor(0.2, 1, 0.2);
                else
                    local rem = entry.expiryTime - now;
                    local mins = floor(rem / 60);
                    local secs = floor(rem - mins * 60);
                    row.status:SetText(format("%d:%02d", mins, secs));
                    row.status:SetTextColor(1, 0.8, 0.2);
                end
                local sw = row.spell:GetStringWidth();
                local stw = row.status:GetStringWidth();
                if sw > maxSpellW then maxSpellW = sw; end
                if stw > maxStatusW then maxStatusW = stw; end
                row.spell:Show();
                row.status:Show();
            end
        end
        for i = count + 1, #tip.rows do
            tip.rows[i].spell:Hide();
            tip.rows[i].status:Hide();
        end
        if count == 0 then return; end
        local statusX = pad + maxSpellW + colGap;
        for i = 1, count do
            local row = tip.rows[i];
            local yOff = -pad - (i - 1) * rowHeight;
            row.spell:ClearAllPoints();
            row.spell:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, yOff);
            row.status:ClearAllPoints();
            row.status:SetPoint("TOPLEFT", tip, "TOPLEFT", statusX, yOff);
        end
        local tipW = statusX + maxStatusW + pad;
        tip:SetSize(tipW, pad * 2 + count * rowHeight);
        tip:ClearAllPoints();
        local parent = self:GetParent() or self;
        local frameLeft = parent:GetLeft() or self:GetLeft();
        local screenW = GetScreenWidth() * self:GetEffectiveScale();
        local frameRight = parent:GetRight() or self:GetRight();
        local spaceLeft = frameLeft and (frameLeft * self:GetEffectiveScale()) or 0;
        local spaceRight = frameRight and (screenW - frameRight * self:GetEffectiveScale()) or 0;
        -- Offsets account for row inset: LEFT_MARGIN(10)+gap(8) left, rightInset(2)+gap(8) right
        local preferLeft = db.tooltipAnchor == "left";
        if preferLeft then
            if spaceLeft >= tipW + 8 then
                tip:SetPoint("RIGHT", self, "LEFT", -18, 0);
            else
                tip:SetPoint("LEFT", self, "RIGHT", 10, 0);
            end
        else
            if spaceRight >= tipW + 8 then
                tip:SetPoint("LEFT", self, "RIGHT", 10, 0);
            else
                tip:SetPoint("RIGHT", self, "LEFT", -18, 0);
            end
        end
        tip:Show();
    end);
    frame:SetScript("OnLeave", function(self)
        self.highlight:Hide();
        if self.healerTooltip then self.healerTooltip:Hide(); end
    end);

    frame:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" or not db or not db.enableCdRequest or not self.healerGUID then return; end
        if GetTime() - menuDismissTime < 0.2 then return; end  -- suppress click-through from menu dismiss
        -- Dead healer with soulstone/rebirth buff: whisper them to accept it
        local hdata = healers[self.healerGUID];
        if hdata and hdata.manaPercent == -2 and (hdata.hasSoulstone or hdata.hasRebirth) then
            if GetTime() - lastWhisperTime >= WHISPER_COOLDOWN then
                lastWhisperTime = GetTime();
                local buffName = hdata.hasSoulstone and "Soulstone" or "Rebirth";
                local recipient = previewActive and UnitName("player") or self.healerName;
                SendChatMessage(format("[HealerWatch] Accept your %s!", buffName), "WHISPER", nil, recipient);
            end
            return;
        end
        -- Dead healer without soulstone/rebirth: auto-whisper best rebirth druid
        if self.needsRebirth then
            local now = GetTime();
            -- Collect alive+ready rebirth casters
            local rebirthCasters = {};
            for _, entry in pairs(raidCooldowns) do
                if entry.spellId == 20484 and not IsCasterDead(entry.sourceGUID) and entry.expiryTime <= now then
                    tinsert(rebirthCasters, entry);
                end
            end
            if #rebirthCasters == 0 then return; end
            -- Sort by lastCastTime ascending (longest since last cast = highest priority)
            sort(rebirthCasters, function(a, b)
                return (a.lastCastTime or 0) < (b.lastCastTime or 0);
            end);
            -- Bear form check: prefer non-bear druid, fall back to bear with caveat
            local best, isBear;
            for _, c in ipairs(rebirthCasters) do
                if not IsUnitInBearForm(c.sourceGUID) then
                    best = c; isBear = false; break;
                end
            end
            if not best then best = rebirthCasters[1]; isBear = true; end
            if best and GetTime() - lastWhisperTime >= WHISPER_COOLDOWN then
                lastWhisperTime = GetTime();
                local deadName = self.healerName or "a healer";
                local base = format("[HealerWatch] Can you Rebirth %s?", deadName);
                local msg = isBear and (base .. " (if safe to leave bear form)") or base;
                local recipient = previewActive and UnitName("player") or best.name;
                SendChatMessage(msg, "WHISPER", nil, recipient);
            end
            return;
        end
        if self.healerTooltip then self.healerTooltip:Hide(); end
        ShowCooldownRequestMenu(self);
    end);

    -- Name: class-colored, left-aligned
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.nameText:SetPoint("LEFT", 0, 0);
    frame.nameText:SetJustifyH("LEFT");
    frame.nameText:SetWordWrap(false);

    -- Mana %: color-coded, right-aligned in its column
    frame.manaText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.manaText:SetJustifyH("RIGHT");

    -- Status label: fixed-width column after mana
    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.statusText:SetJustifyH("LEFT");

    -- Status duration: left-aligned after the label column
    frame.durationText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.durationText:SetJustifyH("LEFT");

    -- Dead pulse overlay (subtle red glow for dead healers needing rebirth)
    local deadPulse = frame:CreateTexture(nil, "ARTWORK");
    deadPulse:SetAllPoints();
    deadPulse:SetColorTexture(1.0, 0.7, 0.0, 1.0);
    deadPulse:SetAlpha(0);
    deadPulse:Hide();
    frame.deadPulse = deadPulse;
    frame.needsRebirth = false;

    -- Icon mode: up to 4 status icon slots (texture + small duration text)
    frame.statusIcons = {};
    for i = 1, 4 do
        local tex = frame:CreateTexture(nil, "OVERLAY");
        tex:SetSize(14, 14);
        tex:Hide();
        local dur = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
        dur:SetJustifyH("LEFT");
        dur:Hide();
        frame.statusIcons[i] = { icon = tex, dur = dur };
    end

    return frame;
end

-- Persistent row frames (never recycled — Blizzard pattern: reuse in place)
local MAX_HEALER_ROWS = 10;
for i = 1, MAX_HEALER_ROWS do
    activeRows[i] = CreateRowFrame();
end

local function HideAllRows()
    for i = 1, #activeRows do
        activeRows[i]:Hide();
        activeRows[i].healerGUID = nil;
        activeRows[i].healerName = nil;
        activeRows[i].needsRebirth = false;
        activeRows[i].deadPulse:Hide();
        for j = 1, 4 do
            activeRows[i].statusIcons[j].icon:Hide();
            activeRows[i].statusIcons[j].dur:Hide();
        end
    end
end

--------------------------------------------------------------------------------
-- Cooldown Row Frames (persistent, like healer rows)
--------------------------------------------------------------------------------

local function CreateCdRowFrame()
    local frame = CreateFrame("Button", nil, CooldownFrame);
    frame:SetSize(400, 16);
    frame:RegisterForClicks("AnyDown");
    frame:Hide();

    -- Row highlight (gated on db.showRowHighlight)
    local hl = frame:CreateTexture(nil, "BACKGROUND");
    hl:SetAllPoints();
    hl:SetColorTexture(1, 1, 1, 0.1);
    hl:Hide();
    frame.highlight = hl;

    frame:SetScript("OnEnter", function(self)
        if db and db.showRowHighlight then self.highlight:Show(); end
        if contextMenuVisible then return; end
        local group = self.spellGroup;
        if not group or not group.casters or #group.casters == 0 then return; end
        -- Custom tooltip for aligned columns
        if not self.cdTooltip then
            local tip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate");
            tip:SetFrameStrata("TOOLTIP");
            tip:SetFrameLevel(200);
            tip:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 12,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            });
            tip:SetBackdropColor(0, 0, 0, 0.9);
            tip:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8);
            tip:SetClampedToScreen(true);
            tip:Hide();
            tip.rows = {};
            self.cdTooltip = tip;
        end
        local tip = self.cdTooltip;
        local now = GetTime();
        -- Collect alive casters, sort by expiryTime: ready first, then soonest CD
        local sorted = {};
        for _, c in ipairs(group.casters) do
            if not c.isDead then
                tinsert(sorted, c);
            end
        end
        if #sorted == 0 then return; end
        sort(sorted, function(a, b)
            local aRem = a.expiryTime <= now and -1 or a.expiryTime;
            local bRem = b.expiryTime <= now and -1 or b.expiryTime;
            return aRem < bRem;
        end);
        -- Build rows
        local fontSize = 12;
        local rowHeight = fontSize + 4;
        local pad = 6;
        local colGap = 8;
        local maxStatusW = 0;
        local maxNameW = 0;
        for i, c in ipairs(sorted) do
            local row = tip.rows[i];
            if not row then
                row = {};
                row.status = tip:CreateFontString(nil, "OVERLAY");
                row.status:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE");
                row.status:SetJustifyH("LEFT");
                row.name = tip:CreateFontString(nil, "OVERLAY");
                row.name:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE");
                row.name:SetJustifyH("LEFT");
                tip.rows[i] = row;
            end
            if c.expiryTime <= now then
                row.status:SetText("Ready");
                row.status:SetTextColor(0.2, 1, 0.2);
            else
                local rem = c.expiryTime - now;
                row.status:SetText(format("%d:%02d", floor(rem / 60), floor(rem - floor(rem / 60) * 60)));
                row.status:SetTextColor(1, 0.8, 0.2);
            end
            local cr, cg, cb = GetClassColor(c.classFile);
            row.name:SetText(c.name);
            row.name:SetTextColor(cr, cg, cb);
            local sw = row.status:GetStringWidth();
            local nw = row.name:GetStringWidth();
            if sw > maxStatusW then maxStatusW = sw; end
            if nw > maxNameW then maxNameW = nw; end
            row.status:Show();
            row.name:Show();
        end
        -- Hide extra rows
        for i = #sorted + 1, #tip.rows do
            tip.rows[i].status:Hide();
            tip.rows[i].name:Hide();
        end
        -- Position rows
        local nameX = pad + maxStatusW + colGap;
        for i = 1, #sorted do
            local row = tip.rows[i];
            local yOff = -pad - (i - 1) * rowHeight;
            row.status:ClearAllPoints();
            row.status:SetPoint("TOPLEFT", tip, "TOPLEFT", pad, yOff);
            row.name:ClearAllPoints();
            row.name:SetPoint("TOPLEFT", tip, "TOPLEFT", nameX, yOff);
        end
        local tipW = nameX + maxNameW + pad;
        tip:SetSize(tipW, pad * 2 + #sorted * rowHeight);
        tip:ClearAllPoints();
        local parent = self:GetParent() or self;
        local frameLeft = parent:GetLeft() or self:GetLeft();
        local screenW = GetScreenWidth() * self:GetEffectiveScale();
        local frameRight = parent:GetRight() or self:GetRight();
        local spaceLeft = frameLeft and (frameLeft * self:GetEffectiveScale()) or 0;
        local spaceRight = frameRight and (screenW - frameRight * self:GetEffectiveScale()) or 0;
        -- Offsets account for row inset: LEFT_MARGIN(10)+gap(8) left, rightInset(2)+gap(8) right
        local preferLeft = db.tooltipAnchor == "left";
        if preferLeft then
            if spaceLeft >= tipW + 8 then
                tip:SetPoint("RIGHT", self, "LEFT", -18, 0);
            else
                tip:SetPoint("LEFT", self, "RIGHT", 10, 0);
            end
        else
            if spaceRight >= tipW + 8 then
                tip:SetPoint("LEFT", self, "RIGHT", 10, 0);
            else
                tip:SetPoint("RIGHT", self, "LEFT", -18, 0);
            end
        end
        tip:Show();
    end);
    frame:SetScript("OnLeave", function(self)
        self.highlight:Hide();
        if self.cdTooltip then self.cdTooltip:Hide(); end
    end);

    -- Click handler for cooldown requests
    frame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and db and db.enableCdRequest and self.spellId then
            if GetTime() - menuDismissTime < 0.2 then return; end  -- suppress click-through from menu dismiss
            local config = CD_REQUEST_CONFIG[self.spellId];
            if config and config.subgroupAware and not self.isRequestable then
                return;  -- Ready but no eligible healer in subgroup, block click
            end
            ShowCdRowRequestMenu(self);
        end
    end);

    -- Caster name (class-colored, left-aligned)
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.nameText:SetPoint("LEFT", 0, 0);
    frame.nameText:SetJustifyH("LEFT");
    frame.nameText:SetWordWrap(false);

    -- Timer / Ready status
    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.timerText:SetJustifyH("LEFT");

    -- Request pulse overlay (subtle amber glow)
    local pulse = frame:CreateTexture(nil, "ARTWORK");
    pulse:SetAllPoints();
    pulse:SetColorTexture(1.0, 0.7, 0.0, 1.0);
    pulse:SetAlpha(0);
    pulse:Hide();
    frame.requestPulse = pulse;
    frame.isRequest = false;

    -- Icon mode: spell icon texture
    frame.spellIcon = frame:CreateTexture(nil, "OVERLAY");
    frame.spellIcon:SetSize(14, 14);
    frame.spellIcon:Hide();

    return frame;
end

-- Persistent cd row frames (never recycled — reused in place like healer rows)
local MAX_CD_ROWS = 15;
for i = 1, MAX_CD_ROWS do
    activeCdRows[i] = CreateCdRowFrame();
end

local function HideAllCdRows()
    for i = 1, #activeCdRows do
        activeCdRows[i]:Hide();
        activeCdRows[i].sourceGUID = nil;
        activeCdRows[i].spellId = nil;
        activeCdRows[i].casterName = nil;
        activeCdRows[i].classFile = nil;
        activeCdRows[i].spellName = nil;
        activeCdRows[i].cdIcon = nil;
        activeCdRows[i].expiryTime = nil;
        activeCdRows[i].spellGroup = nil;
        activeCdRows[i].isRequestable = nil;
        activeCdRows[i].isRequest = false;
        activeCdRows[i].requestPulse:Hide();
        activeCdRows[i].spellIcon:Hide();
    end
end

--------------------------------------------------------------------------------
-- Cooldown Request Menu
--------------------------------------------------------------------------------

-- Which cooldowns can be requested via click-to-whisper
local REQUESTABLE_SPELLS = {
    [INNERVATE_SPELL_ID] = { scope = "raid" },
    [20707] = { scope = "alive" },  -- Soulstone (canonical ID) — pre-cast on alive targets
    [20484] = { scope = "dead" },   -- Rebirth (canonical ID)
};

-- Per-spell behavior when a cooldown row is clicked
CD_REQUEST_CONFIG = {
    -- [BLOODLUST_SPELL_ID]        = { type = "cast" },              -- disabled for now
    -- [HEROISM_SPELL_ID]          = { type = "cast" },              -- disabled for now
    [INNERVATE_SPELL_ID]        = { type = "target", filter = "low_mana",  threshold = 50 },
    -- [POWER_INFUSION_SPELL_ID]   = { type = "target", filter = "dps_mana" },  -- disabled for now
    [20484]                     = { type = "target", filter = "dead" },                         -- Rebirth
    [20707]                     = { type = "target", filter = "alive_no_soulstone" },             -- Soulstone
    [MANA_TIDE_CAST_SPELL_ID]   = { type = "conditional_cast", condition = "subgroup_low_mana", threshold = 20, subgroupAware = true },
    [SYMBOL_OF_HOPE_SPELL_ID]   = { type = "conditional_cast", condition = "subgroup_low_mana", threshold = 20, subgroupAware = true },
};

-- Check if any healer in the caster's subgroup has mana <= threshold% (excluding caster)
local function HasLowManaHealerInSubgroup(casterGUID, threshold)
    local casterSubgroup = memberSubgroups[casterGUID];
    if not casterSubgroup then return false; end

    for guid, data in pairs(healers) do
        if guid ~= casterGUID and data.manaPercent >= 0 and data.manaPercent <= threshold then
            local subgroup = memberSubgroups[guid];
            if subgroup and subgroup == casterSubgroup then
                return true;
            end
        end
    end
    return false;
end

-- Scan group members for valid targets based on filter type
local function ScanGroupTargets(filter, threshold, casterGUID)
    local results = {};

    if previewActive then
        -- Preview mode: bypass thresholds so all targets are always clickable
        if filter == "dead" or filter == "alive_no_soulstone" then
            -- Use full group member list (includes non-healers)
            for _, m in ipairs(previewGroupMembers) do
                if m.guid ~= casterGUID then
                    if filter == "dead" then
                        if m.isDead and not m.hasSoulstone and not m.hasRebirth then
                            tinsert(results, { name = m.name, guid = m.guid, classFile = m.classFile,
                                info = "Dead" });
                        end
                    elseif filter == "alive_no_soulstone" then
                        if not m.isDead and not m.hasSoulstone then
                            tinsert(results, { name = m.name, guid = m.guid, classFile = m.classFile,
                                info = "" });
                        end
                    end
                end
            end
        else
            for guid, data in pairs(healers) do
                if guid ~= casterGUID then
                    if filter == "low_mana" then
                        if data.manaPercent >= 0 then
                            tinsert(results, { name = data.name, guid = guid, classFile = data.classFile,
                                info = format("%d%% mana", data.manaPercent), sortValue = data.manaPercent });
                        end
                    end
                end
            end
        end
    else
        -- Live mode: scan actual group members
        local units = IterateGroupMembers();
        for _, unit in ipairs(units) do
            local guid = UnitGUID(unit);
            if guid and guid ~= casterGUID then
                local name = UnitName(unit);
                local _, classFile = UnitClass(unit);
                if filter == "low_mana" then
                    local powerType = UnitPowerType(unit);
                    if powerType == POWER_TYPE_MANA then
                        local maxPower = UnitPowerMax(unit, POWER_TYPE_MANA);
                        if maxPower > 0 then
                            local pct = floor(UnitPower(unit, POWER_TYPE_MANA) / maxPower * 100);
                            if pct <= threshold then
                                tinsert(results, { name = name, guid = guid, classFile = classFile,
                                    info = format("%d%% mana", pct), sortValue = pct });
                            end
                        end
                    end
                elseif filter == "low_health" then
                    if not UnitIsDeadOrGhost(unit) then
                        local maxHP = UnitHealthMax(unit);
                        if maxHP > 0 then
                            local pct = floor(UnitHealth(unit) / maxHP * 100);
                            if pct <= threshold then
                                tinsert(results, { name = name, guid = guid, classFile = classFile,
                                    info = format("%d%% health", pct), sortValue = pct });
                            end
                        end
                    end
                elseif filter == "dead" then
                    if UnitIsDeadOrGhost(unit) then
                        local healerData = healers[guid];
                        local hasSS = healerData and healerData.hasSoulstone;
                        local hasRB = healerData and healerData.hasRebirth;
                        if not hasSS and not hasRB then
                            tinsert(results, { name = name, guid = guid, classFile = classFile,
                                info = "Dead" });
                        end
                    end
                elseif filter == "alive_no_soulstone" then
                    if not UnitIsDeadOrGhost(unit) then
                        local healerData = healers[guid];
                        if not healerData or not healerData.hasSoulstone then
                            tinsert(results, { name = name, guid = guid, classFile = classFile,
                                info = "" });
                        end
                    end
                elseif filter == "dps_mana" then
                    local powerType = UnitPowerType(unit);
                    if powerType == POWER_TYPE_MANA and not (healers[guid] and healers[guid].isHealer) then
                        tinsert(results, { name = name, guid = guid, classFile = classFile,
                            info = "DPS" });
                    end
                end
            end
        end
    end

    if filter == "low_mana" or filter == "low_health" then
        sort(results, function(a, b) return (a.sortValue or 0) < (b.sortValue or 0); end);
    else
        sort(results, function(a, b) return a.name < b.name; end);
    end
    return results;
end

local MENU_ITEM_HEIGHT = 20;
local MENU_PADDING = 4;
local MENU_ICON_SIZE = 16;

-- Returns one entry per requestable spell with the best caster pre-selected.
-- Bear-form druids are deprioritized for Innervate/Rebirth.
-- Helpers are defined inside to avoid adding to the main-chunk local variable count.
local function GetEligibleCasters(healerGUID)
    local results = {};
    local healerData = healers[healerGUID];
    if not healerData then return results; end

    local healerSubgroup = memberSubgroups[healerGUID];
    local now = GetTime();

    -- Pick best caster from list: lowest lastCastTime, random if all uncast
    local function pickBest(casters)
        if #casters == 0 then return nil; end
        local allUncast = true;
        for _, c in ipairs(casters) do
            if c.lastCastTime > 0 then allUncast = false; break; end
        end
        if allUncast then return casters[random(#casters)]; end
        local best = casters[1];
        for i = 2, #casters do
            if casters[i].lastCastTime < best.lastCastTime then best = casters[i]; end
        end
        return best;
    end

    -- For Innervate/Rebirth, prefer non-bear druids; fall back to bear with caveat
    local function pickBestWithBearCheck(casters, spellId)
        local bearSensitive = (spellId == INNERVATE_SPELL_ID or spellId == 20484);
        if not bearSensitive then return pickBest(casters), false; end
        local nonBears, bears = {}, {};
        for _, c in ipairs(casters) do
            if IsUnitInBearForm(c.guid) then tinsert(bears, c); else tinsert(nonBears, c); end
        end
        if #nonBears > 0 then return pickBest(nonBears), false; end
        if #bears > 0 then return pickBest(bears), true; end
        return nil, false;
    end

    -- Collect eligible casters grouped by spellId
    local spellGroups = {};
    for _, entry in pairs(raidCooldowns) do
        local spellConfig = REQUESTABLE_SPELLS[entry.spellId];
        if spellConfig and entry.expiryTime <= now then
            local eligible = false;
            if previewActive then
                if spellConfig.scope == "dead" then
                    eligible = (healerData.manaPercent == -2);
                elseif spellConfig.scope == "alive" then
                    eligible = (healerData.manaPercent >= 0);
                else
                    eligible = true;
                end
            elseif entry.sourceGUID ~= healerGUID then
                if spellConfig.scope == "raid" then
                    eligible = (healerData.manaPercent >= 0);
                    -- Apply Innervate threshold: only show if healer mana is at or below the configured threshold
                    if eligible and entry.spellId == INNERVATE_SPELL_ID and db then
                        eligible = (healerData.manaPercent <= db.innervateRequestThreshold);
                    end
                elseif spellConfig.scope == "subgroup" then
                    if healerData.manaPercent >= 0 then
                        local casterSubgroup = memberSubgroups[entry.sourceGUID];
                        eligible = (casterSubgroup and healerSubgroup and casterSubgroup == healerSubgroup);
                    end
                elseif spellConfig.scope == "dead" then
                    eligible = (healerData.manaPercent == -2);
                elseif spellConfig.scope == "alive" then
                    eligible = (healerData.manaPercent >= 0);
                end
            end

            if eligible then
                local sid = entry.spellId;
                if not spellGroups[sid] then
                    spellGroups[sid] = { spellId = sid, spellName = entry.spellName, icon = entry.icon, casters = {} };
                end
                tinsert(spellGroups[sid].casters, {
                    name = entry.name,
                    guid = entry.sourceGUID,
                    classFile = entry.classFile,
                    lastCastTime = entry.lastCastTime or 0,
                });
            end
        end
    end

    -- For each spell, pick best caster (bear-form aware) and build result
    for _, group in pairs(spellGroups) do
        local best, isBear = pickBestWithBearCheck(group.casters, group.spellId);
        if best then
            tinsert(results, {
                spellId = group.spellId,
                spellName = group.spellName,
                icon = group.icon,
                casterName = best.name,
                casterGUID = best.guid,
                classFile = best.classFile,
                isBear = isBear,
            });
        end
    end

    sort(results, function(a, b) return a.spellName < b.spellName; end);
    return results;
end

local function CreateContextMenu()
    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate");
    menu:SetFrameStrata("TOOLTIP");
    menu:SetFrameLevel(100);
    menu:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    });
    menu:SetBackdropColor(0.1, 0.1, 0.1, 0.95);
    menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8);
    menu:SetClampedToScreen(true);
    menu:EnableMouse(false);
    menu:Hide();

    -- Dismiss on click-outside via GLOBAL_MOUSE_DOWN (standard WoW dropdown pattern)
    menu:SetScript("OnEvent", function(self, event)
        if event == "GLOBAL_MOUSE_DOWN" then
            -- Check if click was on the menu or any of its children
            local mouseFoci = GetMouseFoci();
            for _, focus in ipairs(mouseFoci) do
                local f = focus;
                while f do
                    if f == self then return; end
                    f = f:GetParent();
                end
            end
            HideContextMenu();
        end
    end);

    menu.items = {};
    return menu;
end

local function CreateMenuItem(menu)
    local item = CreateFrame("Frame", nil, menu);
    item:SetHeight(MENU_ITEM_HEIGHT);

    item.highlight = item:CreateTexture(nil, "BACKGROUND");
    item.highlight:SetAllPoints();
    item.highlight:SetColorTexture(1, 1, 1, 0.15);
    item.highlight:Hide();

    item.icon = item:CreateTexture(nil, "ARTWORK");
    item.icon:SetSize(MENU_ICON_SIZE, MENU_ICON_SIZE);
    item.icon:SetPoint("LEFT", MENU_PADDING, 0);

    item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    item.text:SetPoint("LEFT", item.icon, "RIGHT", 4, 0);
    item.text:SetJustifyH("LEFT");

    item:EnableMouse(true);
    item:SetScript("OnEnter", function(self) self.highlight:Show(); end);
    item:SetScript("OnLeave", function(self) self.highlight:Hide(); end);

    return item;
end

HideContextMenu = function()
    if contextMenuFrame then
        contextMenuFrame:Hide();
        contextMenuFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN");
    end
    if contextMenuVisible then
        menuDismissTime = GetTime();
    end
    contextMenuVisible = false;
end

ShowCooldownRequestMenu = function(rowFrame)
    local healerGUID = rowFrame.healerGUID;
    local healerName = rowFrame.healerName;
    if not healerGUID or not healerName then return; end

    -- Toggle off if clicking same row
    if contextMenuVisible and contextMenuFrame and contextMenuFrame.targetGUID == healerGUID then
        HideContextMenu();
        return;
    end

    local eligible = GetEligibleCasters(healerGUID);
    if #eligible == 0 then
        HideContextMenu();
        return;
    end

    if not contextMenuFrame then
        contextMenuFrame = CreateContextMenu();
    end

    -- Hide existing items
    for _, item in ipairs(contextMenuFrame.items) do
        item:Hide();
    end

    local healerData = healers[healerGUID];
    local manaStr = "";
    if healerData then
        if healerData.manaPercent == -2 then
            manaStr = "Dead";
        elseif healerData.manaPercent >= 0 then
            manaStr = format("%d%% mana", healerData.manaPercent);
        end
    end

    local maxWidth = 0;
    for i, entry in ipairs(eligible) do
        local item = contextMenuFrame.items[i];
        if not item then
            item = CreateMenuItem(contextMenuFrame);
            contextMenuFrame.items[i] = item;
        end

        -- One item per spell — just show the spell name
        item.text:SetText(entry.spellName);
        item.icon:SetTexture(entry.icon);

        item:ClearAllPoints();
        item:SetPoint("TOPLEFT", contextMenuFrame, "TOPLEFT", MENU_PADDING, -(MENU_PADDING + (i - 1) * MENU_ITEM_HEIGHT));
        item:SetPoint("RIGHT", contextMenuFrame, "RIGHT", -MENU_PADDING, 0);

        -- Store data for click handler
        item.casterName = entry.casterName;
        item.spellName = entry.spellName;
        item.healerName = healerName;
        item.manaStr = (entry.spellId == INNERVATE_SPELL_ID) and manaStr or nil;
        item.isBear = entry.isBear;

        item:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return; end
            if GetTime() - lastWhisperTime < WHISPER_COOLDOWN then return; end
            lastWhisperTime = GetTime();
            local base = self.manaStr
                and format("[HealerWatch] %s needs %s (%s)", self.healerName, self.spellName, self.manaStr)
                or format("[HealerWatch] %s needs %s", self.healerName, self.spellName);
            local msg = self.isBear and (base .. " - if safe to leave bear form") or base;
            local recipient = previewActive and UnitName("player") or self.casterName;
            SendChatMessage(msg, "WHISPER", nil, recipient);
            HideContextMenu();
        end);

        item:Show();

        local textWidth = item.text:GetStringWidth();
        local itemWidth = MENU_PADDING + MENU_ICON_SIZE + 4 + textWidth + MENU_PADDING;
        if itemWidth > maxWidth then maxWidth = itemWidth; end
    end

    local menuWidth = max(maxWidth + MENU_PADDING * 2, 120);
    local menuHeight = MENU_PADDING * 2 + #eligible * MENU_ITEM_HEIGHT;
    contextMenuFrame:SetSize(menuWidth, menuHeight);

    -- Anchor near the cursor
    local cursorX, cursorY = GetCursorPosition();
    local menuScale = contextMenuFrame:GetEffectiveScale();
    contextMenuFrame:ClearAllPoints();
    local yAdj = (MENU_PADDING + MENU_ITEM_HEIGHT * 0.5) / menuScale;
    contextMenuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / menuScale, cursorY / menuScale + yAdj);
    contextMenuFrame.targetGUID = healerGUID;
    contextMenuFrame.targetSpellId = nil;
    contextMenuFrame:Show();
    contextMenuFrame:RegisterEvent("GLOBAL_MOUSE_DOWN");
    contextMenuVisible = true;
end

-- Show target selection submenu for a specific caster's targeted spell
ShowTargetSubmenu = function(casterName, casterGUID, spellId, spellName, spellIcon)
    local config = CD_REQUEST_CONFIG[spellId];
    if not config or config.type ~= "target" then return; end

    local threshold = config.threshold or 20;
    if spellId == INNERVATE_SPELL_ID and db then
        threshold = db.innervateRequestThreshold;
    end
    local targets = ScanGroupTargets(config.filter, threshold, casterGUID);
    if #targets == 0 then
        HideContextMenu();
        return;
    end

    if not contextMenuFrame then
        contextMenuFrame = CreateContextMenu();
    end

    -- Hide existing items
    for _, item in ipairs(contextMenuFrame.items) do
        item:Hide();
    end

    local maxWidth = 0;
    for i, t in ipairs(targets) do
        local item = contextMenuFrame.items[i];
        if not item then
            item = CreateMenuItem(contextMenuFrame);
            contextMenuFrame.items[i] = item;
        end

        local cr, cg, cb = GetClassColor(t.classFile);
        local coloredName = format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, t.name);
        local displayText = (t.info and t.info ~= "") and format("%s (%s)", coloredName, t.info) or coloredName;
        item.text:SetText(displayText);
        item.icon:SetTexture(spellIcon);

        item:ClearAllPoints();
        item:SetPoint("TOPLEFT", contextMenuFrame, "TOPLEFT", MENU_PADDING, -(MENU_PADDING + (i - 1) * MENU_ITEM_HEIGHT));
        item:SetPoint("RIGHT", contextMenuFrame, "RIGHT", -MENU_PADDING, 0);

        -- Store data for click handler
        item.casterName = casterName;
        item.whisperMsg = (t.info and t.info ~= "") and format("[HealerWatch] Cast %s on %s (%s)", spellName, t.name, t.info) or format("[HealerWatch] Cast %s on %s", spellName, t.name);

        item:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return; end
            if GetTime() - lastWhisperTime < WHISPER_COOLDOWN then return; end
            lastWhisperTime = GetTime();
            local recipient = previewActive and UnitName("player") or self.casterName;
            SendChatMessage(self.whisperMsg, "WHISPER", nil, recipient);
            HideContextMenu();
        end);

        item:Show();

        local textWidth = item.text:GetStringWidth();
        local itemWidth = MENU_PADDING + MENU_ICON_SIZE + 4 + textWidth + MENU_PADDING;
        if itemWidth > maxWidth then maxWidth = itemWidth; end
    end

    local menuWidth = max(maxWidth + MENU_PADDING * 2, 120);
    local menuHeight = MENU_PADDING * 2 + #targets * MENU_ITEM_HEIGHT;
    contextMenuFrame:SetSize(menuWidth, menuHeight);

    -- Anchor at cursor, shifted up so cursor lands on first item
    local menuScale = contextMenuFrame:GetEffectiveScale();
    contextMenuFrame:ClearAllPoints();
    local anchorX, anchorY = GetCursorPosition();
    local yAdj = MENU_PADDING + MENU_ITEM_HEIGHT * 0.5;
    contextMenuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", anchorX / menuScale, anchorY / menuScale + yAdj);
    contextMenuFrame.targetGUID = casterGUID;
    contextMenuFrame.targetSpellId = spellId;
    contextMenuFrame:Show();
    contextMenuFrame:RegisterEvent("GLOBAL_MOUSE_DOWN");
    contextMenuVisible = true;
end

-- Pick the best ready caster: prefer longest time since last cast, random if all uncast
local function PickBestCaster(group)
    local now = GetTime();
    local ready = {};
    for _, c in ipairs(group.casters) do
        if not c.isDead and c.expiryTime <= now then
            tinsert(ready, c);
        end
    end
    if #ready == 0 then return nil; end

    -- Check if all have lastCastTime == 0 (never cast)
    local allUncast = true;
    for _, c in ipairs(ready) do
        if c.lastCastTime > 0 then allUncast = false; break; end
    end

    if allUncast then
        return ready[random(#ready)];
    end

    -- Pick the one with the lowest lastCastTime (longest since last cast)
    local best = ready[1];
    for i = 2, #ready do
        if ready[i].lastCastTime < best.lastCastTime then
            best = ready[i];
        end
    end
    return best;
end

-- Level 1 menu: list casters of a spell group with individual state
ShowCdRowRequestMenu = function(cdRow)
    local spellId = cdRow.spellId;
    local group = cdRow.spellGroup;
    if not spellId or not group then return; end

    -- Toggle off if clicking same spell
    if contextMenuVisible and contextMenuFrame and contextMenuFrame.targetSpellId == spellId then
        HideContextMenu();
        return;
    end

    local config = CD_REQUEST_CONFIG[spellId];
    if not config then return; end

    -- For subgroupAware spells, whisper the best eligible caster directly (no menu)
    if config.subgroupAware then
        local now = GetTime();
        local best;
        for _, c in ipairs(group.casters) do
            if not c.isDead and c.expiryTime <= now then
                if previewActive or HasLowManaHealerInSubgroup(c.guid, config.threshold or 20) then
                    if not best or c.lastCastTime < best.lastCastTime then
                        best = c;
                    end
                end
            end
        end
        if not best then return; end
        if GetTime() - lastWhisperTime < WHISPER_COOLDOWN then return; end
        lastWhisperTime = GetTime();
        local msg = format("[HealerWatch] Cast %s please", group.spellName);
        local recipient = previewActive and UnitName("player") or best.name;
        SendChatMessage(msg, "WHISPER", nil, recipient);
        return;
    end

    -- For targeted spells, skip caster menu — go straight to target selection
    if config.type == "target" then
        local caster = PickBestCaster(group);
        if not caster then return; end
        if cdRow.cdTooltip then cdRow.cdTooltip:Hide(); end
        ShowTargetSubmenu(caster.name, caster.guid, spellId, group.spellName, group.icon);
        return;
    end

    if cdRow.cdTooltip then cdRow.cdTooltip:Hide(); end
    if not contextMenuFrame then
        contextMenuFrame = CreateContextMenu();
    end

    -- Hide existing items
    for _, item in ipairs(contextMenuFrame.items) do
        item:Hide();
    end

    local now = GetTime();
    local maxWidth = 0;

    -- Filter to alive casters, sort ready first then shortest CD
    local aliveCasters = {};
    for _, c in ipairs(group.casters) do
        if not c.isDead then
            tinsert(aliveCasters, c);
        end
    end
    if #aliveCasters == 0 then return; end
    sort(aliveCasters, function(a, b)
        local aReady = (a.expiryTime <= now);
        local bReady = (b.expiryTime <= now);
        if aReady ~= bReady then return aReady; end
        return a.expiryTime < b.expiryTime;
    end);

    for i, c in ipairs(aliveCasters) do
        local item = contextMenuFrame.items[i];
        if not item then
            item = CreateMenuItem(contextMenuFrame);
            contextMenuFrame.items[i] = item;
        end

        -- Build state string
        local stateStr;
        if c.expiryTime <= now then
            stateStr = "|cff00ff00Ready|r";
        else
            local rem = c.expiryTime - now;
            stateStr = format("|cffcccccc%d:%02d|r", floor(rem / 60), floor(rem) % 60);
        end

        local cr, cg, cb = GetClassColor(c.classFile);
        local coloredName = format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, c.name);
        local displayText = format("%s - %s", stateStr, coloredName);
        item.text:SetText(displayText);
        item.icon:SetTexture(group.icon);

        item:ClearAllPoints();
        item:SetPoint("TOPLEFT", contextMenuFrame, "TOPLEFT", MENU_PADDING, -(MENU_PADDING + (i - 1) * MENU_ITEM_HEIGHT));
        item:SetPoint("RIGHT", contextMenuFrame, "RIGHT", -MENU_PADDING, 0);

        -- Clickable only if ready (or preview mode)
        local isClickable = previewActive or (c.expiryTime <= now);
        item.casterName = c.name;

        if isClickable then
            item:EnableMouse(true);
            item:SetScript("OnEnter", function(self) self.highlight:Show(); end);
            item:SetScript("OnLeave", function(self) self.highlight:Hide(); end);

            if config.type == "target" then
                -- Level 2: open target submenu
                item:SetScript("OnMouseUp", function(self, button)
                    if button ~= "LeftButton" then return; end
                    ShowTargetSubmenu(self.casterName, c.guid, spellId, group.spellName, group.icon);
                end);
            elseif config.type == "cast" then
                item:SetScript("OnMouseUp", function(self, button)
                    if button ~= "LeftButton" then return; end
                    if GetTime() - lastWhisperTime < WHISPER_COOLDOWN then return; end
                    lastWhisperTime = GetTime();
                    local msg = format("[HealerWatch] Cast %s please", group.spellName);
                    local recipient = previewActive and UnitName("player") or self.casterName;
                    SendChatMessage(msg, "WHISPER", nil, recipient);
                    HideContextMenu();
                end);
            elseif config.type == "conditional_cast" then
                -- Check condition only in live mode
                local condMet = previewActive;
                if not condMet and config.condition == "subgroup_low_mana" then
                    condMet = HasLowManaHealerInSubgroup(c.guid, config.threshold or 20);
                end
                if condMet then
                    item:SetScript("OnMouseUp", function(self, button)
                        if button ~= "LeftButton" then return; end
                        if GetTime() - lastWhisperTime < WHISPER_COOLDOWN then return; end
                        lastWhisperTime = GetTime();
                        local msg = format("[HealerWatch] Cast %s please", group.spellName);
                        local recipient = previewActive and UnitName("player") or self.casterName;
                        SendChatMessage(msg, "WHISPER", nil, recipient);
                        HideContextMenu();
                    end);
                else
                    -- Condition not met — grey out
                    item:EnableMouse(false);
                    item:SetScript("OnMouseUp", nil);
                end
            end
        else
            -- Dead or on CD — non-clickable, greyed highlight
            item:EnableMouse(false);
            item:SetScript("OnEnter", nil);
            item:SetScript("OnLeave", nil);
            item:SetScript("OnMouseUp", nil);
        end

        item:Show();

        local textWidth = item.text:GetStringWidth();
        local itemWidth = MENU_PADDING + MENU_ICON_SIZE + 4 + textWidth + MENU_PADDING;
        if itemWidth > maxWidth then maxWidth = itemWidth; end
    end

    local menuWidth = max(maxWidth + MENU_PADDING * 2, 120);
    local menuHeight = MENU_PADDING * 2 + #aliveCasters * MENU_ITEM_HEIGHT;
    contextMenuFrame:SetSize(menuWidth, menuHeight);

    -- Anchor near the cursor
    local cursorX, cursorY = GetCursorPosition();
    local menuScale = contextMenuFrame:GetEffectiveScale();
    contextMenuFrame:ClearAllPoints();
    local yAdj = (MENU_PADDING + MENU_ITEM_HEIGHT * 0.5) / menuScale;
    contextMenuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / menuScale, cursorY / menuScale + yAdj);
    contextMenuFrame.targetGUID = nil;  -- spell-level, not caster-level
    contextMenuFrame.targetSpellId = spellId;
    contextMenuFrame:Show();
    contextMenuFrame:RegisterEvent("GLOBAL_MOUSE_DOWN");
    contextMenuVisible = true;
end

--------------------------------------------------------------------------------
-- Sync Window (Broadcaster Election UI)
--------------------------------------------------------------------------------

do
    local SYNC_ROW_HEIGHT = 20;
    local SYNC_PADDING = 10;
    local SYNC_WIDTH = 260;

    local frame = CreateFrame("Frame", "HealerWatchSyncFrame", UIParent, "BackdropTemplate");
    frame:SetSize(SYNC_WIDTH, 140);
    frame:SetFrameStrata("DIALOG");
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    });
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.92);
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1);
    frame:SetClampedToScreen(true);
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", function(self) self:StartMoving(); end);
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100);
    frame:Hide();

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    title:SetPoint("TOPLEFT", SYNC_PADDING, -SYNC_PADDING);
    title:SetText("HealerWatch Sync");

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    closeBtn:SetPoint("TOPRIGHT", -2, -2);
    closeBtn:SetScript("OnClick", function() frame:Hide(); end);

    -- Status line at bottom
    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    statusText:SetPoint("BOTTOMLEFT", SYNC_PADDING, SYNC_PADDING + 26);
    statusText:SetJustifyH("LEFT");

    -- Auto-Elect button at bottom
    local autoBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    autoBtn:SetSize(100, 22);
    autoBtn:SetPoint("BOTTOMLEFT", SYNC_PADDING, SYNC_PADDING);
    autoBtn:SetText("Auto-Elect");
    autoBtn:SetScript("OnClick", function()
        overrideBroadcaster = nil;
        if IsInGroup() then
            local dist = IsInRaid() and "RAID" or "PARTY";
            SendAddonMessage(ADDON_MSG_PREFIX, "OVERRIDE:CLEAR", dist);
        end
        RefreshSyncFrame();
    end);

    -- Row pool
    local rows = {};

    local function GetRow(index)
        if rows[index] then return rows[index]; end
        local row = CreateFrame("Button", nil, frame);
        row:SetHeight(SYNC_ROW_HEIGHT);

        row.indicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        row.indicator:SetPoint("LEFT", 0, 0);
        row.indicator:SetWidth(16);
        row.indicator:SetJustifyH("LEFT");

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
        row.nameText:SetPoint("LEFT", row.indicator, "RIGHT", 2, 0);
        row.nameText:SetJustifyH("LEFT");

        row.versionText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
        row.versionText:SetPoint("LEFT", row.nameText, "RIGHT", 6, 0);
        row.versionText:SetJustifyH("LEFT");

        row.rankText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
        row.rankText:SetPoint("RIGHT", -60, 0);
        row.rankText:SetJustifyH("RIGHT");

        row.setBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate");
        row.setBtn:SetSize(44, 18);
        row.setBtn:SetPoint("RIGHT", 0, 0);
        row.setBtn:SetText("Set");

        rows[index] = row;
        return row;
    end

    RefreshSyncFrame = function()
        if not frame:IsShown() then return; end

        -- Collect and sort users: broadcaster first, then by rank desc, then alphabetical
        local sorted = {};
        for _, user in pairs(healerWatchUsers) do
            tinsert(sorted, user);
        end
        sort(sorted, function(a, b)
            if a.rank ~= b.rank then return a.rank > b.rank; end
            return a.name < b.name;
        end);

        local broadcaster = GetBroadcaster();
        local isManual = (overrideBroadcaster and healerWatchUsers[overrideBroadcaster]) and true or false;
        local playerName = UnitName("player");
        local yOff = -(SYNC_PADDING + 24);  -- below title

        for i, user in ipairs(sorted) do
            local row = GetRow(i);
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", SYNC_PADDING, yOff);
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SYNC_PADDING, yOff);
            yOff = yOff - SYNC_ROW_HEIGHT;

            -- Broadcaster indicator
            if user.name == broadcaster then
                row.indicator:SetText("|cff00ff00>|r");
            else
                row.indicator:SetText("");
            end

            -- Class-colored name
            local classFile;
            if user.guid then
                _, classFile = GetPlayerInfoByGUID(user.guid);
            end
            if classFile then
                local r, g, b = GetClassColor(classFile);
                row.nameText:SetTextColor(r, g, b);
            else
                row.nameText:SetTextColor(1, 1, 1);
            end
            row.nameText:SetText(user.name);

            -- Version
            row.versionText:SetText("v" .. (user.version or "?"));

            -- Rank indicator
            local rankLabel = "";
            if user.rank == 2 then rankLabel = "Leader";
            elseif user.rank == 1 then rankLabel = "Assist";
            end
            row.rankText:SetText(rankLabel);

            -- Set button
            row.setBtn:SetScript("OnClick", function()
                overrideBroadcaster = user.name;
                if IsInGroup() then
                    local dist = IsInRaid() and "RAID" or "PARTY";
                    SendAddonMessage(ADDON_MSG_PREFIX, "OVERRIDE:" .. user.name, dist);
                end
                RefreshSyncFrame();
            end);

            row:Show();
        end

        -- Hide unused rows
        for i = #sorted + 1, #rows do
            rows[i]:Hide();
        end

        -- Status line
        if broadcaster == playerName then
            statusText:SetText("|cff00ff00You|r are broadcasting" .. (isManual and " (manual)" or " (auto)"));
        else
            statusText:SetText("Broadcaster: |cffffd100" .. broadcaster .. "|r" .. (isManual and " (manual)" or " (auto)"));
        end

        -- Resize frame to fit content
        local contentHeight = SYNC_PADDING + 24 + (#sorted * SYNC_ROW_HEIGHT) + 8 + 14 + 4 + 22 + SYNC_PADDING;
        frame:SetHeight(max(contentHeight, 100));
    end

    SyncFrame = frame;
end

--------------------------------------------------------------------------------
-- Display Update
--------------------------------------------------------------------------------

-- Shared layout constants
local FONT_PATH = "Fonts\\FRIZQT__.TTF";
local COL_GAP = 2;
local LEFT_MARGIN = 10;
local RIGHT_MARGIN = 10;
local TOP_PADDING = 8;
local BOTTOM_PADDING = 8;


-- Pre-compute healer row data into rowDataCache and return measured column widths
local function PrepareHealerRowData(sortedHealers)
    wipe(rowDataCache);
    local maxNameWidth = 0;
    local maxManaWidth = max(MeasureText("100%", db.fontSize), MeasureText("DEAD", db.fontSize));
    local maxStatusLabelWidth = 0;
    local maxStatusDurWidth = 0;
    local hasBuff = false;
    local hasPotion = false;
    local useIcons = db.statusIcons;
    local maxIconCount = 0;
    local hasIconDuration = false;

    for _, data in ipairs(sortedHealers) do
        local manaStr;
        if data.manaPercent == -2 then
            manaStr = "DEAD";
        elseif data.manaPercent == -1 then
            manaStr = "DC";
        else
            manaStr = format("%d%%", data.manaPercent);
        end

        local statusLabel, statusDur, iconData = FormatStatusText(data);

        local displayName = data.name;
        if not data.inspectConfirmed then
            displayName = data.name .. " (?)";
        end
        local nw = MeasureText(displayName, db.fontSize);
        if nw > maxNameWidth then maxNameWidth = nw; end

        -- Deep-copy iconData since statusIconParts is reused per call
        local iconDataCopy;
        if iconData and #iconData > 0 then
            iconDataCopy = {};
            for i, entry in ipairs(iconData) do
                iconDataCopy[i] = { icon = entry.icon, duration = entry.duration };
            end
        end

        if useIcons then
            if iconDataCopy then
                local count = #iconDataCopy;
                if count > maxIconCount then maxIconCount = count; end
                for _, entry in ipairs(iconDataCopy) do
                    if entry.duration ~= "" then
                        hasIconDuration = true;
                    end
                end
            end
        else
            local labelPlain = statusLabel:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "");
            local durPlain = statusDur:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "");

            local slw = 0;
            if labelPlain ~= "" then
                slw = MeasureText(labelPlain, db.fontSize - 1);
            end
            if durPlain ~= "" then
                if durPlain:find(":") then
                    hasPotion = true;
                else
                    hasBuff = true;
                end
            end
            if slw > maxStatusLabelWidth then maxStatusLabelWidth = slw; end
        end

        tinsert(rowDataCache, {
            data = data,
            manaStr = manaStr,
            statusLabel = statusLabel,
            statusDur = statusDur,
            statusIconData = iconDataCopy,
        });
    end

    if useIcons then
        -- Icon-based width: each icon + optional duration text
        if maxIconCount > 0 then
            local iconSize = db.iconSize;
            local iconGap = 3;
            maxStatusLabelWidth = maxIconCount * (iconSize + iconGap) - iconGap;
            if hasIconDuration then
                local durRefWidth = MeasureText("00s", db.fontSize - 2);
                maxStatusLabelWidth = maxStatusLabelWidth + maxIconCount * (iconGap + durRefWidth);
            end
        end
        maxStatusDurWidth = 0;
    else
        -- Use stable reference widths per format to prevent jitter as digits change
        local durFontSize = db.fontSize - 1;
        if hasPotion then
            maxStatusDurWidth = MeasureText("0:00", durFontSize);
        elseif hasBuff then
            maxStatusDurWidth = MeasureText("00s", durFontSize);
        end
    end

    local pad = max(4, floor(db.fontSize * 0.35 + 0.5));
    maxNameWidth = maxNameWidth + 1;
    maxManaWidth = maxManaWidth + pad;
    if maxStatusLabelWidth > 0 then
        maxStatusLabelWidth = maxStatusLabelWidth + pad;
    end
    if maxStatusDurWidth > 0 then
        maxStatusDurWidth = maxStatusDurWidth + pad;
    end

    return maxNameWidth, maxManaWidth, maxStatusLabelWidth, maxStatusDurWidth;
end

-- Check if any Rebirth caster is alive and off cooldown
local function IsRebirthAvailable()
    local now = GetTime();
    for _, entry in pairs(raidCooldowns) do
        if entry.spellId == 20484 then
            local guid = entry.sourceGUID;
            if not IsCasterDead(guid) and entry.expiryTime <= now then
                return true;
            end
        end
    end
    return false;
end

-- Render healer rows onto a target frame starting at yOffset; returns updated yOffset and totalWidth
local function RenderHealerRows(targetFrame, yOffset, totalWidth, maxNameWidth, maxManaWidth, maxStatusLabelWidth, maxStatusDurWidth)
    local useIcons = db.statusIcons;
    local rowHeight = max(db.fontSize + 4, useIcons and (db.iconSize + 2) or 0, 16);
    local iconSize = db.iconSize;
    local iconGap = 3;
    local rebirthReady = IsRebirthAvailable();

    for rowIdx, rd in ipairs(rowDataCache) do
        local data = rd.data;
        local row = activeRows[rowIdx];
        if not row then break; end  -- safety: cap at MAX_HEALER_ROWS
        row.healerGUID = data.guid;
        row.healerName = data.name;

        row:SetHeight(rowHeight);
        row.nameText:SetFont(FONT_PATH, db.fontSize, "OUTLINE");
        row.manaText:SetFont(FONT_PATH, db.fontSize, "OUTLINE");

        row.nameText:SetWidth(maxNameWidth);
        row.manaText:SetWidth(maxManaWidth);

        row.manaText:ClearAllPoints();
        row.manaText:SetPoint("LEFT", row.nameText, "RIGHT", 0, 0);

        local cr, cg, cb = GetClassColor(data.classFile);
        if not data.inspectConfirmed then
            row.nameText:SetText(data.name .. " |cff888888(?)|r");
            row.nameText:SetTextColor(cr * 0.5, cg * 0.5, cb * 0.5);
        else
            row.nameText:SetText(data.name);
            row.nameText:SetTextColor(cr, cg, cb);
        end

        if data.manaPercent == -2 or data.manaPercent == -1 then
            row.manaText:SetText(rd.manaStr);
            row.manaText:SetTextColor(0.5, 0.5, 0.5);
        elseif not data.inspectConfirmed then
            row.manaText:SetText(rd.manaStr);
            local mr, mg, mb = GetManaColor(data.manaPercent);
            row.manaText:SetTextColor(mr * 0.5, mg * 0.5, mb * 0.5);
        else
            row.manaText:SetText(rd.manaStr);
            local mr, mg, mb = GetManaColor(data.manaPercent);
            row.manaText:SetTextColor(mr, mg, mb);
        end

        -- Dead pulse: dead healer without soulstone/rebirth buff, and a rebirth is available
        if data.manaPercent == -2 and not data.hasSoulstone and not data.hasRebirth and rebirthReady then
            row.needsRebirth = true;
            row.deadPulse:Show();
        else
            row.needsRebirth = false;
            row.deadPulse:Hide();
        end

        if useIcons then
            -- Icon mode: hide text, show icon textures
            row.statusText:Hide();
            row.durationText:Hide();

            local iconData = rd.statusIconData;
            local prevAnchor = row.manaText;
            local prevPoint = "RIGHT";
            for i = 1, 4 do
                local slot = row.statusIcons[i];
                if iconData and i <= #iconData and iconData[i].icon then
                    slot.icon:ClearAllPoints();
                    slot.icon:SetSize(iconSize, iconSize);
                    slot.icon:SetTexture(iconData[i].icon);
                    local gap = (prevAnchor == row.manaText) and (COL_GAP + 3) or COL_GAP;
                    slot.icon:SetPoint("LEFT", prevAnchor, prevPoint, gap, 0);
                    slot.icon:Show();

                    if iconData[i].duration ~= "" then
                        slot.dur:ClearAllPoints();
                        slot.dur:SetFont(FONT_PATH, db.fontSize - 2, "OUTLINE");
                        slot.dur:SetPoint("LEFT", slot.icon, "RIGHT", iconGap, 0);
                        slot.dur:SetText(iconData[i].duration);
                        slot.dur:SetTextColor(1, 1, 1);
                        slot.dur:Show();
                        prevAnchor = slot.dur;
                        prevPoint = "RIGHT";
                    else
                        slot.dur:Hide();
                        prevAnchor = slot.icon;
                        prevPoint = "RIGHT";
                    end
                else
                    slot.icon:Hide();
                    slot.dur:Hide();
                end
            end
        else
            -- Text mode: hide icons, show text
            for i = 1, 4 do
                row.statusIcons[i].icon:Hide();
                row.statusIcons[i].dur:Hide();
            end

            row.statusText:SetFont(FONT_PATH, db.fontSize - 1, "OUTLINE");
            row.durationText:SetFont(FONT_PATH, db.fontSize - 1, "OUTLINE");
            row.statusText:SetWidth(maxStatusLabelWidth);
            row.statusText:ClearAllPoints();
            row.statusText:SetPoint("LEFT", row.manaText, "RIGHT", COL_GAP + 3, 0);
            row.durationText:ClearAllPoints();
            row.durationText:SetPoint("LEFT", row.statusText, "RIGHT", COL_GAP, 0);
            row.statusText:SetText(rd.statusLabel);
            row.durationText:SetText(rd.statusDur);
            row.statusText:Show();
            row.durationText:Show();
        end

        row:ClearAllPoints();
        row:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
        row:SetPoint("RIGHT", targetFrame, "RIGHT", -2, 0);
        row:Show();

        yOffset = yOffset - rowHeight;
    end

    -- Hide excess rows
    for i = #rowDataCache + 1, #activeRows do
        activeRows[i]:Hide();
        activeRows[i].healerGUID = nil;
        activeRows[i].healerName = nil;
    end

    return yOffset;
end

-- Collect sorted cooldown data and render rows onto a target frame; returns updated yOffset and totalWidth
local function RenderCooldownRows(targetFrame, yOffset, totalWidth)
    local spellGroups = GroupCooldownsBySpell();

    if #spellGroups == 0 then return yOffset, totalWidth; end

    local now = GetTime();
    local cdMode = db.cooldownDisplayMode or "icons_labels";
    local useIcons = (cdMode == "icons" or cdMode == "icons_labels");
    local useIconLabels = (cdMode == "icons_labels");
    local cdIconSize = db.iconSize;
    local rowHeight = max(db.fontSize + 4, useIcons and (cdIconSize + 2) or 0, 16);

    -- Measure column widths (no player name column — just spell + timer)
    local cdSpellMax = 0;
    local cdLabelMax = 0;
    local cdFontSize = db.fontSize;
    local cdTimerMax = MeasureText("Request (9)", cdFontSize);

    for _, group in ipairs(spellGroups) do
        if not useIcons or useIconLabels then
            local sw = MeasureText(group.spellName, cdFontSize);
            if sw > cdSpellMax then cdSpellMax = sw; end
        end
    end

    local cdPad = max(4, floor(cdFontSize * 0.35 + 0.5));
    local cdHalfPad = max(2, floor(cdPad * 0.5 + 0.5));
    cdTimerMax = cdTimerMax + cdHalfPad;

    if useIcons then
        if useIconLabels then
            cdLabelMax = cdSpellMax + cdPad;
            cdSpellMax = cdIconSize + cdPad;
        else
            cdSpellMax = cdIconSize + cdPad;
        end
    else
        cdSpellMax = cdSpellMax + cdPad;
    end

    local cdContentWidth = cdSpellMax + cdLabelMax + COL_GAP + cdTimerMax;
    local cdTotalWidth = LEFT_MARGIN + cdContentWidth + RIGHT_MARGIN;
    if cdTotalWidth > totalWidth then totalWidth = cdTotalWidth; end

    for rowIdx, group in ipairs(spellGroups) do
        local cdRow = activeCdRows[rowIdx];
        if not cdRow then break; end  -- safety: cap at MAX_CD_ROWS

        cdRow:SetParent(targetFrame);

        -- Store spell group for click handler
        cdRow.spellGroup = group;
        cdRow.spellId = group.spellId;
        cdRow.spellName = group.spellName;
        cdRow.cdIcon = group.icon;

        -- Best caster: first in sorted group (alive+ready first)
        local best = group.casters[1];
        cdRow.sourceGUID = best and best.guid or nil;
        cdRow.casterName = best and best.name or nil;
        cdRow.classFile = best and best.classFile or nil;
        cdRow.expiryTime = best and best.expiryTime or 0;

        -- nameText repurposed as spell name (left-aligned first column)
        cdRow.nameText:SetFont(FONT_PATH, cdFontSize, "OUTLINE");

        if useIcons then
            -- Icon mode: show spell icon
            cdRow.spellIcon:ClearAllPoints();
            cdRow.spellIcon:SetSize(cdIconSize, cdIconSize);
            cdRow.spellIcon:SetTexture(group.icon);
            cdRow.spellIcon:SetPoint("LEFT", 0, 0);
            cdRow.spellIcon:Show();

            if useIconLabels then
                -- Icon + label mode: icon, spell name, then timer
                cdRow.nameText:SetWidth(cdLabelMax);
                cdRow.nameText:SetText(group.spellName);
                cdRow.nameText:SetTextColor(1, 1, 1);
                cdRow.nameText:ClearAllPoints();
                cdRow.nameText:SetPoint("LEFT", cdRow.spellIcon, "RIGHT", COL_GAP, 0);
                cdRow.nameText:Show();
                cdRow.timerText:ClearAllPoints();
                cdRow.timerText:SetPoint("LEFT", cdRow.nameText, "RIGHT", COL_GAP, 0);
            else
                cdRow.nameText:Hide();
                cdRow.timerText:ClearAllPoints();
                cdRow.timerText:SetPoint("LEFT", cdRow.spellIcon, "RIGHT", COL_GAP, 0);
            end
        else
            -- Text mode: show spell name in nameText, hide icon
            cdRow.spellIcon:Hide();
            cdRow.nameText:ClearAllPoints();
            cdRow.nameText:SetPoint("LEFT", 0, 0);
            cdRow.nameText:SetWidth(cdSpellMax);
            cdRow.nameText:SetText(group.spellName);
            cdRow.nameText:SetTextColor(1, 1, 1);
            cdRow.nameText:Show();

            cdRow.timerText:ClearAllPoints();
            cdRow.timerText:SetPoint("LEFT", cdRow.nameText, "RIGHT", COL_GAP, 0);
        end

        cdRow.timerText:SetFont(FONT_PATH, cdFontSize, "OUTLINE");

        -- Determine best state: "Ready" if any alive caster is ready,
        -- shortest remaining CD if all alive are on CD, "DEAD" if all dead
        local allDead = true;
        local anyReady = false;
        local shortestRemaining = nil;
        local readyCount = 0;

        for _, c in ipairs(group.casters) do
            if not c.isDead then
                allDead = false;
                if c.expiryTime <= now then
                    anyReady = true;
                    readyCount = readyCount + 1;
                else
                    local rem = c.expiryTime - now;
                    if not shortestRemaining or rem < shortestRemaining then
                        shortestRemaining = rem;
                    end
                end
            end
        end

        -- For subgroupAware spells, check if any ready caster has an eligible healer in their subgroup
        local anyRequestable = false;
        local cdConfig = CD_REQUEST_CONFIG[group.spellId];
        if anyReady and cdConfig and cdConfig.subgroupAware then
            for _, c in ipairs(group.casters) do
                if not c.isDead and c.expiryTime <= now then
                    if previewActive or HasLowManaHealerInSubgroup(c.guid, cdConfig.threshold or 20) then
                        anyRequestable = true;
                        break;
                    end
                end
            end
        end
        cdRow.isRequestable = anyRequestable;

        if allDead then
            cdRow.timerText:SetText("DEAD");
            cdRow.timerText:SetTextColor(0.5, 0.5, 0.5);
            if not useIcons then
                cdRow.nameText:SetTextColor(0.5, 0.5, 0.5);
            end
            cdRow.isRequest = false;
            cdRow.requestPulse:Hide();
        elseif anyReady and anyRequestable then
            cdRow.timerText:SetText("Request (" .. readyCount .. ")");
            cdRow.timerText:SetTextColor(1.0, 0.8, 0.0);
            cdRow.isRequest = true;
            cdRow.requestPulse:Show();
        elseif anyReady then
            cdRow.timerText:SetText("Ready (" .. readyCount .. ")");
            cdRow.timerText:SetTextColor(0.0, 1.0, 0.0);
            cdRow.isRequest = false;
            cdRow.requestPulse:Hide();
        else
            local rem = shortestRemaining or 0;
            cdRow.timerText:SetText(format("%d:%02d", floor(rem / 60), floor(rem) % 60));
            cdRow.timerText:SetTextColor(0.8, 0.8, 0.8);
            cdRow.isRequest = false;
            cdRow.requestPulse:Hide();
        end

        cdRow:SetHeight(rowHeight);
        cdRow:ClearAllPoints();
        cdRow:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
        cdRow:SetPoint("RIGHT", targetFrame, "RIGHT", -2, 0);
        cdRow:Show();

        yOffset = yOffset - rowHeight;
    end

    -- Hide excess rows
    for i = #spellGroups + 1, #activeCdRows do
        activeCdRows[i]:Hide();
        activeCdRows[i].sourceGUID = nil;
        activeCdRows[i].spellId = nil;
        activeCdRows[i].spellGroup = nil;
        activeCdRows[i].isRequestable = nil;
        activeCdRows[i].isRequest = false;
        activeCdRows[i].requestPulse:Hide();
    end

    return yOffset, totalWidth;
end

-- Healer rows only on HealerWatchFrame (split mode)
local function RefreshHealerDisplay(sortedHealers)
    HideAllRows();

    local rowHeight = max(db.fontSize + 4, db.statusIcons and (db.iconSize + 2) or 0, 16);
    local maxNameWidth, maxManaWidth, maxStatusLabelWidth, maxStatusDurWidth = PrepareHealerRowData(sortedHealers);

    local contentWidth = maxNameWidth + COL_GAP + maxManaWidth;
    if maxStatusLabelWidth > 0 then
        contentWidth = contentWidth + COL_GAP + maxStatusLabelWidth;
        if maxStatusDurWidth > 0 then
            contentWidth = contentWidth + COL_GAP + maxStatusDurWidth;
        end
    end
    local totalWidth = max(LEFT_MARGIN + contentWidth + RIGHT_MARGIN, 120);

    local yOffset = -TOP_PADDING;

    if db.showAverageMana then
        local avgMana = GetAverageMana();
        local ar, ag, ab = GetManaColor(avgMana);
        HealerWatchFrame.title:SetFont(FONT_PATH, db.fontSize, "OUTLINE");
        HealerWatchFrame.title:SetFormattedText("Mana: |cff%02x%02x%02x%d%%|r",
            ar * 255, ag * 255, ab * 255, avgMana);
        HealerWatchFrame.title:Show();

        local titleWidth = MeasureText("Mana: 100%", db.fontSize) + LEFT_MARGIN + RIGHT_MARGIN;
        if titleWidth > totalWidth then totalWidth = titleWidth; end

        yOffset = yOffset - rowHeight;
        if db.headerBackground then
            HealerWatchFrame.separator:Hide();
            HealerWatchFrame.titleBg:ClearAllPoints();
            HealerWatchFrame.titleBg:SetPoint("TOPLEFT", HealerWatchFrame, "TOPLEFT", 0, 0);
            HealerWatchFrame.titleBg:SetPoint("TOPRIGHT", HealerWatchFrame, "TOPRIGHT", 0, 0);
            HealerWatchFrame.titleBg:SetHeight(TOP_PADDING + rowHeight);
            HealerWatchFrame.titleBg:Show();
        else
            HealerWatchFrame.titleBg:Hide();
            HealerWatchFrame.separator:ClearAllPoints();
            HealerWatchFrame.separator:SetPoint("TOPLEFT", HealerWatchFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
            HealerWatchFrame.separator:SetPoint("TOPRIGHT", HealerWatchFrame, "TOPRIGHT", -RIGHT_MARGIN, yOffset);
            HealerWatchFrame.separator:Show();
        end
        yOffset = yOffset - 4;
    else
        HealerWatchFrame.title:Hide();
        HealerWatchFrame.separator:Hide();
        HealerWatchFrame.titleBg:Hide();
    end

    -- Track content-driven minimums (used by resize handle to prevent clipping)
    contentMinWidth = totalWidth;

    -- Respect user-set width as minimum
    totalWidth = max(totalWidth, db.frameWidth or 120);

    yOffset = RenderHealerRows(HealerWatchFrame, yOffset, totalWidth, maxNameWidth, maxManaWidth, maxStatusLabelWidth, maxStatusDurWidth);

    -- Hide merged-mode cd elements
    HealerWatchFrame.cdTitle:Hide();
    HealerWatchFrame.cdSeparator:Hide();
    HealerWatchFrame.cdTitleBg:Hide();

    local totalHeight = -yOffset + BOTTOM_PADDING;
    contentMinHeight = totalHeight;

    -- Respect user-set height as minimum
    totalHeight = max(totalHeight, db.frameHeight or HEIGHT_MIN);

    HealerWatchFrame:SetHeight(totalHeight);
    HealerWatchFrame:SetWidth(totalWidth);
    HealerWatchFrame:Show();
end

-- Cooldown rows only on CooldownFrame (split mode)
local function RefreshCooldownDisplay()
    HideAllCdRows();

    if not db.showRaidCooldowns then
        CooldownFrame:Hide();
        return;
    end

    -- Check if there are any cooldowns to show
    local hasCooldowns = false;
    for _ in pairs(raidCooldowns) do
        hasCooldowns = true;
        break;
    end
    if not hasCooldowns then
        CooldownFrame:Hide();
        return;
    end

    local cdHasIcons = (db.cooldownDisplayMode ~= "text");
    local rowHeight = max(db.fontSize + 4, cdHasIcons and (db.iconSize + 2) or 0, 16);
    local yOffset = -TOP_PADDING;
    local totalWidth = 120;

    -- Title
    CooldownFrame.title:SetFont(FONT_PATH, db.fontSize, "OUTLINE");
    CooldownFrame.title:SetText("Cooldowns");
    CooldownFrame.title:Show();

    local titleWidth = MeasureText("Cooldowns", db.fontSize) + LEFT_MARGIN + RIGHT_MARGIN;
    if titleWidth > totalWidth then totalWidth = titleWidth; end

    yOffset = yOffset - rowHeight;
    if db.headerBackground then
        CooldownFrame.separator:Hide();
        CooldownFrame.titleBg:ClearAllPoints();
        CooldownFrame.titleBg:SetPoint("TOPLEFT", CooldownFrame, "TOPLEFT", 0, 0);
        CooldownFrame.titleBg:SetPoint("TOPRIGHT", CooldownFrame, "TOPRIGHT", 0, 0);
        CooldownFrame.titleBg:SetHeight(TOP_PADDING + rowHeight);
        CooldownFrame.titleBg:Show();
    else
        CooldownFrame.titleBg:Hide();
        CooldownFrame.separator:ClearAllPoints();
        CooldownFrame.separator:SetPoint("TOPLEFT", CooldownFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
        CooldownFrame.separator:SetPoint("TOPRIGHT", CooldownFrame, "TOPRIGHT", -RIGHT_MARGIN, yOffset);
        CooldownFrame.separator:Show();
    end
    yOffset = yOffset - 4;

    yOffset, totalWidth = RenderCooldownRows(CooldownFrame, yOffset, totalWidth);

    -- Track content-driven minimums (used by resize handle to prevent clipping)
    cdContentMinWidth = totalWidth;

    -- Respect user-set width as minimum
    totalWidth = max(totalWidth, db.cdFrameWidth or 120);

    local totalHeight = -yOffset + BOTTOM_PADDING;
    cdContentMinHeight = totalHeight;

    -- Respect user-set height as minimum
    totalHeight = max(totalHeight, db.cdFrameHeight or HEIGHT_MIN);

    CooldownFrame:SetHeight(totalHeight);
    CooldownFrame:SetWidth(totalWidth);
    CooldownFrame:Show();
end

-- Merged display: healer rows + cooldown rows on HealerWatchFrame (original behavior)
local function RefreshMergedDisplay(sortedHealers)
    HideAllRows();

    local iconH = 0;
    if db.statusIcons or db.cooldownDisplayMode ~= "text" then iconH = db.iconSize + 2; end
    local rowHeight = max(db.fontSize + 4, iconH, 16);
    local maxNameWidth, maxManaWidth, maxStatusLabelWidth, maxStatusDurWidth = PrepareHealerRowData(sortedHealers);

    local contentWidth = maxNameWidth + COL_GAP + maxManaWidth;
    if maxStatusLabelWidth > 0 then
        contentWidth = contentWidth + COL_GAP + maxStatusLabelWidth;
        if maxStatusDurWidth > 0 then
            contentWidth = contentWidth + COL_GAP + maxStatusDurWidth;
        end
    end
    local totalWidth = max(LEFT_MARGIN + contentWidth + RIGHT_MARGIN, 120);

    local yOffset = -TOP_PADDING;

    if db.showAverageMana then
        local avgMana = GetAverageMana();
        local ar, ag, ab = GetManaColor(avgMana);
        HealerWatchFrame.title:SetFont(FONT_PATH, db.fontSize, "OUTLINE");
        HealerWatchFrame.title:SetFormattedText("Mana: |cff%02x%02x%02x%d%%|r",
            ar * 255, ag * 255, ab * 255, avgMana);
        HealerWatchFrame.title:Show();

        local titleWidth = MeasureText("Mana: 100%", db.fontSize) + LEFT_MARGIN + RIGHT_MARGIN;
        if titleWidth > totalWidth then totalWidth = titleWidth; end

        yOffset = yOffset - rowHeight;
        if db.headerBackground then
            HealerWatchFrame.separator:Hide();
            HealerWatchFrame.titleBg:ClearAllPoints();
            HealerWatchFrame.titleBg:SetPoint("TOPLEFT", HealerWatchFrame, "TOPLEFT", 0, 0);
            HealerWatchFrame.titleBg:SetPoint("TOPRIGHT", HealerWatchFrame, "TOPRIGHT", 0, 0);
            HealerWatchFrame.titleBg:SetHeight(TOP_PADDING + rowHeight);
            HealerWatchFrame.titleBg:Show();
        else
            HealerWatchFrame.titleBg:Hide();
            HealerWatchFrame.separator:ClearAllPoints();
            HealerWatchFrame.separator:SetPoint("TOPLEFT", HealerWatchFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
            HealerWatchFrame.separator:SetPoint("TOPRIGHT", HealerWatchFrame, "TOPRIGHT", -RIGHT_MARGIN, yOffset);
            HealerWatchFrame.separator:Show();
        end
        yOffset = yOffset - 4;
    else
        HealerWatchFrame.title:Hide();
        HealerWatchFrame.separator:Hide();
        HealerWatchFrame.titleBg:Hide();
    end

    yOffset = RenderHealerRows(HealerWatchFrame, yOffset, totalWidth, maxNameWidth, maxManaWidth, maxStatusLabelWidth, maxStatusDurWidth);

    -- Raid cooldown section (merged)
    HideAllCdRows();
    HealerWatchFrame.cdTitle:Hide();
    HealerWatchFrame.cdSeparator:Hide();
    HealerWatchFrame.cdTitleBg:Hide();

    if db.showRaidCooldowns then
        -- Check if there are cooldowns
        local hasCooldowns = false;
        for _ in pairs(raidCooldowns) do
            hasCooldowns = true;
            break;
        end

        if hasCooldowns then
            -- "Cooldowns" title (centered, like Avg Mana)
            local cdSectionTop = yOffset;
            yOffset = yOffset - TOP_PADDING;
            HealerWatchFrame.cdTitle:SetFont(FONT_PATH, db.fontSize, "OUTLINE");
            HealerWatchFrame.cdTitle:SetTextColor(1, 0.82, 0);
            HealerWatchFrame.cdTitle:ClearAllPoints();
            HealerWatchFrame.cdTitle:SetPoint("TOPLEFT", HealerWatchFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
            HealerWatchFrame.cdTitle:Show();

            local cdTitleWidth = MeasureText("Cooldowns", db.fontSize) + LEFT_MARGIN + RIGHT_MARGIN;
            if cdTitleWidth > totalWidth then totalWidth = cdTitleWidth; end

            yOffset = yOffset - rowHeight;

            if db.headerBackground then
                HealerWatchFrame.cdSeparator:Hide();
                HealerWatchFrame.cdTitleBg:ClearAllPoints();
                HealerWatchFrame.cdTitleBg:SetPoint("TOPLEFT", HealerWatchFrame, "TOPLEFT", 0, cdSectionTop);
                HealerWatchFrame.cdTitleBg:SetPoint("TOPRIGHT", HealerWatchFrame, "TOPRIGHT", 0, cdSectionTop);
                HealerWatchFrame.cdTitleBg:SetHeight(TOP_PADDING + rowHeight);
                HealerWatchFrame.cdTitleBg:Show();
            else
                HealerWatchFrame.cdTitleBg:Hide();
                HealerWatchFrame.cdSeparator:ClearAllPoints();
                HealerWatchFrame.cdSeparator:SetPoint("TOPLEFT", HealerWatchFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
                HealerWatchFrame.cdSeparator:SetPoint("TOPRIGHT", HealerWatchFrame, "TOPRIGHT", -RIGHT_MARGIN, yOffset);
                HealerWatchFrame.cdSeparator:Show();
            end
            yOffset = yOffset - 4;

            yOffset, totalWidth = RenderCooldownRows(HealerWatchFrame, yOffset, totalWidth);
        end
    end

    -- Track content-driven minimums (used by resize handle to prevent clipping)
    contentMinWidth = totalWidth;

    -- Respect user-set width as minimum
    totalWidth = max(totalWidth, db.frameWidth or 120);

    local totalHeight = -yOffset + BOTTOM_PADDING;
    contentMinHeight = totalHeight;

    -- Respect user-set height as minimum
    totalHeight = max(totalHeight, db.frameHeight or HEIGHT_MIN);

    HealerWatchFrame:SetHeight(totalHeight);
    HealerWatchFrame:SetWidth(totalWidth);
    HealerWatchFrame:Show();
end

-- Dispatcher
RefreshDisplay = function()
    if not db or not db.enabled then
        HealerWatchFrame:Hide();
        CooldownFrame:Hide();
        return;
    end

    if not previewActive and not IsInGroup() then
        HealerWatchFrame:Hide();
        CooldownFrame:Hide();
        return;
    end

    local sortedHealers = GetSortedHealers();
    if #sortedHealers == 0 then
        HealerWatchFrame:Hide();
        CooldownFrame:Hide();
        return;
    end

    if db.splitFrames then
        RefreshHealerDisplay(sortedHealers);
        RefreshCooldownDisplay();
    else
        CooldownFrame:Hide();
        RefreshMergedDisplay(sortedHealers);
    end
end

--------------------------------------------------------------------------------
-- OnUpdate Handler
--------------------------------------------------------------------------------

local previewTimer = 0;
local previewFromSettings = false;

-- Per-frame OnUpdate disabled (resize handles disabled, no other per-frame work needed)

-- Background OnUpdate: drives ALL periodic logic (always runs, avoids hidden-frame deadlock)
local BackgroundFrame = CreateFrame("Frame");
BackgroundFrame:SetScript("OnUpdate", function(self, elapsed)
    -- Stop settings preview when panel closes
    if previewFromSettings and SettingsPanel and not SettingsPanel:IsShown() then
        StopPreview();
        previewFromSettings = false;
    end

    -- Inspect queue (skip during preview)
    if not previewActive then
        inspectElapsed = inspectElapsed + elapsed;
        if inspectElapsed >= INSPECT_REQUEUE_INTERVAL then
            inspectElapsed = 0;
            if #inspectQueue == 0 and not inspectPending then
                for guid, data in pairs(healers) do
                    if data.unit and UnitExists(data.unit) and UnitIsVisible(data.unit)
                        and CheckInteractDistance(data.unit, 4) then
                        if not data.inspectConfirmed and HEALER_CAPABLE_CLASSES[data.classFile] then
                            QueueInspect(data.unit);
                        end
                    end
                end
            end
            ProcessInspectQueue();
        end
    end

    -- Broadcaster heartbeat + stale pruning
    if not previewActive then
        heartbeatElapsed = heartbeatElapsed + elapsed;
        if heartbeatElapsed >= HEARTBEAT_INTERVAL then
            heartbeatElapsed = 0;
            RegisterSelf();
            if IsInGroup() then
                BroadcastHello();
                BroadcastSpec();
            end
            -- Prune stale healerWatchUsers
            local now = GetTime();
            local playerName = UnitName("player");
            for uname, udata in pairs(healerWatchUsers) do
                if uname ~= playerName and now - udata.lastSeen > STALE_TIMEOUT then
                    healerWatchUsers[uname] = nil;
                    if overrideBroadcaster == uname then
                        overrideBroadcaster = nil;
                    end
                end
            end
        end
    end

    -- Throttled display update
    updateElapsed = updateElapsed + elapsed;
    if updateElapsed >= UPDATE_INTERVAL then
        updateElapsed = 0;

        if previewActive then
            previewTimer = previewTimer + UPDATE_INTERVAL;
            local now = GetTime();
            for guid, data in pairs(healers) do
                if data.isHealer and data.baseMana then
                    local seed = (data.driftSeed or 1);
                    local drift = sin(previewTimer * 0.4 * seed) * 0.8 + cos(previewTimer * 0.15 * seed) * 0.5;
                    data.manaPercent = max(0, min(100, data.baseMana + floor(drift * 12)));
                    if data.isDrinking and data.drinkExpiry > 0 and data.drinkExpiry <= now then
                        data.drinkExpiry = now + 18;
                    end
                    if data.hasInnervate and data.innervateExpiry > 0 and data.innervateExpiry <= now then
                        data.innervateExpiry = now + 12;
                    end
                    if data.hasManaTide and data.manaTideExpiry > 0 and data.manaTideExpiry <= now then
                        data.manaTideExpiry = now + 8;
                    end
                    if data.hasSymbolOfHope and data.symbolOfHopeExpiry > 0 and data.symbolOfHopeExpiry <= now then
                        data.symbolOfHopeExpiry = now + 15;
                    end
                    if data.potionExpiry > 0 and data.potionExpiry <= now then
                        data.potionExpiry = now + 90;
                    end
                end
            end
            for key, entry in pairs(raidCooldowns) do
                if entry.expiryTime <= now then
                    if key:sub(1, 8) == "preview-" then
                        -- Leave expired so they show "Ready" / "Request"
                    else
                        entry.expiryTime = now + RAID_COOLDOWN_SPELLS[entry.spellId].duration;
                    end
                end
            end
        else
            UpdateManaValues();
            CheckManaWarnings();
        end

        RefreshDisplay();

        -- Safety net: ensure resize handles match hover state (OnLeave can miss at edges)
        UpdateResizeHandleVisibility();
        UpdateCdResizeHandleVisibility();
    end

    -- Pulse animations (runs every frame for smooth fade)
    local pulseAlpha = (sin(GetTime() * 270) + 1) * 0.15 + 0.05;  -- 0.05 to 0.35, ~1.3s cycle
    for i = 1, #activeCdRows do
        local cdRow = activeCdRows[i];
        if cdRow.isRequest then
            cdRow.requestPulse:SetAlpha(pulseAlpha);
        end
    end
    for i = 1, #activeRows do
        local row = activeRows[i];
        if row.needsRebirth then
            row.deadPulse:SetAlpha(pulseAlpha);
        end
    end
end);

--------------------------------------------------------------------------------
-- Preview System
--------------------------------------------------------------------------------

local PREVIEW_DATA = {
    { name = "Holypriest", classFile = "PRIEST", baseMana = 82, hasPotion = true, hasSymbolOfHope = true, driftSeed = 1.0 },
    { name = "Treehugger", classFile = "DRUID", baseMana = 45, isDrinking = true, driftSeed = 1.4 },
    { name = "Palaheals", classFile = "PALADIN", baseMana = 18, hasInnervate = true, driftSeed = 0.7 },
    { name = "Tidecaller", classFile = "SHAMAN", baseMana = 64, hasManaTide = true, driftSeed = 1.2 },
    { name = "Potionboy", classFile = "PALADIN", baseMana = 55, hasPotion = true, driftSeed = 0.9 },
    { name = "Soulstoned", classFile = "PALADIN", hasSoulstone = true, driftSeed = 0 },
    { name = "Rebirthed", classFile = "PRIEST", hasRebirth = true, driftSeed = 0 },
    { name = "Deadweight", classFile = "SHAMAN", driftSeed = 0 },  -- dead, no buffs (pulses when rebirth available)
};

StartPreview = function()
    if previewActive then return; end
    previewActive = true;
    previewTimer = 0;

    -- Save real healer data
    savedHealers = {};
    for guid, data in pairs(healers) do
        savedHealers[guid] = data;
    end

    -- Inject mock data
    wipe(healers);
    for i, td in ipairs(PREVIEW_DATA) do
        local fakeGUID = "preview-guid-" .. i;
        healers[fakeGUID] = {
            guid = fakeGUID,
            unit = nil,
            name = td.name,
            classFile = td.classFile,
            isHealer = true,
            inspectConfirmed = true,
            manaPercent = td.baseMana or -2,
            baseMana = td.baseMana,
            driftSeed = td.driftSeed,
            isDrinking = td.isDrinking or false,
            hasInnervate = td.hasInnervate or false,
            hasManaTide = td.hasManaTide or false,
            hasSoulstone = td.hasSoulstone or false,
            hasRebirth = td.hasRebirth or false,
            hasSymbolOfHope = td.hasSymbolOfHope or false,
            drinkExpiry = td.isDrinking and (GetTime() + 18) or 0,
            innervateExpiry = td.hasInnervate and (GetTime() + 12) or 0,
            manaTideExpiry = td.hasManaTide and (GetTime() + 8) or 0,
            symbolOfHopeExpiry = td.hasSymbolOfHope and (GetTime() + 15) or 0,
            potionExpiry = td.hasPotion and (GetTime() + 90) or 0,
        };
    end

    -- Inject mock group members (includes non-healers for Rebirth/Soulstone target lists)
    wipe(previewGroupMembers);
    -- All healers from PREVIEW_DATA
    for i, td in ipairs(PREVIEW_DATA) do
        local fakeGUID = "preview-guid-" .. i;
        tinsert(previewGroupMembers, { guid = fakeGUID, name = td.name, classFile = td.classFile,
            isDead = not td.baseMana, hasSoulstone = td.hasSoulstone or false, hasRebirth = td.hasRebirth or false });
    end
    -- Non-healer mock members
    tinsert(previewGroupMembers, { guid = "preview-guid-dps1", name = "Stabsworth", classFile = "ROGUE", isDead = true, hasSoulstone = false, hasRebirth = false });
    tinsert(previewGroupMembers, { guid = "preview-guid-dps2", name = "Arcanox", classFile = "MAGE", isDead = false, hasSoulstone = false, hasRebirth = false });
    tinsert(previewGroupMembers, { guid = "preview-guid-tank1", name = "Meatshield", classFile = "WARRIOR", isDead = false, hasSoulstone = true, hasRebirth = false });

    -- Save and inject mock subgroups
    savedMemberSubgroups = {};
    for guid, subgroup in pairs(memberSubgroups) do
        savedMemberSubgroups[guid] = subgroup;
    end
    wipe(memberSubgroups);
    memberSubgroups["preview-guid-1"] = 1;  -- Holypriest
    memberSubgroups["preview-guid-2"] = 1;  -- Treehugger
    memberSubgroups["preview-guid-3"] = 2;  -- Palaheals
    memberSubgroups["preview-guid-4"] = 2;  -- Tidecaller
    memberSubgroups["preview-guid-5"] = 1;  -- Potionboy
    memberSubgroups["preview-guid-6"] = 2;  -- Soulstoned
    memberSubgroups["preview-guid-ss"] = 1; -- Shadowlock (warlock)
    memberSubgroups["preview-guid-ss2"] = 2; -- Demonlock (warlock)
    memberSubgroups["preview-guid-druid2"] = 1; -- Barkskin (druid)

    -- Save and inject mock raid cooldowns
    savedRaidCooldowns = {};
    for key, entry in pairs(raidCooldowns) do
        savedRaidCooldowns[key] = entry;
    end
    wipe(raidCooldowns);
    local now = GetTime();
    local innervateInfo = RAID_COOLDOWN_SPELLS[INNERVATE_SPELL_ID];
    local manaTideInfo = RAID_COOLDOWN_SPELLS[MANA_TIDE_CAST_SPELL_ID];
    -- Bloodlust/Heroism preview disabled for now
    -- local bloodlustInfo = RAID_COOLDOWN_SPELLS[BLOODLUST_SPELL_ID];
    -- local heroismInfo = RAID_COOLDOWN_SPELLS[HEROISM_SPELL_ID];
    -- local isHorde = (UnitFactionGroup("player") == "Horde");
    -- local blInfo = isHorde and bloodlustInfo or heroismInfo;
    -- local blSpellId = isHorde and BLOODLUST_SPELL_ID or HEROISM_SPELL_ID;
    -- Use guid-spellId keys so tooltip lookups work in preview
    raidCooldowns["preview-guid-2-" .. INNERVATE_SPELL_ID] = {
        sourceGUID = "preview-guid-2",
        name = "Treehugger",
        classFile = "DRUID",
        spellId = INNERVATE_SPELL_ID,
        icon = innervateInfo.icon,
        spellName = innervateInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    raidCooldowns["preview-guid-2-20484"] = {
        sourceGUID = "preview-guid-2",
        name = "Treehugger",
        classFile = "DRUID",
        spellId = 20484,
        icon = rebirthInfo.icon,
        spellName = rebirthInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    raidCooldowns["preview-guid-4-" .. MANA_TIDE_CAST_SPELL_ID] = {
        sourceGUID = "preview-guid-4",
        name = "Tidecaller",
        classFile = "SHAMAN",
        spellId = MANA_TIDE_CAST_SPELL_ID,
        icon = manaTideInfo.icon,
        spellName = manaTideInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    -- Bloodlust/Heroism preview disabled for now
    -- raidCooldowns["preview-guid-4-" .. blSpellId] = {
    --     sourceGUID = "preview-guid-4",
    --     name = "Tidecaller",
    --     classFile = "SHAMAN",
    --     spellId = blSpellId,
    --     icon = blInfo.icon,
    --     spellName = blInfo.name,
    --     expiryTime = now + 420,
    -- };
    raidCooldowns["preview-guid-ss-20707"] = {
        sourceGUID = "preview-guid-ss",
        name = "Shadowlock",
        classFile = "WARLOCK",
        spellId = 20707,
        icon = soulstoneInfo.icon,
        spellName = soulstoneInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    -- Power Infusion preview disabled for now
    -- local piInfo = RAID_COOLDOWN_SPELLS[POWER_INFUSION_SPELL_ID];
    -- raidCooldowns["preview-guid-1-" .. POWER_INFUSION_SPELL_ID] = {
    --     sourceGUID = "preview-guid-1",
    --     name = "Holypriest",
    --     classFile = "PRIEST",
    --     spellId = POWER_INFUSION_SPELL_ID,
    --     icon = piInfo.icon,
    --     spellName = piInfo.name,
    --     expiryTime = now - 1,
    -- };
    local sohInfo = RAID_COOLDOWN_SPELLS[SYMBOL_OF_HOPE_SPELL_ID];
    raidCooldowns["preview-guid-1-" .. SYMBOL_OF_HOPE_SPELL_ID] = {
        sourceGUID = "preview-guid-1",
        name = "Holypriest",
        classFile = "PRIEST",
        spellId = SYMBOL_OF_HOPE_SPELL_ID,
        icon = sohInfo.icon,
        spellName = sohInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    local sfInfo = RAID_COOLDOWN_SPELLS[34433];
    raidCooldowns["preview-guid-1-" .. 34433] = {
        sourceGUID = "preview-guid-1",
        name = "Holypriest",
        classFile = "PRIEST",
        spellId = 34433,
        icon = sfInfo.icon,
        spellName = sfInfo.name,
        expiryTime = now + 180,  -- on CD
    };
    raidCooldowns["preview-guid-7-" .. 34433] = {
        sourceGUID = "preview-guid-7",
        name = "Rebirthed",
        classFile = "PRIEST",
        spellId = 34433,
        icon = sfInfo.icon,
        spellName = sfInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    -- Duplicate casters to demonstrate spell grouping
    raidCooldowns["preview-guid-druid2-" .. INNERVATE_SPELL_ID] = {
        sourceGUID = "preview-guid-druid2",
        name = "Barkskin",
        classFile = "DRUID",
        spellId = INNERVATE_SPELL_ID,
        icon = innervateInfo.icon,
        spellName = innervateInfo.name,
        expiryTime = now + 180,  -- on CD
    };
    raidCooldowns["preview-guid-druid2-20484"] = {
        sourceGUID = "preview-guid-druid2",
        name = "Barkskin",
        classFile = "DRUID",
        spellId = 20484,
        icon = rebirthInfo.icon,
        spellName = rebirthInfo.name,
        expiryTime = now + 900,  -- on CD
    };
    raidCooldowns["preview-guid-ss2-20707"] = {
        sourceGUID = "preview-guid-ss2",
        name = "Demonlock",
        classFile = "WARLOCK",
        spellId = 20707,
        icon = soulstoneInfo.icon,
        spellName = soulstoneInfo.name,
        expiryTime = now + 1200,  -- on CD
    };

    -- Unlock frames for dragging while options are open
    HealerWatchFrame:EnableMouse(true);
    CooldownFrame:EnableMouse(true);
    RefreshDisplay();
end

StopPreview = function()
    if not previewActive then return; end
    previewActive = false;

    -- Restore real healer data
    wipe(healers);
    if savedHealers then
        for guid, data in pairs(savedHealers) do
            healers[guid] = data;
        end
        savedHealers = nil;
    end

    wipe(previewGroupMembers);

    -- Restore real raid cooldowns
    wipe(raidCooldowns);
    if savedRaidCooldowns then
        for key, entry in pairs(savedRaidCooldowns) do
            raidCooldowns[key] = entry;
        end
        savedRaidCooldowns = nil;
    end

    -- Restore real subgroup data
    wipe(memberSubgroups);
    if savedMemberSubgroups then
        for guid, subgroup in pairs(savedMemberSubgroups) do
            memberSubgroups[guid] = subgroup;
        end
        savedMemberSubgroups = nil;
    end

    HideContextMenu();

    -- Restore lock state and frame strata
    HealerWatchFrame:EnableMouse(not db.locked);
    HealerWatchFrame:SetFrameStrata("MEDIUM");
    CooldownFrame:EnableMouse(not db.locked);
    CooldownFrame:SetFrameStrata("MEDIUM");

    RefreshDisplay();
end

--------------------------------------------------------------------------------
-- Options GUI (native Settings API)
--------------------------------------------------------------------------------

local healerWatchCategoryID;

-- Sort value mapping (Settings dropdown uses numeric keys)
local SORT_MAP = { [1] = "mana", [2] = "name" };
local SORT_REVERSE = { mana = 1, name = 2 };

-- Cooldown display mode mapping
local CD_MODE_MAP = { [1] = "text", [2] = "icons", [3] = "icons_labels" };
local CD_MODE_REVERSE = { text = 1, icons = 2, icons_labels = 3 };

local function RegisterSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("HealerWatch");

    -- Helper: register a boolean proxy setting + checkbox
    local function AddCheckbox(key, name, tooltip, onChange)
        local setting = Settings.RegisterProxySetting(category,
            "HEALERWATCH_" .. key:upper(), Settings.VarType.Boolean, name,
            DEFAULT_SETTINGS[key],
            function() return db[key]; end,
            function(value)
                db[key] = value;
                if onChange then onChange(value); end
            end);
        return Settings.CreateCheckbox(category, setting, tooltip);
    end

    -- Helper: register a numeric proxy setting + slider
    local function AddSlider(key, name, tooltip, minVal, maxVal, step, onChange, getFn, setFn)
        local setting = Settings.RegisterProxySetting(category,
            "HEALERWATCH_" .. key:upper(), Settings.VarType.Number, name,
            getFn and getFn(DEFAULT_SETTINGS[key]) or DEFAULT_SETTINGS[key],
            getFn and function() return getFn(db[key]); end or function() return db[key]; end,
            function(value)
                if setFn then
                    db[key] = setFn(value);
                else
                    db[key] = value;
                end
                if onChange then onChange(value); end
            end);
        local options = Settings.CreateSliderOptions(minVal, maxVal, step);
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right);
        return Settings.CreateSlider(category, setting, options, tooltip);
    end

    -------------------------
    -- Section: Display
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Display"));

    AddCheckbox("enabled", "Enable HealerWatch",
        "Toggle the HealerWatch display on or off.",
        function() RefreshDisplay(); end);

    AddCheckbox("showAverageMana", "Show Average Mana",
        "Display the average mana percentage across all healers in the header row.");

    AddCheckbox("locked", "Lock Frame Position",
        "Prevent the frames from being dragged.",
        function(value)
            HealerWatchFrame:EnableMouse(not value);
            CooldownFrame:EnableMouse(not value);
            UpdateResizeHandleVisibility();
            UpdateCdResizeHandleVisibility();
        end);

    AddCheckbox("splitFrames", "Separate Cooldown Frame",
        "Show cooldowns in a separate, independently movable frame. When disabled, cooldowns appear below the healer mana list in a single combined frame.",
        function() RefreshDisplay(); end);

    -- Sort dropdown
    local sortSetting = Settings.RegisterProxySetting(category,
        "HEALERWATCH_SORT_BY", Settings.VarType.Number, "Sort Healers By",
        SORT_REVERSE[DEFAULT_SETTINGS.sortBy] or 1,
        function() return SORT_REVERSE[db.sortBy] or 1; end,
        function(value) db.sortBy = SORT_MAP[value] or "mana"; end);
    local function GetSortOptions()
        local container = Settings.CreateControlTextContainer();
        container:Add(1, "Lowest Mana First");
        container:Add(2, "Name (A-Z)");
        return container:GetData();
    end
    Settings.CreateDropdown(category, sortSetting, GetSortOptions,
        "How to order healers in the display.");

    -- Tooltip anchor dropdown
    local anchorSetting = Settings.RegisterProxySetting(category,
        "HEALERWATCH_TOOLTIP_ANCHOR", Settings.VarType.Number, "Tooltip Position",
        db.tooltipAnchor == "right" and 2 or 1,
        function() return db.tooltipAnchor == "right" and 2 or 1; end,
        function(value) db.tooltipAnchor = value == 2 and "right" or "left"; end);
    Settings.CreateDropdown(category, anchorSetting, function()
        local container = Settings.CreateControlTextContainer();
        container:Add(1, "Left of Frame");
        container:Add(2, "Right of Frame");
        return container:GetData();
    end, "Preferred side for tooltips. Automatically flips to the other side if there isn't enough screen space.");

    -------------------------
    -- Section: Healer Status Indicators
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Healer Status Indicators"));

    AddCheckbox("showDrinking", "Drinking",
        "Indicate when a healer is drinking to restore mana.");

    AddCheckbox("showInnervate", "Innervate",
        "Indicate when a healer has Innervate active.");

    AddCheckbox("showManaTide", "Mana Tide",
        "Indicate when a healer is affected by Mana Tide Totem.");

    AddCheckbox("showPotionCooldown", "Potion Cooldowns",
        "Display mana potion cooldown timers.");

    AddCheckbox("showRebirth", "Rebirth",
        "Indicate pending Rebirth on dead healers who have been battle-rezzed. Shown as an orange status label or icon on the healer row.");

    AddCheckbox("showSoulstone", "Soulstone",
        "Indicate Soulstone on dead healers who have the buff. Shown as a purple status label or icon on the healer row.");

    AddCheckbox("showSymbolOfHope", "Symbol of Hope",
        "Indicate when a healer is receiving mana from Symbol of Hope.");

    AddCheckbox("showStatusDuration", "Buff Durations",
        "Show remaining seconds on active buffs like Innervate, Mana Tide, and Drinking.");

    AddCheckbox("statusIcons", "Status Icons",
        "Show spell icons instead of text labels for healer status indicators (Drinking, Innervate, etc.).");

    AddCheckbox("showRowHighlight", "Row Hover Highlight",
        "Highlight rows on mouse hover. Helps identify which row you're about to click when using Click-to-Request.");

    local cdReqInit = AddCheckbox("enableCdRequest", "Click-to-Request Cooldowns",
        "Left-click rows to request cooldowns via whisper.\n\nHealer rows: Alive healers open a menu of available cooldowns (Innervate, Soulstone). Dead healers with a Soulstone or Rebirth buff are whispered to accept it. Dead healers with an amber pulse are matched to the best available Rebirth druid.\n\nCooldown rows: Innervate, Rebirth, and Soulstone open a target selection menu. Mana Tide and Symbol of Hope whisper the caster directly when the amber Request pulse is active.");

    local innThreshInit = AddSlider("innervateRequestThreshold", "Innervate Target Threshold (%)",
        "When clicking an Innervate cooldown row, only show targets at or below this mana percentage. Set to 100 to always show all mana users.",
        0, 100, 5);
    innThreshInit:SetParentInitializer(cdReqInit,
        function() return db.enableCdRequest; end);

    -------------------------
    -- Section: Cooldown Tracking
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Cooldown Tracking"));

    AddCheckbox("showRaidCooldowns", "Enable Cooldown Tracking",
        "Track group cooldowns with Ready/on-cooldown timers in a dedicated section.\n\nGreen 'Ready' means at least one caster is alive and off cooldown. An amber 'Request' pulse on Mana Tide or Symbol of Hope means a healer in the caster's subgroup is low on mana — click to whisper them. Grey timers show the shortest remaining cooldown.");

    -- AddCheckbox("cdBloodlustHeroism", "Bloodlust / Heroism",  -- disabled for now
    --     "Track Bloodlust and Heroism cooldowns in the cooldown section.");

    AddCheckbox("cdInnervate", "Innervate",
        "Track Innervate cooldowns in the cooldown section.");

    AddCheckbox("cdManaTide", "Mana Tide",
        "Track Mana Tide Totem cooldowns in the cooldown section.");

    -- AddCheckbox("cdPowerInfusion", "Power Infusion",  -- disabled for now
    --     "Track Power Infusion cooldowns in the cooldown section.");

    AddCheckbox("cdRebirth", "Rebirth",
        "Track Rebirth cooldowns in the cooldown section.");

    AddCheckbox("cdSoulstone", "Soulstone",
        "Track Soulstone cooldowns in the cooldown section.");

    AddCheckbox("cdSymbolOfHope", "Symbol of Hope",
        "Track Symbol of Hope cooldowns in the cooldown section.");

    -- Cooldown display mode dropdown
    local cdModeSetting = Settings.RegisterProxySetting(category,
        "HEALERWATCH_CD_DISPLAY_MODE", Settings.VarType.Number, "Cooldown Display Mode",
        CD_MODE_REVERSE[DEFAULT_SETTINGS.cooldownDisplayMode] or 3,
        function() return CD_MODE_REVERSE[db.cooldownDisplayMode] or 3; end,
        function(value) db.cooldownDisplayMode = CD_MODE_MAP[value] or "icons_labels"; end);
    local function GetCdModeOptions()
        local container = Settings.CreateControlTextContainer();
        container:Add(1, "Text Only");
        container:Add(2, "Icons Only");
        container:Add(3, "Icons + Labels");
        return container:GetData();
    end
    Settings.CreateDropdown(category, cdModeSetting, GetCdModeOptions,
        "How cooldowns are displayed: text names, icons, or icons with labels.");

    -------------------------
    -- Section: Appearance
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Appearance"));

    AddCheckbox("headerBackground", "Header Background",
        "Show a shaded background behind header rows instead of a separator line.");

    AddSlider("fontSize", "Font Size",
        "Text size for healer names and mana percentages.",
        8, 24, 1);

    AddSlider("iconSize", "Icon Size",
        "Size of spell icons for status indicators and cooldowns.",
        10, 32, 1);

    AddSlider("scale", "Scale",
        "Overall scale of both frames, as a percentage (100% = default size).",
        50, 200, 10,
        function(value)
            HealerWatchFrame:SetScale(value / 100);
            CooldownFrame:SetScale(value / 100);
        end,
        function(raw) return floor(raw * 100 + 0.5); end,
        function(value) return value / 100; end);

    AddSlider("bgOpacity", "Display Opacity (%)",
        "Background opacity of both frames.",
        0, 100, 5,
        function(value)
            HealerWatchFrame:SetBackdropColor(0, 0, 0, value / 100);
            CooldownFrame:SetBackdropColor(0, 0, 0, value / 100);
        end,
        function(raw) return floor(raw * 100 + 0.5); end,
        function(value) return value / 100; end);

    -------------------------
    -- Section: Mana Color Thresholds
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Mana Color Thresholds"));

    AddSlider("colorThresholdGreen", "Green (above %)",
        "Mana percentage above which the text color is green.",
        50, 100, 5);

    AddSlider("colorThresholdYellow", "Yellow (above %)",
        "Mana percentage above which the text color is yellow.",
        25, 75, 5);

    AddSlider("colorThresholdOrange", "Orange (above %)",
        "Mana percentage above which the text color is orange. Below this value, text is red.",
        0, 50, 5);

    -------------------------
    -- Section: Chat Warnings
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Chat Warnings"));

    local sendWarnInit = AddCheckbox("sendWarnings", "Send Warning Messages",
        "Send a chat warning to party/raid when average healer mana drops below the warning threshold. When multiple players have HealerWatch, only the elected broadcaster sends warnings. Use /hwatch sync to see the broadcaster.");

    local warnCdInit = AddSlider("warningCooldown", "Warning Cooldown (sec)",
        "After a warning is sent, wait at least this many seconds before sending another. Prevents chat spam during sustained low mana.",
        10, 120, 5);
    warnCdInit:SetParentInitializer(sendWarnInit,
        function() return db.sendWarnings; end);

    local warnThreshInit = AddSlider("warningThreshold", "Warning Threshold (%)",
        "Send a warning to party/raid chat when average healer mana drops to or below this percentage. The warning resets once mana recovers above this value.",
        1, 50, 1);
    warnThreshInit:SetParentInitializer(sendWarnInit,
        function() return db.sendWarnings; end);

    Settings.RegisterAddOnCategory(category);
    healerWatchCategoryID = category:GetID();
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local EventFrame = CreateFrame("Frame");

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...;
        if loadedAddon ~= addonName then return; end

        -- Initialize SavedVariables
        if not HealerWatchDB then
            HealerWatchDB = {};
        end

        -- Copy defaults for missing keys
        for key, value in pairs(DEFAULT_SETTINGS) do
            if HealerWatchDB[key] == nil then
                HealerWatchDB[key] = value;
            end
        end

        db = HealerWatchDB;

        -- Clean up removed settings
        db.optionsBgOpacity = nil;
        db.warningThresholdHigh = nil;
        db.warningThresholdMed = nil;
        db.warningThresholdLow = nil;
        db.shortenedStatus = nil;
        db.showSolo = nil;
        db.sendWarningsSolo = nil;

        -- Migrate cooldownIcons/cooldownIconLabels → cooldownDisplayMode
        if db.cooldownIcons ~= nil then
            if not db.cooldownIcons then
                db.cooldownDisplayMode = "text";
            elseif db.cooldownIconLabels then
                db.cooldownDisplayMode = "icons_labels";
            else
                db.cooldownDisplayMode = "icons";
            end
            db.cooldownIcons = nil;
            db.cooldownIconLabels = nil;
        end

        -- Register native settings panel
        RegisterSettings();

        -- Apply saved position (healer frame)
        if db.frameX and db.frameY then
            HealerWatchFrame:ClearAllPoints();
            HealerWatchFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.frameX, db.frameY);
        else
            HealerWatchFrame:SetPoint("LEFT", UIParent, "LEFT", 20, 100);
        end

        -- Apply saved position (cooldown frame — default below healer frame)
        if db.cdFrameX and db.cdFrameY then
            CooldownFrame:ClearAllPoints();
            CooldownFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.cdFrameX, db.cdFrameY);
        else
            local healerLeft = db.frameX or 20;
            local healerTop = db.frameY or (UIParent:GetHeight() / 2 + 100);
            CooldownFrame:ClearAllPoints();
            CooldownFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", healerLeft, healerTop - 150);
        end

        -- Apply settings to both frames
        HealerWatchFrame:SetScale(db.scale);
        HealerWatchFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        HealerWatchFrame:EnableMouse(not db.locked);
        CooldownFrame:SetScale(db.scale);
        CooldownFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        CooldownFrame:EnableMouse(not db.locked);
    
        UpdateResizeHandleVisibility();

        self:UnregisterEvent("ADDON_LOADED");

        -- Register addon message prefix for cross-zone cooldown sync
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_MSG_PREFIX);

        print("|cff00ff00HealerWatch|r loaded. Type |cff00ffff/healerwatch|r or visit Options > AddOns.");

    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player");
        isFreshLogin = true;  -- GetSpellCooldown unreliable shortly after login
        RegisterSelf();
        if IsInGroup() then
            ScanGroupComposition();
            BroadcastHello();
        end
        -- After spell data stabilizes, re-verify local player cooldowns via GetSpellCooldown
        C_Timer.After(5, function()
            isFreshLogin = false;
            if not playerGUID or not IsInGroup() then return; end
            for key, entry in pairs(raidCooldowns) do
                if entry.sourceGUID == playerGUID and not SOULSTONE_BUFF_IDS[entry.spellId] then
                    local start, dur = GetSpellCooldown(entry.spellId);
                    if start and start > 0 and dur and dur > 1.5 then
                        entry.expiryTime = start + dur;
                    else
                        entry.expiryTime = 0;
                    end
                end
            end
        end);

    elseif event == "PLAYER_LEAVING_WORLD" then
        -- Persist cooldown state so /reload doesn't lose timers.
        -- GetTime() is continuous across reloads so expiryTime values stay valid.
        if db and next(raidCooldowns) then
            db.savedCooldowns = {};
            for key, entry in pairs(raidCooldowns) do
                db.savedCooldowns[key] = {
                    sourceGUID = entry.sourceGUID,
                    name = entry.name,
                    classFile = entry.classFile,
                    spellId = entry.spellId,
                    icon = entry.icon,
                    spellName = entry.spellName,
                    expiryTime = entry.expiryTime,
                    lastCastTime = entry.lastCastTime,
                };
            end
        else
            db.savedCooldowns = nil;
        end

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD"
        or event == "PARTY_MEMBER_ENABLE" then
        ScanGroupComposition();
        if IsInGroup() then
            RegisterSelf();
            BroadcastHello();
            -- Delayed rescan to catch late-arriving member data (cross-zone joins)
            if not pendingRescan then
                pendingRescan = true;
                C_Timer.After(2, function()
                    pendingRescan = false;
                    if IsInGroup() then ScanGroupComposition(); end
                end);
            end
        else
            -- Solo: wipe healerWatchUsers, keep only self
            wipe(healerWatchUsers);
            overrideBroadcaster = nil;
            RegisterSelf();
        end

    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
        -- Player switched specs or respecced — re-evaluate self and rescan cooldowns
        local guid = UnitGUID("player");
        if guid and healers[guid] then
            healers[guid].inspectConfirmed = false;
            CheckSelfSpec();
            BroadcastSpec();
        end
        -- Rescan to pick up talent-based cooldowns (e.g., Mana Tide)
        ScanGroupComposition();

    elseif event == "PLAYER_ROLES_ASSIGNED" then
        -- Re-check roles; someone may have been assigned healer
        for guid, data in pairs(healers) do
            if data.unit and UnitExists(data.unit) then
                if UnitGroupRolesAssigned(data.unit) == "HEALER" then
                    data.isHealer = true;
                end
            end
        end

    elseif event == "INSPECT_READY" then
        local inspecteeGUID = ...;
        ProcessInspectResult(inspecteeGUID);

    elseif event == "UNIT_POWER_UPDATE" then
        local unit, powerType = ...;
        if powerType == "MANA" then
            local guid = UnitGUID(unit);
            if guid and healers[guid] and healers[guid].isHealer then
                local manaMax = UnitPowerMax(unit, POWER_TYPE_MANA);
                if manaMax > 0 then
                    healers[guid].manaPercent = floor((UnitPower(unit, POWER_TYPE_MANA) / manaMax) * 100 + 0.5);
                end
            end
        end

    elseif event == "UNIT_AURA" then
        local unit = ...;
        if unit then
            local guid = UnitGUID(unit);
            if guid and healers[guid] and healers[guid].isHealer then
                UpdateUnitBuffs(unit);
            end
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        inspectPaused = true;

    elseif event == "PLAYER_REGEN_ENABLED" then
        inspectPaused = false;

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        ProcessCombatLog();

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, addonMsg, channel, sender = ...;
        if prefix ~= ADDON_MSG_PREFIX then return; end

        local senderName = Ambiguate(sender, "short");
        local isSelf = (senderName == UnitName("player"));

        -- Handle HELLO (from others only — we register ourselves locally)
        local helloVersion = addonMsg:match("^HELLO:(.+)$");
        if helloVersion and not isSelf then
            -- Find sender's rank from group
            local senderRank = 0;
            local senderGUID;
            for _, u in ipairs(IterateGroupMembers()) do
                if UnitName(u) == senderName then
                    senderRank = GetPlayerRank(u);
                    senderGUID = UnitGUID(u);
                    break;
                end
            end
            healerWatchUsers[senderName] = {
                name = senderName,
                version = helloVersion,
                guid = senderGUID,
                lastSeen = GetTime(),
                rank = senderRank,
            };
            -- Reply with our own HELLO + SPEC if we haven't sent one recently
            if GetTime() - lastHelloTime > HELLO_REPLY_COOLDOWN then
                BroadcastHello();
            end
            BroadcastSpec();
            if RefreshSyncFrame then RefreshSyncFrame(); end
            return;
        end

        -- Handle OVERRIDE (from anyone in group)
        local overrideTarget = addonMsg:match("^OVERRIDE:(.+)$");
        if overrideTarget and not isSelf then
            if overrideTarget == "CLEAR" then
                overrideBroadcaster = nil;
            else
                overrideBroadcaster = overrideTarget;
            end
            if RefreshSyncFrame then RefreshSyncFrame(); end
            return;
        end

        -- Ignore other messages from self (we already tracked locally)
        if isSelf then return; end

        -- Find the sender's GUID from group members
        local senderGUID;
        for _, unit in ipairs(IterateGroupMembers()) do
            if UnitName(unit) == senderName then
                senderGUID = UnitGUID(unit);
                break;
            end
        end
        if not senderGUID then return; end

        local _, engClass = GetPlayerInfoByGUID(senderGUID);

        -- "SPEC:<0|1>" — remote HealerWatch user broadcasting their healer status
        local specFlag = addonMsg:match("^SPEC:([01])$");
        if specFlag then
            local data = healers[senderGUID];
            if data and not data.inspectConfirmed then
                data.isHealer = (specFlag == "1");
                data.inspectConfirmed = true;
            end
            return;
        end

        -- "CD:spellId:duration" — single cooldown just cast
        local cdSpellStr, cdDurStr = addonMsg:match("^CD:(%d+):(%d+)$");
        if cdSpellStr then
            local spellId = tonumber(cdSpellStr);
            local duration = tonumber(cdDurStr);
            if spellId and duration then
                local cdInfo = RAID_COOLDOWN_SPELLS[spellId];
                if cdInfo then
                    local canonical = CANONICAL_SPELL_ID[spellId] or spellId;
                    local key = senderGUID .. "-" .. canonical;
                    raidCooldowns[key] = {
                        sourceGUID = senderGUID,
                        name = senderName,
                        classFile = engClass or "UNKNOWN",
                        spellId = canonical,
                        icon = cdInfo.icon,
                        spellName = cdInfo.name,
                        expiryTime = GetTime() + duration,
                        lastCastTime = GetTime(),
                    };
                end
            end
            return;
        end

        -- "SYNC:spellId1:remaining1,spellId2:remaining2,..." — bulk state update
        local syncData = addonMsg:match("^SYNC:(.+)$");
        if syncData then
            local now = GetTime();
            for entry in syncData:gmatch("[^,]+") do
                local spellIdStr, remainStr = entry:match("^(%d+):(%d+)$");
                if spellIdStr then
                    local spellId = tonumber(spellIdStr);
                    local remaining = tonumber(remainStr);
                    if spellId and remaining then
                        local cdInfo = RAID_COOLDOWN_SPELLS[spellId];
                        if cdInfo then
                            local canonical = CANONICAL_SPELL_ID[spellId] or spellId;
                            local key = senderGUID .. "-" .. canonical;
                            local expiryTime = (remaining > 0) and (now + remaining) or 0;
                            raidCooldowns[key] = {
                                sourceGUID = senderGUID,
                                name = senderName,
                                classFile = engClass or "UNKNOWN",
                                spellId = canonical,
                                icon = cdInfo.icon,
                                spellName = cdInfo.name,
                                expiryTime = expiryTime,
                            };
                        end
                    end
                end
            end
            return;
        end
    end
end

EventFrame:SetScript("OnEvent", OnEvent);
EventFrame:RegisterEvent("ADDON_LOADED");
EventFrame:RegisterEvent("PLAYER_LOGIN");
EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE");
EventFrame:RegisterEvent("PARTY_MEMBER_ENABLE");
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
EventFrame:RegisterEvent("PLAYER_LEAVING_WORLD");
EventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED");
EventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
EventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED");
EventFrame:RegisterEvent("INSPECT_READY");
EventFrame:RegisterEvent("UNIT_POWER_UPDATE");
EventFrame:RegisterEvent("UNIT_AURA");
EventFrame:RegisterEvent("PLAYER_REGEN_DISABLED");
EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
EventFrame:RegisterEvent("CHAT_MSG_ADDON");

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

local function OpenOptions()
    if not previewActive then
        StartPreview();
    end
    previewFromSettings = true;
    HealerWatchFrame:SetFrameStrata("TOOLTIP");
    CooldownFrame:SetFrameStrata("TOOLTIP");
    Settings.OpenToCategory(healerWatchCategoryID);
end

local function SlashCommandHandler(msg)
    msg = msg and msg:lower():trim() or "";

    if msg == "" or msg == "options" or msg == "config" then
        OpenOptions();

    elseif msg == "lock" then
        db.locked = not db.locked;
        HealerWatchFrame:EnableMouse(not db.locked);
        CooldownFrame:EnableMouse(not db.locked);
    
        UpdateResizeHandleVisibility();
        UpdateCdResizeHandleVisibility();
        if db.locked then
            print("|cff00ff00HealerWatch|r frames locked.");
        else
            print("|cff00ff00HealerWatch|r frames unlocked. Drag to reposition.");
        end

    elseif msg == "test" then
        if previewActive then
            StopPreview();
            print("|cff00ff00HealerWatch|r preview stopped.");
        else
            StartPreview();
            print("|cff00ff00HealerWatch|r showing preview. Use |cff00ffff/healerwatch test|r again to stop.");
        end

    elseif msg == "reset" then
        for key, value in pairs(DEFAULT_SETTINGS) do
            db[key] = value;
        end
        HealerWatchFrame:SetScale(db.scale);
        HealerWatchFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        HealerWatchFrame:EnableMouse(not db.locked);
        CooldownFrame:SetScale(db.scale);
        CooldownFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        CooldownFrame:EnableMouse(not db.locked);
    
        UpdateResizeHandleVisibility();
        UpdateCdResizeHandleVisibility();
        HealerWatchFrame:ClearAllPoints();
        HealerWatchFrame:SetPoint("LEFT", UIParent, "LEFT", 20, 100);
        CooldownFrame:ClearAllPoints();
        CooldownFrame:SetPoint("LEFT", UIParent, "LEFT", 20, -50);
        db.frameX = nil;
        db.frameY = nil;
        db.frameWidth = nil;
        db.frameHeight = nil;
        db.cdFrameX = nil;
        db.cdFrameY = nil;
        db.cdFrameWidth = nil;
        db.cdFrameHeight = nil;
        print("|cff00ff00HealerWatch|r settings reset to defaults.");

    elseif msg == "sync" then
        RegisterSelf();
        if SyncFrame:IsShown() then
            SyncFrame:Hide();
        else
            SyncFrame:Show();
            RefreshSyncFrame();
        end

    elseif msg == "help" then
        print("|cff00ff00HealerWatch|r commands:");
        print("  |cff00ffff/healerwatch|r - Open Options > AddOns > HealerWatch");
        print("  |cff00ffff/healerwatch lock|r - Toggle frame lock");
        print("  |cff00ffff/healerwatch test|r - Show test healer data");
        print("  |cff00ffff/healerwatch sync|r - Show broadcaster sync window");
        print("  |cff00ffff/healerwatch reset|r - Reset to defaults");
        print("  |cff00ffff/healerwatch help|r - Show this help");

    else
        print("|cff00ff00HealerWatch|r: Unknown command. Use |cff00ffff/healerwatch help|r for commands.");
    end
end

SLASH_HEALERWATCH1 = "/healerwatch";
SLASH_HEALERWATCH2 = "/hwatch";
-- Register /hw shorthand only if no other addon has claimed it
local hwTaken = false;
for key, _ in pairs(SlashCmdList) do
    local i = 1;
    while _G["SLASH_" .. key .. i] do
        if _G["SLASH_" .. key .. i] == "/hw" then hwTaken = true; break; end
        i = i + 1;
    end
    if hwTaken then break; end
end
if not hwTaken then
    SLASH_HEALERWATCH3 = "/hw";
end
SlashCmdList["HEALERWATCH"] = SlashCommandHandler;

--------------------------------------------------------------------------------
-- Initialize db reference (will be overwritten on ADDON_LOADED)
--------------------------------------------------------------------------------

db = DEFAULT_SETTINGS;
