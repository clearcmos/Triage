-- HealerMana: Tracks healer mana in group content with smart healer detection
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
    cooldownIcons = true,
    iconSize = 16,
    showRowHighlight = true,
    enableCdRequest = true,
    headerBackground = true,
};

--------------------------------------------------------------------------------
-- Local References for Performance
--------------------------------------------------------------------------------

local CreateFrame = CreateFrame;
local GetTime = GetTime;
local pairs = pairs;
local ipairs = ipairs;
local tinsert = table.insert;
local tremove = table.remove;
local wipe = table.wipe;
local sort = sort;
local format = string.format;
local floor = math.floor;
local sin = sin;
local cos = cos;
local min = math.min;
local max = math.max;
local UnitName = UnitName;
local UnitClass = UnitClass;
local UnitPower = UnitPower;
local UnitPowerMax = UnitPowerMax;
local UnitGUID = UnitGUID;
local UnitExists = UnitExists;
local UnitIsConnected = UnitIsConnected;
local UnitIsDeadOrGhost = UnitIsDeadOrGhost;
local UnitIsVisible = UnitIsVisible;
local UnitGroupRolesAssigned = UnitGroupRolesAssigned;
local UnitBuff = UnitBuff;
local IsInRaid = IsInRaid;
local IsInGroup = IsInGroup;
local GetNumGroupMembers = GetNumGroupMembers;
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo;
local SendChatMessage = SendChatMessage;
local NotifyInspect = NotifyInspect;
local ClearInspectPlayer = ClearInspectPlayer;
local CanInspect = CanInspect;
local GetPlayerInfoByGUID = GetPlayerInfoByGUID;
local band = bit.band;

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
local DIVINE_INTERVENTION_SPELL_ID = 19752;
local SYMBOL_OF_HOPE_SPELL_ID = 32548;
local SYMBOL_OF_HOPE_SPELL_NAME = GetSpellInfo(32548) or "Symbol of Hope";
local SHIELD_WALL_SPELL_ID = 871;

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

-- Status icon textures for icon mode (keyed by status identifier)
local STATUS_ICONS = {
    drinking     = select(3, GetSpellInfo(430)),      -- Drink
    innervate    = select(3, GetSpellInfo(29166)),     -- Innervate
    manaTide     = select(3, GetSpellInfo(16191)),     -- Mana Tide Totem
    soulstone    = select(3, GetSpellInfo(20707)),     -- Soulstone Resurrection
    symbolOfHope = select(3, GetSpellInfo(32548)) or 135982,  -- Symbol of Hope
    potion       = 134762,                              -- Generic potion (inv_potion_137)
};

-- Raid-wide cooldown spells tracked at the bottom of the display
-- Multi-rank spells share a single info table referenced by all rank IDs
local RAID_COOLDOWN_SPELLS = {
    [INNERVATE_SPELL_ID] = {
        name = INNERVATE_SPELL_NAME,
        icon = select(3, GetSpellInfo(INNERVATE_SPELL_ID)),
        duration = 360,
    },
    [MANA_TIDE_CAST_SPELL_ID] = {
        name = MANA_TIDE_BUFF_NAME,
        icon = select(3, GetSpellInfo(MANA_TIDE_CAST_SPELL_ID)),
        duration = 300,
    },
    [BLOODLUST_SPELL_ID] = {
        name = GetSpellInfo(BLOODLUST_SPELL_ID) or "Bloodlust",
        icon = select(3, GetSpellInfo(BLOODLUST_SPELL_ID)),
        duration = 600,
    },
    [HEROISM_SPELL_ID] = {
        name = GetSpellInfo(HEROISM_SPELL_ID) or "Heroism",
        icon = select(3, GetSpellInfo(HEROISM_SPELL_ID)),
        duration = 600,
    },
    [POWER_INFUSION_SPELL_ID] = {
        name = GetSpellInfo(POWER_INFUSION_SPELL_ID) or "Power Infusion",
        icon = select(3, GetSpellInfo(POWER_INFUSION_SPELL_ID)),
        duration = 180,
    },
    [DIVINE_INTERVENTION_SPELL_ID] = {
        name = GetSpellInfo(DIVINE_INTERVENTION_SPELL_ID) or "Divine Intervention",
        icon = select(3, GetSpellInfo(DIVINE_INTERVENTION_SPELL_ID)),
        duration = 3600,
    },
    [SYMBOL_OF_HOPE_SPELL_ID] = {
        name = "Symbol of Hope",
        icon = select(3, GetSpellInfo(SYMBOL_OF_HOPE_SPELL_ID)) or 135982,
        duration = 300,
    },
    [SHIELD_WALL_SPELL_ID] = {
        name = GetSpellInfo(SHIELD_WALL_SPELL_ID) or "Shield Wall",
        icon = select(3, GetSpellInfo(SHIELD_WALL_SPELL_ID)),
        duration = 1800,
    },
};

-- Rebirth (6 ranks, all same CD) — shared info referenced by each rank ID
local rebirthInfo = {
    name = GetSpellInfo(20484) or "Rebirth",
    icon = select(3, GetSpellInfo(20484)),
    duration = 1200,
};
RAID_COOLDOWN_SPELLS[20484] = rebirthInfo;  -- Rank 1
RAID_COOLDOWN_SPELLS[20739] = rebirthInfo;  -- Rank 2
RAID_COOLDOWN_SPELLS[20742] = rebirthInfo;  -- Rank 3
RAID_COOLDOWN_SPELLS[20747] = rebirthInfo;  -- Rank 4
RAID_COOLDOWN_SPELLS[20748] = rebirthInfo;  -- Rank 5
RAID_COOLDOWN_SPELLS[26994] = rebirthInfo;  -- Rank 6

-- Lay on Hands (4 ranks, all same CD) — shared info referenced by each rank ID
local layOnHandsInfo = {
    name = GetSpellInfo(633) or "Lay on Hands",
    icon = select(3, GetSpellInfo(633)),
    duration = 3600,
};
RAID_COOLDOWN_SPELLS[633]   = layOnHandsInfo;  -- Rank 1
RAID_COOLDOWN_SPELLS[2800]  = layOnHandsInfo;  -- Rank 2
RAID_COOLDOWN_SPELLS[10310] = layOnHandsInfo;  -- Rank 3
RAID_COOLDOWN_SPELLS[27154] = layOnHandsInfo;  -- Rank 4

-- Soulstone Resurrection (6 ranks, tracked via SPELL_AURA_APPLIED on target)
-- When the buff is applied, the warlock's Create Soulstone is on CD for 30 min
local soulstoneInfo = {
    name = "Soulstone",
    icon = select(3, GetSpellInfo(20707)),
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
    [633] = 633, [2800] = 633, [10310] = 633, [27154] = 633,  -- Lay on Hands
    [20707] = 20707, [20762] = 20707, [20763] = 20707,
    [20764] = 20707, [20765] = 20707, [27239] = 20707,  -- Soulstone
};

-- Class-baseline raid cooldowns (every member of the class has these)
local CLASS_COOLDOWN_SPELLS = {
    ["DRUID"] = { INNERVATE_SPELL_ID, 20484 },                   -- Innervate, Rebirth
    ["PALADIN"] = { 633, DIVINE_INTERVENTION_SPELL_ID },          -- Lay on Hands, Divine Intervention
    ["WARLOCK"] = { 20707 },                                      -- Soulstone
    -- Shaman BL/Heroism handled separately (faction-dependent)
    -- Warrior Shield Wall handled via tank spec detection (TANK_COOLDOWN_SPELLS)
};

-- Talent-based cooldowns to check for player via IsSpellKnown
local TALENT_COOLDOWN_SPELLS = {
    ["SHAMAN"] = { MANA_TIDE_CAST_SPELL_ID },
    ["PRIEST"] = { POWER_INFUSION_SPELL_ID, SYMBOL_OF_HOPE_SPELL_ID },
};

-- Tank spec detection (Protection warriors) for tank-specific cooldowns
local TANK_TALENT_TABS = {
    ["WARRIOR"] = { [3] = true },  -- Protection
};

-- Cooldowns seeded only after confirming tank spec via inspection
local TANK_COOLDOWN_SPELLS = {
    ["WARRIOR"] = { SHIELD_WALL_SPELL_ID },
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
local sortedCooldownCache = {};
local activeCdRows = {};
local savedRaidCooldowns = nil;

-- Subgroup tracking: guid -> subgroup number (1-8)
local memberSubgroups = {};
local savedMemberSubgroups = nil;

-- Context menu state
local contextMenuFrame;
local contextMenuVisible = false;

-- Cooldown frame state
local cdContentMinWidth = 120;
local cdContentMinHeight = 30;
local cdResizeDragging = false;
local cdResizeStartCursorX, cdResizeStartCursorY, cdResizeStartW, cdResizeStartH;

-- Warning state
local lastWarningTime = 0;
local warningTriggered = false;

-- Update throttling
local updateElapsed = 0;
local UPDATE_INTERVAL = 0.2;
local inspectElapsed = 0;

-- Preview state
local previewActive = false;
local savedHealers = nil;

-- Forward declarations
local RefreshDisplay;
local ScanGroupComposition;
local StartPreview;
local StopPreview;
local UpdateCdResizeHandleVisibility;
local HideContextMenu;
local ShowCooldownRequestMenu;
local ShowCdRowRequestMenu;

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

local function IterateGroupMembers()
    local results = {};
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i;
            if UnitExists(unit) then
                tinsert(results, unit);
            end
        end
    elseif IsInGroup() then
        tinsert(results, "player");
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i;
            if UnitExists(unit) then
                tinsert(results, unit);
            end
        end
    end
    return results;
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

    -- Soulstone shown on dead healers (manaPercent == -2)
    if db.showSoulstone and data.hasSoulstone and data.manaPercent == -2 then
        tinsert(statusLabelParts, format("|cff9482c9%s|r", "Soulstone"));
        tinsert(statusDurParts, "");
        tinsert(statusIconParts, { icon = STATUS_ICONS.soulstone, duration = "" });
    end

    if data.isDrinking and db.showDrinking then
        tinsert(statusLabelParts, format("|cff55ccff%s|r", "Drinking"));
        local dur = FormatDuration(data.drinkExpiry, now);
        tinsert(statusDurParts, dur);
        tinsert(statusIconParts, { icon = STATUS_ICONS.drinking, duration = dur });
    end
    if data.hasInnervate and db.showInnervate then
        tinsert(statusLabelParts, format("|cffba55d3%s|r", "Innervate"));
        local dur = FormatDuration(data.innervateExpiry, now);
        tinsert(statusDurParts, dur);
        tinsert(statusIconParts, { icon = STATUS_ICONS.innervate, duration = dur });
    end
    if data.hasManaTide and db.showManaTide then
        tinsert(statusLabelParts, format("|cff00c8ff%s|r", "Mana Tide"));
        local dur = FormatDuration(data.manaTideExpiry, now);
        tinsert(statusDurParts, dur);
        tinsert(statusIconParts, { icon = STATUS_ICONS.manaTide, duration = dur });
    end
    if data.hasSymbolOfHope and db.showSymbolOfHope then
        tinsert(statusLabelParts, format("|cffffff80%s|r", "Symbol of Hope"));
        local dur = FormatDuration(data.symbolOfHopeExpiry, now);
        tinsert(statusDurParts, dur);
        tinsert(statusIconParts, { icon = STATUS_ICONS.symbolOfHope, duration = dur });
    end
    if db.showPotionCooldown and data.potionExpiry and data.potionExpiry > now
            and not (data.isDrinking and db.showDrinking)
            and not (data.hasInnervate and db.showInnervate)
            and not (data.hasManaTide and db.showManaTide)
            and not (data.hasSymbolOfHope and db.showSymbolOfHope) then
        local remaining = floor(data.potionExpiry - now);
        local minutes = floor(remaining / 60);
        local seconds = remaining % 60;
        tinsert(statusLabelParts, format("|cffffaa00%s|r", "Potion"));
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
-- Healer Detection Engine
--------------------------------------------------------------------------------

local function IsHealerCapableClass(unit)
    local _, classFile = UnitClass(unit);
    return HEALER_CAPABLE_CLASSES[classFile] == true, classFile;
end

-- Seed tank-specific cooldowns for a confirmed tank
local function SeedTankCooldowns(guid, data)
    local tankSpells = TANK_COOLDOWN_SPELLS[data.classFile];
    if not tankSpells then return; end
    for _, spellId in ipairs(tankSpells) do
        local key = guid .. "-" .. spellId;
        if not raidCooldowns[key] then
            local cdInfo = RAID_COOLDOWN_SPELLS[spellId];
            if cdInfo then
                raidCooldowns[key] = {
                    sourceGUID = guid,
                    name = data.name or "Unknown",
                    classFile = data.classFile,
                    spellId = spellId,
                    icon = cdInfo.icon,
                    spellName = cdInfo.name,
                    expiryTime = 0,
                };
            end
        end
    end
end

local function QueueInspect(unit)
    local guid = UnitGUID(unit);
    if not guid then return; end

    -- Don't queue if already queued
    for _, entry in ipairs(inspectQueue) do
        if entry.guid == guid then return; end
    end

    -- Don't re-queue if we already know all their statuses
    local data = healers[guid];
    if data then
        local needsHealerCheck = data.isHealer == nil and HEALER_CAPABLE_CLASSES[data.classFile];
        local needsTankCheck = data.isTank == nil and TANK_TALENT_TABS[data.classFile];
        if not needsHealerCheck and not needsTankCheck then return; end
    end

    tinsert(inspectQueue, { unit = unit, guid = guid });
end

local function CheckSelfSpec()
    local guid = UnitGUID("player");
    if not guid or not healers[guid] then return; end

    local _, classFile = UnitClass("player");
    local isCapable = HEALER_CAPABLE_CLASSES[classFile];
    local isTankClass = TANK_TALENT_TABS[classFile];

    if not isCapable and not isTankClass then
        healers[guid].isHealer = false;
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
        local ok, specId, name, desc, icon, role, stat, pointsSpent =
            pcall(C_SpecializationInfo.GetSpecializationInfo, i, false, false, nil, nil, activeGroup);
        if ok and pointsSpent and pointsSpent > maxPoints then
            maxPoints = pointsSpent;
            primaryTab = i;
            primaryRole = role;
        end
    end

    if maxPoints > 0 and primaryTab then
        -- Healer detection
        if isCapable then
            if primaryRole == "HEALER" then
                healers[guid].isHealer = true;
            elseif primaryRole then
                healers[guid].isHealer = false;
            else
                local healTabs = HEALING_TALENT_TABS[classFile];
                healers[guid].isHealer = (healTabs and healTabs[primaryTab]) or false;
            end
        end
        -- Tank detection (role is nil in Classic; use talent tab mapping)
        if isTankClass then
            local tankTabs = TANK_TALENT_TABS[classFile];
            healers[guid].isTank = (tankTabs and tankTabs[primaryTab]) or false;
            if healers[guid].isTank then
                SeedTankCooldowns(guid, healers[guid]);
            end
        end
    else
        if isCapable then
            healers[guid].isHealer = (GetNumGroupMembers() <= 5);
        end
        if isTankClass then
            healers[guid].isTank = false;
        end
    end
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
        local ok, specId, name, desc, icon, role, stat, pointsSpent =
            pcall(C_SpecializationInfo.GetSpecializationInfo, i, true, false, nil, nil, activeGroup);
        if ok and pointsSpent and pointsSpent > maxPoints then
            maxPoints = pointsSpent;
            primaryTab = i;
            primaryRole = role;
        end
    end

    local isCapable = HEALER_CAPABLE_CLASSES[classFile];
    local isTankClass = TANK_TALENT_TABS[classFile];

    if maxPoints > 0 and primaryTab then
        -- Healer detection
        if isCapable then
            if primaryRole == "HEALER" then
                data.isHealer = true;
            elseif primaryRole then
                data.isHealer = false;
            else
                local healTabs = HEALING_TALENT_TABS[classFile];
                data.isHealer = (healTabs and healTabs[primaryTab]) or false;
            end
        end
        -- Tank detection
        if isTankClass then
            local tankTabs = TANK_TALENT_TABS[classFile];
            data.isTank = (tankTabs and tankTabs[primaryTab]) or false;
            if data.isTank then
                SeedTankCooldowns(inspecteeGUID, data);
            end
        end
    else
        -- API returned no data; assume healer in small groups, retry in raids
        if isCapable then
            if GetNumGroupMembers() <= 5 then
                data.isHealer = true;
            end
        end
        if isTankClass then
            data.isTank = false;
        end
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

        if UnitExists(unit) and UnitGUID(unit) == guid and UnitIsVisible(unit) then
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
            -- Don't assume tank on failed inspect
            if data and data.isTank == nil and TANK_TALENT_TABS[data.classFile] then
                data.isTank = false;
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Group Scanning
--------------------------------------------------------------------------------

ScanGroupComposition = function()
    -- Clear inspect queue (will re-queue unresolved members below)
    wipe(inspectQueue);
    -- Don't wipe inspectRetries — preserve progress across roster updates
    -- Don't clear inspectPending — let in-flight inspect complete

    local seenGUIDs = {};
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
                    manaPercent = 100,
                    isDrinking = false,
                    hasInnervate = false,
                    hasManaTide = false,
                    hasSoulstone = false,
                    hasSymbolOfHope = false,
                    symbolOfHopeExpiry = 0,
                    potionExpiry = 0,
                    isTank = nil,
                };
            end

            -- Always update unit token and name (can change on roster change)
            healers[guid].unit = unit;
            healers[guid].name = name or healers[guid].name;
            if classFile then healers[guid].classFile = classFile; end

            if assignedHealer then
                healers[guid].isHealer = true;
            elseif not isCapable then
                healers[guid].isHealer = false;
            elseif healers[guid].isHealer == nil then
                -- Self: check directly, others: queue inspect
                if UnitIsUnit(unit, "player") then
                    CheckSelfSpec();
                else
                    QueueInspect(unit);
                end
            end

            -- Tank spec detection (warriors need inspection to confirm Protection)
            if TANK_TALENT_TABS[classFile] and healers[guid].isTank == nil then
                if UnitIsUnit(unit, "player") then
                    CheckSelfSpec();
                else
                    QueueInspect(unit);
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
                    local canonical = CANONICAL_SPELL_ID[spellId] or spellId;
                    local key = guid .. "-" .. canonical;
                    if not raidCooldowns[key] then
                        local cdInfo = RAID_COOLDOWN_SPELLS[spellId];
                        if cdInfo then
                            raidCooldowns[key] = {
                                sourceGUID = guid,
                                name = name or "Unknown",
                                classFile = classFile or "UNKNOWN",
                                spellId = canonical,
                                icon = cdInfo.icon,
                                spellName = cdInfo.name,
                                expiryTime = 0,
                            };
                        end
                    end
                end
            end

            -- Shaman: BL/Heroism based on faction
            if classFile == "SHAMAN" then
                local faction = UnitFactionGroup(unit);
                local blSpellId = (faction == "Horde") and BLOODLUST_SPELL_ID or HEROISM_SPELL_ID;
                local key = guid .. "-" .. blSpellId;
                if not raidCooldowns[key] then
                    local cdInfo = RAID_COOLDOWN_SPELLS[blSpellId];
                    if cdInfo then
                        raidCooldowns[key] = {
                            sourceGUID = guid,
                            name = name or "Unknown",
                            classFile = classFile,
                            spellId = blSpellId,
                            icon = cdInfo.icon,
                            spellName = cdInfo.name,
                            expiryTime = 0,
                        };
                    end
                end
            end

            -- Player only: check talent-based cooldowns via IsSpellKnown
            if UnitIsUnit(unit, "player") then
                local talentSpells = TALENT_COOLDOWN_SPELLS[classFile];
                if talentSpells then
                    for _, spellId in ipairs(talentSpells) do
                        if IsSpellKnown(spellId) then
                            local key = guid .. "-" .. spellId;
                            if not raidCooldowns[key] then
                                local cdInfo = RAID_COOLDOWN_SPELLS[spellId];
                                if cdInfo then
                                    raidCooldowns[key] = {
                                        sourceGUID = guid,
                                        name = name or "Unknown",
                                        classFile = classFile or "UNKNOWN",
                                        spellId = spellId,
                                        icon = cdInfo.icon,
                                        spellName = cdInfo.name,
                                        expiryTime = 0,
                                    };
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Seed tank-specific cooldowns for confirmed tanks
    for _, unit in ipairs(units) do
        local guid = UnitGUID(unit);
        if guid then
            local data = healers[guid];
            if data and data.isTank then
                SeedTankCooldowns(guid, data);
            end
        end
    end
end

local function GetSortedHealers()
    wipe(sortedCache);
    for guid, data in pairs(healers) do
        if data.isHealer then
            tinsert(sortedCache, data);
        end
    end

    if db.sortBy == "mana" then
        sort(sortedCache, function(a, b)
            return a.manaPercent < b.manaPercent;
        end);
    else
        sort(sortedCache, function(a, b)
            return a.name < b.name;
        end);
    end

    return sortedCache;
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
    if count == 0 then return 0; end
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

local function UpdateAllHealerBuffs()
    for guid, data in pairs(healers) do
        if data.isHealer and data.unit and UnitExists(data.unit) then
            UpdateUnitBuffs(data.unit);
        end
    end
end

--------------------------------------------------------------------------------
-- Potion Tracking via Combat Log
--------------------------------------------------------------------------------

local function ProcessCombatLog()
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _, spellId, spellName =
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
    if cdInfo and db.showRaidCooldowns then
        if subevent == "SPELL_CAST_SUCCESS" and not SOULSTONE_BUFF_IDS[spellId] then
            if sourceFlags and band(sourceFlags, 0x07) ~= 0 then
                local _, engClass = GetPlayerInfoByGUID(sourceGUID);
                local canonical = CANONICAL_SPELL_ID[spellId] or spellId;
                local key = sourceGUID .. "-" .. canonical;
                raidCooldowns[key] = {
                    sourceGUID = sourceGUID,
                    name = sourceName or "Unknown",
                    classFile = engClass or "UNKNOWN",
                    spellId = canonical,
                    icon = cdInfo.icon,
                    spellName = cdInfo.name,
                    expiryTime = GetTime() + cdInfo.duration,
                };
            end
        elseif subevent == "SPELL_AURA_APPLIED" and SOULSTONE_BUFF_IDS[spellId] then
            -- Soulstone: source is the warlock, dest gets the buff
            if sourceFlags and band(sourceFlags, 0x07) ~= 0 then
                local _, engClass = GetPlayerInfoByGUID(sourceGUID);
                local canonical = CANONICAL_SPELL_ID[spellId] or spellId;
                local key = sourceGUID .. "-" .. canonical;
                raidCooldowns[key] = {
                    sourceGUID = sourceGUID,
                    name = sourceName or "Unknown",
                    classFile = engClass or "UNKNOWN",
                    spellId = canonical,
                    icon = cdInfo.icon,
                    spellName = cdInfo.name,
                    expiryTime = GetTime() + cdInfo.duration,
                };
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
end

--------------------------------------------------------------------------------
-- Warning System
--------------------------------------------------------------------------------

local function CheckManaWarnings()
    if not db.sendWarnings then return; end
    if not IsInGroup() then return; end

    local now = GetTime();
    if now - lastWarningTime < db.warningCooldown then return; end

    local avgMana = GetAverageMana();

    -- Reset warning if mana recovered above threshold
    if avgMana > db.warningThreshold then
        warningTriggered = false;
        return;
    end

    if warningTriggered then return; end

    if avgMana <= db.warningThreshold then
        local chatType = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or "SAY");
        SendChatMessage(format("[HealerMana] Healer mana low! Average: %d%%", avgMana), chatType);
        warningTriggered = true;
        lastWarningTime = now;
    end
end

--------------------------------------------------------------------------------
-- Display Frame
--------------------------------------------------------------------------------

local HealerManaFrame = CreateFrame("Frame", "HealerManaMainFrame", UIParent, "BackdropTemplate");
HealerManaFrame:SetSize(220, 30);
HealerManaFrame:SetFrameStrata("MEDIUM");
HealerManaFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, tileSize = 16,
});
HealerManaFrame:SetBackdropColor(0, 0, 0, 0.7);
HealerManaFrame:SetClampedToScreen(true);
HealerManaFrame:SetMovable(true);
HealerManaFrame:EnableMouse(true);
HealerManaFrame:Hide();

-- Header background highlight
HealerManaFrame.titleBg = HealerManaFrame:CreateTexture(nil, "BORDER");
HealerManaFrame.titleBg:SetColorTexture(0.2, 0.2, 0.2, 0.5);
HealerManaFrame.titleBg:Hide();

-- Title / average mana text
HealerManaFrame.title = HealerManaFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
HealerManaFrame.title:SetPoint("TOPLEFT", 10, -8);
HealerManaFrame.title:SetJustifyH("LEFT");

-- Separator line below header
HealerManaFrame.separator = HealerManaFrame:CreateTexture(nil, "ARTWORK");
HealerManaFrame.separator:SetHeight(1);
HealerManaFrame.separator:SetColorTexture(0.5, 0.5, 0.5, 0.4);
HealerManaFrame.separator:Hide();

-- Cooldown section title (merged mode)
HealerManaFrame.cdTitleBg = HealerManaFrame:CreateTexture(nil, "BORDER");
HealerManaFrame.cdTitleBg:SetColorTexture(0.2, 0.2, 0.2, 0.5);
HealerManaFrame.cdTitleBg:Hide();

HealerManaFrame.cdTitle = HealerManaFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
HealerManaFrame.cdTitle:SetJustifyH("LEFT");
HealerManaFrame.cdTitle:SetText("Cooldowns");
HealerManaFrame.cdTitle:Hide();

-- Separator line above cooldown section
HealerManaFrame.cdSeparator = HealerManaFrame:CreateTexture(nil, "ARTWORK");
HealerManaFrame.cdSeparator:SetHeight(1);
HealerManaFrame.cdSeparator:SetColorTexture(0.5, 0.5, 0.5, 0.4);
HealerManaFrame.cdSeparator:Hide();

-- Drag handlers
HealerManaFrame:RegisterForDrag("LeftButton");
HealerManaFrame:SetScript("OnDragStart", function(self)
    if db and not db.locked then
        self:StartMoving();
    end
end);
HealerManaFrame:SetScript("OnDragStop", function(self)
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
local resizeHandle = CreateFrame("Button", nil, HealerManaFrame);
resizeHandle:SetSize(16, 16);
resizeHandle:SetPoint("BOTTOMRIGHT", 0, 0);
resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up");
resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight");
resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down");
resizeHandle:Hide();
HealerManaFrame.resizeHandle = resizeHandle;

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
    local effectiveScale = HealerManaFrame:GetEffectiveScale();
    resizeStartCursorX, resizeStartCursorY = GetCursorPosition();
    resizeStartW = HealerManaFrame:GetWidth();
    resizeStartH = HealerManaFrame:GetHeight();

    self:SetScript("OnUpdate", function()
        local cursorX, cursorY = GetCursorPosition();
        local dx = (cursorX - resizeStartCursorX) / effectiveScale;
        local dy = (resizeStartCursorY - cursorY) / effectiveScale;
        local newW = max(contentMinWidth, min(WIDTH_MAX, resizeStartW + dx));
        local newH = max(contentMinHeight, min(HEIGHT_MAX, resizeStartH + dy));
        db.frameWidth = floor(newW + 0.5);
        db.frameHeight = floor(newH + 0.5);
        HealerManaFrame:SetWidth(db.frameWidth);
        HealerManaFrame:SetHeight(db.frameHeight);
    end);
end);

resizeHandle:SetScript("OnMouseUp", function(self)
    resizeDragging = false;
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
    if HealerManaFrame:IsMouseOver() or resizeHandle:IsMouseOver() then
        resizeHandle:Show();
    else
        resizeHandle:Hide();
    end
end

HealerManaFrame:HookScript("OnEnter", function() UpdateResizeHandleVisibility(); end);
HealerManaFrame:HookScript("OnLeave", function() UpdateResizeHandleVisibility(); end);
resizeHandle:SetScript("OnEnter", function() UpdateResizeHandleVisibility(); end);
resizeHandle:SetScript("OnLeave", function() UpdateResizeHandleVisibility(); end);

--------------------------------------------------------------------------------
-- Cooldown Display Frame (split mode)
--------------------------------------------------------------------------------

local CooldownFrame = CreateFrame("Frame", "HealerManaCooldownFrame", UIParent, "BackdropTemplate");
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
local cdResizeHandle = CreateFrame("Button", nil, CooldownFrame);
cdResizeHandle:SetSize(16, 16);
cdResizeHandle:SetPoint("BOTTOMRIGHT", 0, 0);
cdResizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up");
cdResizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight");
cdResizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down");
cdResizeHandle:Hide();
CooldownFrame.resizeHandle = cdResizeHandle;

cdResizeHandle:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return; end
    cdResizeDragging = true;
    local effectiveScale = CooldownFrame:GetEffectiveScale();
    cdResizeStartCursorX, cdResizeStartCursorY = GetCursorPosition();
    cdResizeStartW = CooldownFrame:GetWidth();
    cdResizeStartH = CooldownFrame:GetHeight();

    self:SetScript("OnUpdate", function()
        local cursorX, cursorY = GetCursorPosition();
        local dx = (cursorX - cdResizeStartCursorX) / effectiveScale;
        local dy = (cdResizeStartCursorY - cursorY) / effectiveScale;
        local newW = max(cdContentMinWidth, min(WIDTH_MAX, cdResizeStartW + dx));
        local newH = max(cdContentMinHeight, min(HEIGHT_MAX, cdResizeStartH + dy));
        db.cdFrameWidth = floor(newW + 0.5);
        db.cdFrameHeight = floor(newH + 0.5);
        CooldownFrame:SetWidth(db.cdFrameWidth);
        CooldownFrame:SetHeight(db.cdFrameHeight);
    end);
end);

cdResizeHandle:SetScript("OnMouseUp", function(self)
    cdResizeDragging = false;
    self:SetScript("OnUpdate", nil);
end);

UpdateCdResizeHandleVisibility = function()
    if db and db.locked then
        if not cdResizeDragging then
            cdResizeHandle:Hide();
        end
        return;
    end
    if cdResizeDragging then return; end
    if CooldownFrame:IsMouseOver() or cdResizeHandle:IsMouseOver() then
        cdResizeHandle:Show();
    else
        cdResizeHandle:Hide();
    end
end

CooldownFrame:HookScript("OnEnter", function() UpdateCdResizeHandleVisibility(); end);
CooldownFrame:HookScript("OnLeave", function() UpdateCdResizeHandleVisibility(); end);
cdResizeHandle:SetScript("OnEnter", function() UpdateCdResizeHandleVisibility(); end);
cdResizeHandle:SetScript("OnLeave", function() UpdateCdResizeHandleVisibility(); end);

--------------------------------------------------------------------------------
-- Row Frame Pool
--------------------------------------------------------------------------------

local function CreateRowFrame()
    local frame = CreateFrame("Button", nil, HealerManaFrame);
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
    end);
    frame:SetScript("OnLeave", function(self)
        self.highlight:Hide();
    end);

    frame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and db and db.enableCdRequest and self.healerGUID then
            ShowCooldownRequestMenu(self);
        end
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
    end);
    frame:SetScript("OnLeave", function(self)
        self.highlight:Hide();
    end);

    -- Click handler for cooldown requests
    frame:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and db and db.enableCdRequest and self.spellId then
            ShowCdRowRequestMenu(self);
        end
    end);

    -- Caster name (class-colored, left-aligned)
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.nameText:SetPoint("LEFT", 0, 0);
    frame.nameText:SetJustifyH("LEFT");
    frame.nameText:SetWordWrap(false);

    -- Spell name
    frame.spellText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.spellText:SetJustifyH("LEFT");

    -- Timer / Ready status
    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.timerText:SetJustifyH("LEFT");

    -- Icon mode: spell icon texture
    frame.spellIcon = frame:CreateTexture(nil, "OVERLAY");
    frame.spellIcon:SetSize(14, 14);
    frame.spellIcon:Hide();

    return frame;
end

-- Persistent cd row frames (never recycled — reused in place like healer rows)
local MAX_CD_ROWS = 25;
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
        activeCdRows[i].spellIcon:Hide();
    end
end

--------------------------------------------------------------------------------
-- Cooldown Request Menu
--------------------------------------------------------------------------------

-- Which cooldowns can be requested via click-to-whisper
local REQUESTABLE_SPELLS = {
    [INNERVATE_SPELL_ID] = { scope = "raid" },
    [20707] = { scope = "dead" },  -- Soulstone (canonical ID)
    [20484] = { scope = "dead" },  -- Rebirth (canonical ID)
};

-- Per-spell behavior when a cooldown row is clicked
local CD_REQUEST_CONFIG = {
    [BLOODLUST_SPELL_ID]        = { type = "cast" },
    [HEROISM_SPELL_ID]          = { type = "cast" },
    [SHIELD_WALL_SPELL_ID]      = { type = "cast" },
    [INNERVATE_SPELL_ID]        = { type = "target", filter = "low_mana",  threshold = 30 },
    [633]                       = { type = "target", filter = "low_health", threshold = 20 },  -- Lay on Hands
    [POWER_INFUSION_SPELL_ID]   = { type = "target", filter = "dps_mana" },
    [20484]                     = { type = "target", filter = "dead" },                         -- Rebirth
    [20707]                     = { type = "target", filter = "alive_no_soulstone" },             -- Soulstone
    [MANA_TIDE_CAST_SPELL_ID]   = { type = "conditional_cast", condition = "subgroup_low_mana", threshold = 20 },
    [SYMBOL_OF_HOPE_SPELL_ID]   = { type = "conditional_cast", condition = "subgroup_low_mana", threshold = 20 },
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
        for guid, data in pairs(healers) do
            if guid ~= casterGUID then
                if filter == "low_mana" then
                    if data.manaPercent >= 0 then
                        tinsert(results, { name = data.name, guid = guid, classFile = data.classFile,
                            info = format("%d%% mana", data.manaPercent) });
                    end
                elseif filter == "low_health" then
                    if data.manaPercent >= 0 then
                        tinsert(results, { name = data.name, guid = guid, classFile = data.classFile,
                            info = format("%d%% health", data.manaPercent) });
                    end
                elseif filter == "dead" then
                    if data.manaPercent == -2 then
                        tinsert(results, { name = data.name, guid = guid, classFile = data.classFile,
                            info = "Dead" });
                    end
                elseif filter == "alive_no_soulstone" then
                    if data.manaPercent >= 0 then
                        tinsert(results, { name = data.name, guid = guid, classFile = data.classFile,
                            info = format("%d%% mana", data.manaPercent) });
                    end
                elseif filter == "dps_mana" then
                    if data.classFile == "SHAMAN" then
                        tinsert(results, { name = data.name, guid = guid, classFile = data.classFile,
                            info = "DPS" });
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
                        local maxPower = UnitPowerMax(unit);
                        if maxPower > 0 then
                            local pct = floor(UnitPower(unit) / maxPower * 100);
                            if pct <= threshold then
                                tinsert(results, { name = name, guid = guid, classFile = classFile,
                                    info = format("%d%% mana", pct) });
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
                                    info = format("%d%% health", pct) });
                            end
                        end
                    end
                elseif filter == "dead" then
                    if UnitIsDeadOrGhost(unit) then
                        local healerData = healers[guid];
                        if not healerData or not healerData.hasSoulstone then
                            tinsert(results, { name = name, guid = guid, classFile = classFile,
                                info = "Dead" });
                        end
                    end
                elseif filter == "alive_no_soulstone" then
                    if not UnitIsDeadOrGhost(unit) then
                        local healerData = healers[guid];
                        if not healerData or not healerData.hasSoulstone then
                            tinsert(results, { name = name, guid = guid, classFile = classFile,
                                info = format("%s", classFile and classFile or "") });
                        end
                    end
                elseif filter == "dps_mana" then
                    local powerType = UnitPowerType(unit);
                    if powerType == POWER_TYPE_MANA and not healers[guid] then
                        tinsert(results, { name = name, guid = guid, classFile = classFile,
                            info = "DPS" });
                    end
                end
            end
        end
    end

    sort(results, function(a, b) return a.name < b.name; end);
    return results;
end

local MENU_ITEM_HEIGHT = 20;
local MENU_PADDING = 4;
local MENU_ICON_SIZE = 16;

local function GetEligibleCasters(healerGUID)
    local results = {};
    local healerData = healers[healerGUID];
    if not healerData then return results; end

    local healerSubgroup = memberSubgroups[healerGUID];
    local now = GetTime();

    for _, entry in pairs(raidCooldowns) do
        local spellConfig = REQUESTABLE_SPELLS[entry.spellId];
        if spellConfig and entry.expiryTime <= now then
            local eligible = false;
            if previewActive then
                -- Preview mode: show all ready requestable cooldowns for testing
                eligible = true;
            elseif entry.sourceGUID ~= healerGUID then
                if spellConfig.scope == "raid" then
                    eligible = (healerData.manaPercent >= 0);
                elseif spellConfig.scope == "subgroup" then
                    if healerData.manaPercent >= 0 then
                        local casterSubgroup = memberSubgroups[entry.sourceGUID];
                        eligible = (casterSubgroup and healerSubgroup and casterSubgroup == healerSubgroup);
                    end
                elseif spellConfig.scope == "dead" then
                    eligible = (healerData.manaPercent == -2);
                end
            end

            if eligible then
                tinsert(results, {
                    casterName = entry.name,
                    casterGUID = entry.sourceGUID,
                    spellName = entry.spellName,
                    spellId = entry.spellId,
                    icon = entry.icon,
                    classFile = entry.classFile,
                });
            end
        end
    end

    sort(results, function(a, b)
        if a.spellName == b.spellName then return a.casterName < b.casterName; end
        return a.spellName < b.spellName;
    end);

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

        local cr, cg, cb = GetClassColor(entry.classFile);
        local displayText = format("|cff%02x%02x%02x%s|r - %s",
            cr * 255, cg * 255, cb * 255, entry.casterName, entry.spellName);
        item.text:SetText(displayText);
        item.icon:SetTexture(entry.icon);

        item:ClearAllPoints();
        item:SetPoint("TOPLEFT", contextMenuFrame, "TOPLEFT", MENU_PADDING, -(MENU_PADDING + (i - 1) * MENU_ITEM_HEIGHT));
        item:SetPoint("RIGHT", contextMenuFrame, "RIGHT", -MENU_PADDING, 0);

        -- Store data for click handler
        item.casterName = entry.casterName;
        item.spellName = entry.spellName;
        item.healerName = healerName;
        item.manaStr = manaStr;

        item:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return; end
            local msg = format("[HM] %s needs %s (%s)", self.healerName, self.spellName, self.manaStr);
            local recipient = previewActive and UnitName("player") or self.casterName;
            SendChatMessage(msg, "WHISPER", nil, recipient);
            HideContextMenu();
        end);

        item:Show();

        -- Measure width
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
    contextMenuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / menuScale + 4, cursorY / menuScale + 4);
    contextMenuFrame.targetGUID = healerGUID;
    contextMenuFrame.targetSpellId = nil;
    contextMenuFrame:Show();
    contextMenuFrame:RegisterEvent("GLOBAL_MOUSE_DOWN");
    contextMenuVisible = true;
end

ShowCdRowRequestMenu = function(cdRow)
    local spellId = cdRow.spellId;
    local casterName = cdRow.casterName;
    local sourceGUID = cdRow.sourceGUID;
    if not spellId or not casterName then return; end

    -- Toggle off if clicking same row
    if contextMenuVisible and contextMenuFrame and contextMenuFrame.targetGUID == sourceGUID
       and contextMenuFrame.targetSpellId == spellId then
        HideContextMenu();
        return;
    end

    -- Only show menu for ready cooldowns (skip in preview mode)
    local now = GetTime();
    if not previewActive and cdRow.expiryTime and cdRow.expiryTime > now then return; end

    local config = CD_REQUEST_CONFIG[spellId];
    if not config then return; end

    -- Build menu entries (preview mode bypasses all conditions)
    local entries = {};

    if config.type == "cast" or (previewActive and config.type == "conditional_cast") then
        tinsert(entries, {
            icon = cdRow.cdIcon,
            text = cdRow.spellName,
            whisper = format("[HM] Cast %s please", cdRow.spellName),
        });
    elseif config.type == "conditional_cast" then
        if config.condition == "subgroup_low_mana" then
            if not HasLowManaHealerInSubgroup(sourceGUID, config.threshold or 20) then
                HideContextMenu();
                return;
            end
        end
        tinsert(entries, {
            icon = cdRow.cdIcon,
            text = cdRow.spellName,
            whisper = format("[HM] Cast %s please", cdRow.spellName),
        });
    elseif config.type == "target" then
        local targets = ScanGroupTargets(config.filter, config.threshold or 20, sourceGUID);
        if #targets == 0 then
            HideContextMenu();
            return;
        end
        for _, t in ipairs(targets) do
            local cr, cg, cb = GetClassColor(t.classFile);
            local coloredName = format("|cff%02x%02x%02x%s|r", cr * 255, cg * 255, cb * 255, t.name);
            tinsert(entries, {
                icon = cdRow.cdIcon,
                text = format("%s - %s (%s)", cdRow.spellName, coloredName, t.info),
                whisper = format("[HM] Cast %s on %s (%s)", cdRow.spellName, t.name, t.info),
                targetName = t.name,
            });
        end
    end

    if #entries == 0 then
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
    for i, entry in ipairs(entries) do
        local item = contextMenuFrame.items[i];
        if not item then
            item = CreateMenuItem(contextMenuFrame);
            contextMenuFrame.items[i] = item;
        end

        item.text:SetText(entry.text);
        item.icon:SetTexture(entry.icon);

        item:ClearAllPoints();
        item:SetPoint("TOPLEFT", contextMenuFrame, "TOPLEFT", MENU_PADDING, -(MENU_PADDING + (i - 1) * MENU_ITEM_HEIGHT));
        item:SetPoint("RIGHT", contextMenuFrame, "RIGHT", -MENU_PADDING, 0);

        -- Store data for click handler
        item.casterName = casterName;
        item.whisperMsg = entry.whisper;

        item:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" then return; end
            local recipient = previewActive and UnitName("player") or self.casterName;
            SendChatMessage(self.whisperMsg, "WHISPER", nil, recipient);
            HideContextMenu();
        end);

        item:Show();

        -- Measure width
        local textWidth = item.text:GetStringWidth();
        local itemWidth = MENU_PADDING + MENU_ICON_SIZE + 4 + textWidth + MENU_PADDING;
        if itemWidth > maxWidth then maxWidth = itemWidth; end
    end

    local menuWidth = max(maxWidth + MENU_PADDING * 2, 120);
    local menuHeight = MENU_PADDING * 2 + #entries * MENU_ITEM_HEIGHT;
    contextMenuFrame:SetSize(menuWidth, menuHeight);

    -- Anchor near the cursor
    local cursorX, cursorY = GetCursorPosition();
    local menuScale = contextMenuFrame:GetEffectiveScale();
    contextMenuFrame:ClearAllPoints();
    contextMenuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX / menuScale + 4, cursorY / menuScale + 4);
    contextMenuFrame.targetGUID = sourceGUID;
    contextMenuFrame.targetSpellId = spellId;
    contextMenuFrame:Show();
    contextMenuFrame:RegisterEvent("GLOBAL_MOUSE_DOWN");
    contextMenuVisible = true;
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

        local nw = MeasureText(data.name, db.fontSize);
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

-- Render healer rows onto a target frame starting at yOffset; returns updated yOffset and totalWidth
local function RenderHealerRows(targetFrame, yOffset, totalWidth, maxNameWidth, maxManaWidth, maxStatusLabelWidth, maxStatusDurWidth)
    local useIcons = db.statusIcons;
    local rowHeight = max(db.fontSize + 4, useIcons and (db.iconSize + 2) or 0, 16);
    local iconSize = db.iconSize;
    local iconGap = 3;

    for rowIdx, rd in ipairs(rowDataCache) do
        local data = rd.data;
        local row = activeRows[rowIdx];
        if not row then break; end  -- safety: cap at MAX_HEALER_ROWS
        row.healerGUID = data.guid;
        row.healerName = data.name;

        row:SetSize(totalWidth, rowHeight);
        row.nameText:SetFont(FONT_PATH, db.fontSize, "OUTLINE");
        row.manaText:SetFont(FONT_PATH, db.fontSize, "OUTLINE");

        row.nameText:SetWidth(maxNameWidth);
        row.manaText:SetWidth(maxManaWidth);

        row.manaText:ClearAllPoints();
        row.manaText:SetPoint("LEFT", row.nameText, "RIGHT", COL_GAP, 0);

        local cr, cg, cb = GetClassColor(data.classFile);
        row.nameText:SetText(data.name);
        row.nameText:SetTextColor(cr, cg, cb);

        if data.manaPercent == -2 or data.manaPercent == -1 then
            row.manaText:SetText(rd.manaStr);
            row.manaText:SetTextColor(0.5, 0.5, 0.5);
        else
            row.manaText:SetText(rd.manaStr);
            local mr, mg, mb = GetManaColor(data.manaPercent);
            row.manaText:SetTextColor(mr, mg, mb);
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
                    slot.icon:SetPoint("LEFT", prevAnchor, prevPoint, COL_GAP, 0);
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
            row.statusText:SetPoint("LEFT", row.manaText, "RIGHT", COL_GAP, 0);
            row.durationText:ClearAllPoints();
            row.durationText:SetPoint("LEFT", row.statusText, "RIGHT", COL_GAP, 0);
            row.statusText:SetText(rd.statusLabel);
            row.durationText:SetText(rd.statusDur);
            row.statusText:Show();
            row.durationText:Show();
        end

        row:ClearAllPoints();
        row:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
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
    wipe(sortedCooldownCache);
    for _, entry in pairs(raidCooldowns) do
        tinsert(sortedCooldownCache, entry);
    end

    if #sortedCooldownCache == 0 then return yOffset, totalWidth; end

    local now = GetTime();
    local useIcons = db.cooldownIcons;
    local cdIconSize = db.iconSize;
    local rowHeight = max(db.fontSize + 4, useIcons and (cdIconSize + 2) or 0, 16);
    sort(sortedCooldownCache, function(a, b)
        return a.spellName < b.spellName;
    end);

    -- Measure column widths
    local cdNameMax = 0;
    local cdSpellMax = 0;
    local cdFontSize = db.fontSize;
    local cdTimerMax = MeasureText("Ready", cdFontSize);

    for _, entry in ipairs(sortedCooldownCache) do
        local nw = MeasureText(entry.name, cdFontSize);
        if nw > cdNameMax then cdNameMax = nw; end
        if not useIcons then
            local sw = MeasureText(entry.spellName, cdFontSize);
            if sw > cdSpellMax then cdSpellMax = sw; end
        end
    end

    local cdPad = max(4, floor(cdFontSize * 0.35 + 0.5));
    local cdHalfPad = max(2, floor(cdPad * 0.5 + 0.5));
    cdNameMax = cdNameMax + cdHalfPad;
    cdTimerMax = cdTimerMax + cdHalfPad;

    if useIcons then
        cdSpellMax = cdIconSize + cdPad;
    else
        cdSpellMax = cdSpellMax + cdPad;
    end

    local cdContentWidth = cdNameMax + COL_GAP + cdSpellMax + COL_GAP + cdTimerMax;
    local cdTotalWidth = LEFT_MARGIN + cdContentWidth + RIGHT_MARGIN;
    if cdTotalWidth > totalWidth then totalWidth = cdTotalWidth; end

    for rowIdx, entry in ipairs(sortedCooldownCache) do
        local cdRow = activeCdRows[rowIdx];
        if not cdRow then break; end  -- safety: cap at MAX_CD_ROWS

        cdRow:SetParent(targetFrame);

        -- Store cooldown data for click-to-request
        cdRow.sourceGUID = entry.sourceGUID;
        cdRow.spellId = entry.spellId;
        cdRow.casterName = entry.name;
        cdRow.classFile = entry.classFile;
        cdRow.spellName = entry.spellName;
        cdRow.cdIcon = entry.icon;
        cdRow.expiryTime = entry.expiryTime;

        cdRow.nameText:SetFont(FONT_PATH, cdFontSize, "OUTLINE");
        cdRow.nameText:SetWidth(cdNameMax);
        local cr, cg, cb = GetClassColor(entry.classFile);
        cdRow.nameText:SetText(entry.name);
        cdRow.nameText:SetTextColor(cr, cg, cb);

        if useIcons then
            -- Icon mode: show spell icon instead of text
            cdRow.spellText:Hide();
            cdRow.spellIcon:ClearAllPoints();
            cdRow.spellIcon:SetSize(cdIconSize, cdIconSize);
            cdRow.spellIcon:SetTexture(entry.icon);
            cdRow.spellIcon:SetPoint("LEFT", cdRow.nameText, "RIGHT", COL_GAP, 0);
            cdRow.spellIcon:Show();

            cdRow.timerText:ClearAllPoints();
            cdRow.timerText:SetPoint("LEFT", cdRow.spellIcon, "RIGHT", COL_GAP, 0);
        else
            -- Text mode: show spell name text
            cdRow.spellIcon:Hide();
            cdRow.spellText:ClearAllPoints();
            cdRow.spellText:SetPoint("LEFT", cdRow.nameText, "RIGHT", COL_GAP, 0);
            cdRow.spellText:SetFont(FONT_PATH, cdFontSize, "OUTLINE");
            cdRow.spellText:SetWidth(cdSpellMax);
            cdRow.spellText:SetText(entry.spellName);
            cdRow.spellText:SetTextColor(cr, cg, cb);
            cdRow.spellText:Show();

            cdRow.timerText:ClearAllPoints();
            cdRow.timerText:SetPoint("LEFT", cdRow.spellText, "RIGHT", COL_GAP, 0);
        end

        cdRow.timerText:SetFont(FONT_PATH, cdFontSize, "OUTLINE");

        -- Check if caster is dead
        local casterDead = false;
        local hdata = healers[entry.sourceGUID];
        if hdata and hdata.unit and UnitExists(hdata.unit) then
            casterDead = UnitIsDeadOrGhost(hdata.unit);
        else
            -- Non-healer (e.g., tank): scan group for unit
            for _, u in ipairs(IterateGroupMembers()) do
                if UnitGUID(u) == entry.sourceGUID then
                    casterDead = UnitIsDeadOrGhost(u);
                    break;
                end
            end
        end

        if casterDead then
            cdRow.timerText:SetText("DEAD");
            cdRow.timerText:SetTextColor(0.5, 0.5, 0.5);
            cdRow.nameText:SetTextColor(0.5, 0.5, 0.5);
        elseif entry.expiryTime <= now then
            cdRow.timerText:SetText("Ready");
            cdRow.timerText:SetTextColor(0.0, 1.0, 0.0);
        else
            local remaining = entry.expiryTime - now;
            cdRow.timerText:SetText(format("%d:%02d", floor(remaining / 60), floor(remaining) % 60));
            cdRow.timerText:SetTextColor(0.8, 0.8, 0.8);
        end

        cdRow:SetSize(totalWidth, rowHeight);
        cdRow:ClearAllPoints();
        cdRow:SetPoint("TOPLEFT", targetFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
        cdRow:Show();

        yOffset = yOffset - rowHeight;
    end

    -- Hide excess rows
    for i = #sortedCooldownCache + 1, #activeCdRows do
        activeCdRows[i]:Hide();
        activeCdRows[i].sourceGUID = nil;
        activeCdRows[i].spellId = nil;
    end

    return yOffset, totalWidth;
end

-- Healer rows only on HealerManaFrame (split mode)
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
        HealerManaFrame.title:SetFont(FONT_PATH, db.fontSize, "OUTLINE");
        HealerManaFrame.title:SetFormattedText("Mana: |cff%02x%02x%02x%d%%|r",
            ar * 255, ag * 255, ab * 255, avgMana);
        HealerManaFrame.title:Show();

        local titleWidth = MeasureText("Mana: " .. avgMana .. "%", db.fontSize) + LEFT_MARGIN + RIGHT_MARGIN;
        if titleWidth > totalWidth then totalWidth = titleWidth; end

        yOffset = yOffset - rowHeight;
        if db.headerBackground then
            HealerManaFrame.separator:Hide();
            HealerManaFrame.titleBg:ClearAllPoints();
            HealerManaFrame.titleBg:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", 0, 0);
            HealerManaFrame.titleBg:SetPoint("TOPRIGHT", HealerManaFrame, "TOPRIGHT", 0, 0);
            HealerManaFrame.titleBg:SetHeight(TOP_PADDING + rowHeight);
            HealerManaFrame.titleBg:Show();
        else
            HealerManaFrame.titleBg:Hide();
            HealerManaFrame.separator:ClearAllPoints();
            HealerManaFrame.separator:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
            HealerManaFrame.separator:SetPoint("TOPRIGHT", HealerManaFrame, "TOPRIGHT", -RIGHT_MARGIN, yOffset);
            HealerManaFrame.separator:Show();
        end
        yOffset = yOffset - 4;
    else
        HealerManaFrame.title:Hide();
        HealerManaFrame.separator:Hide();
        HealerManaFrame.titleBg:Hide();
    end

    -- Track content-driven minimums (used by resize handle to prevent clipping)
    contentMinWidth = totalWidth;

    -- Respect user-set width as minimum
    totalWidth = max(totalWidth, db.frameWidth or 120);

    yOffset = RenderHealerRows(HealerManaFrame, yOffset, totalWidth, maxNameWidth, maxManaWidth, maxStatusLabelWidth, maxStatusDurWidth);

    -- Hide merged-mode cd elements
    HealerManaFrame.cdTitle:Hide();
    HealerManaFrame.cdSeparator:Hide();
    HealerManaFrame.cdTitleBg:Hide();

    local totalHeight = -yOffset + BOTTOM_PADDING;
    contentMinHeight = totalHeight;

    -- Respect user-set height as minimum
    totalHeight = max(totalHeight, db.frameHeight or HEIGHT_MIN);

    HealerManaFrame:SetHeight(totalHeight);
    HealerManaFrame:SetWidth(totalWidth);
    HealerManaFrame:Show();
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

    local rowHeight = max(db.fontSize + 4, db.cooldownIcons and (db.iconSize + 2) or 0, 16);
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

-- Merged display: healer rows + cooldown rows on HealerManaFrame (original behavior)
local function RefreshMergedDisplay(sortedHealers)
    HideAllRows();

    local iconH = 0;
    if db.statusIcons or db.cooldownIcons then iconH = db.iconSize + 2; end
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
        HealerManaFrame.title:SetFont(FONT_PATH, db.fontSize, "OUTLINE");
        HealerManaFrame.title:SetFormattedText("Mana: |cff%02x%02x%02x%d%%|r",
            ar * 255, ag * 255, ab * 255, avgMana);
        HealerManaFrame.title:Show();

        local titleWidth = MeasureText("Mana: " .. avgMana .. "%", db.fontSize) + LEFT_MARGIN + RIGHT_MARGIN;
        if titleWidth > totalWidth then totalWidth = titleWidth; end

        yOffset = yOffset - rowHeight;
        if db.headerBackground then
            HealerManaFrame.separator:Hide();
            HealerManaFrame.titleBg:ClearAllPoints();
            HealerManaFrame.titleBg:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", 0, 0);
            HealerManaFrame.titleBg:SetPoint("TOPRIGHT", HealerManaFrame, "TOPRIGHT", 0, 0);
            HealerManaFrame.titleBg:SetHeight(TOP_PADDING + rowHeight);
            HealerManaFrame.titleBg:Show();
        else
            HealerManaFrame.titleBg:Hide();
            HealerManaFrame.separator:ClearAllPoints();
            HealerManaFrame.separator:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
            HealerManaFrame.separator:SetPoint("TOPRIGHT", HealerManaFrame, "TOPRIGHT", -RIGHT_MARGIN, yOffset);
            HealerManaFrame.separator:Show();
        end
        yOffset = yOffset - 4;
    else
        HealerManaFrame.title:Hide();
        HealerManaFrame.separator:Hide();
        HealerManaFrame.titleBg:Hide();
    end

    yOffset = RenderHealerRows(HealerManaFrame, yOffset, totalWidth, maxNameWidth, maxManaWidth, maxStatusLabelWidth, maxStatusDurWidth);

    -- Raid cooldown section (merged)
    HideAllCdRows();
    HealerManaFrame.cdTitle:Hide();
    HealerManaFrame.cdSeparator:Hide();
    HealerManaFrame.cdTitleBg:Hide();

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
            HealerManaFrame.cdTitle:SetFont(FONT_PATH, db.fontSize, "OUTLINE");
            HealerManaFrame.cdTitle:SetTextColor(1, 0.82, 0);
            HealerManaFrame.cdTitle:ClearAllPoints();
            HealerManaFrame.cdTitle:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
            HealerManaFrame.cdTitle:Show();

            local cdTitleWidth = MeasureText("Cooldowns", db.fontSize) + LEFT_MARGIN + RIGHT_MARGIN;
            if cdTitleWidth > totalWidth then totalWidth = cdTitleWidth; end

            yOffset = yOffset - rowHeight;

            if db.headerBackground then
                HealerManaFrame.cdSeparator:Hide();
                HealerManaFrame.cdTitleBg:ClearAllPoints();
                HealerManaFrame.cdTitleBg:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", 0, cdSectionTop);
                HealerManaFrame.cdTitleBg:SetPoint("TOPRIGHT", HealerManaFrame, "TOPRIGHT", 0, cdSectionTop);
                HealerManaFrame.cdTitleBg:SetHeight(TOP_PADDING + rowHeight);
                HealerManaFrame.cdTitleBg:Show();
            else
                HealerManaFrame.cdTitleBg:Hide();
                HealerManaFrame.cdSeparator:ClearAllPoints();
                HealerManaFrame.cdSeparator:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", LEFT_MARGIN, yOffset);
                HealerManaFrame.cdSeparator:SetPoint("TOPRIGHT", HealerManaFrame, "TOPRIGHT", -RIGHT_MARGIN, yOffset);
                HealerManaFrame.cdSeparator:Show();
            end
            yOffset = yOffset - 4;

            yOffset, totalWidth = RenderCooldownRows(HealerManaFrame, yOffset, totalWidth);
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

    HealerManaFrame:SetHeight(totalHeight);
    HealerManaFrame:SetWidth(totalWidth);
    HealerManaFrame:Show();
end

-- Dispatcher
RefreshDisplay = function()
    if not db or not db.enabled then
        HealerManaFrame:Hide();
        CooldownFrame:Hide();
        return;
    end

    if not previewActive and not IsInGroup() then
        HealerManaFrame:Hide();
        CooldownFrame:Hide();
        return;
    end

    local sortedHealers = GetSortedHealers();
    if #sortedHealers == 0 then
        HealerManaFrame:Hide();
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
                    if data.unit and UnitExists(data.unit) then
                        local needsHealerCheck = data.isHealer == nil and HEALER_CAPABLE_CLASSES[data.classFile];
                        local needsTankCheck = data.isTank == nil and TANK_TALENT_TABS[data.classFile];
                        if needsHealerCheck or needsTankCheck then
                            QueueInspect(data.unit);
                        end
                    end
                end
            end
            ProcessInspectQueue();
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
                    if key == "preview-inn" or key == "preview-rebirth" or key == "preview-ss" or key == "preview-pi" or key == "preview-loh" then
                        -- Leave expired so they show "Ready"
                    else
                        entry.expiryTime = now + RAID_COOLDOWN_SPELLS[entry.spellId].duration;
                    end
                end
            end
        else
            UpdateManaValues();
            UpdateAllHealerBuffs();
            CheckManaWarnings();
        end

        RefreshDisplay();
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
    { name = "Soulstoned", classFile = "PALADIN", hasSoulstone = true, driftSeed = 0 },
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
            manaPercent = td.baseMana or -2,
            baseMana = td.baseMana,
            driftSeed = td.driftSeed,
            isDrinking = td.isDrinking or false,
            hasInnervate = td.hasInnervate or false,
            hasManaTide = td.hasManaTide or false,
            hasSoulstone = td.hasSoulstone or false,
            hasSymbolOfHope = td.hasSymbolOfHope or false,
            drinkExpiry = td.isDrinking and (GetTime() + 18) or 0,
            innervateExpiry = td.hasInnervate and (GetTime() + 12) or 0,
            manaTideExpiry = td.hasManaTide and (GetTime() + 8) or 0,
            symbolOfHopeExpiry = td.hasSymbolOfHope and (GetTime() + 15) or 0,
            potionExpiry = td.hasPotion and (GetTime() + 90) or 0,
        };
    end

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
    memberSubgroups["preview-guid-5"] = 2;  -- Soulstoned
    memberSubgroups["preview-guid-ss"] = 1; -- Shadowlock (warlock)
    memberSubgroups["preview-guid-sw"] = 2; -- Tankyboy (warrior)

    -- Save and inject mock raid cooldowns
    savedRaidCooldowns = {};
    for key, entry in pairs(raidCooldowns) do
        savedRaidCooldowns[key] = entry;
    end
    wipe(raidCooldowns);
    local now = GetTime();
    local innervateInfo = RAID_COOLDOWN_SPELLS[INNERVATE_SPELL_ID];
    local manaTideInfo = RAID_COOLDOWN_SPELLS[MANA_TIDE_CAST_SPELL_ID];
    local bloodlustInfo = RAID_COOLDOWN_SPELLS[BLOODLUST_SPELL_ID];
    local heroismInfo = RAID_COOLDOWN_SPELLS[HEROISM_SPELL_ID];
    -- Show Bloodlust or Heroism based on player faction
    local blInfo = (UnitFactionGroup("player") == "Horde") and bloodlustInfo or heroismInfo;
    local blSpellId = (UnitFactionGroup("player") == "Horde") and BLOODLUST_SPELL_ID or HEROISM_SPELL_ID;
    raidCooldowns["preview-inn"] = {
        sourceGUID = "preview-guid-2",
        name = "Treehugger",
        classFile = "DRUID",
        spellId = INNERVATE_SPELL_ID,
        icon = innervateInfo.icon,
        spellName = innervateInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    raidCooldowns["preview-tide"] = {
        sourceGUID = "preview-guid-4",
        name = "Tidecaller",
        classFile = "SHAMAN",
        spellId = MANA_TIDE_CAST_SPELL_ID,
        icon = manaTideInfo.icon,
        spellName = manaTideInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    raidCooldowns["preview-bl"] = {
        sourceGUID = "preview-guid-4",
        name = "Tidecaller",
        classFile = "SHAMAN",
        spellId = blSpellId,
        icon = blInfo.icon,
        spellName = blInfo.name,
        expiryTime = now + 420,
    };
    raidCooldowns["preview-rebirth"] = {
        sourceGUID = "preview-guid-2",
        name = "Treehugger",
        classFile = "DRUID",
        spellId = 20484,
        icon = rebirthInfo.icon,
        spellName = rebirthInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    raidCooldowns["preview-ss"] = {
        sourceGUID = "preview-guid-ss",
        name = "Shadowlock",
        classFile = "WARLOCK",
        spellId = 20707,
        icon = soulstoneInfo.icon,
        spellName = soulstoneInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    raidCooldowns["preview-loh"] = {
        sourceGUID = "preview-guid-3",
        name = "Palaheals",
        classFile = "PALADIN",
        spellId = 633,
        icon = layOnHandsInfo.icon,
        spellName = layOnHandsInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    local piInfo = RAID_COOLDOWN_SPELLS[POWER_INFUSION_SPELL_ID];
    raidCooldowns["preview-pi"] = {
        sourceGUID = "preview-guid-1",
        name = "Holypriest",
        classFile = "PRIEST",
        spellId = POWER_INFUSION_SPELL_ID,
        icon = piInfo.icon,
        spellName = piInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    local sohInfo = RAID_COOLDOWN_SPELLS[SYMBOL_OF_HOPE_SPELL_ID];
    raidCooldowns["preview-soh"] = {
        sourceGUID = "preview-guid-1",
        name = "Holypriest",
        classFile = "PRIEST",
        spellId = SYMBOL_OF_HOPE_SPELL_ID,
        icon = sohInfo.icon,
        spellName = sohInfo.name,
        expiryTime = now - 1,  -- starts as "Ready"
    };
    local swInfo = RAID_COOLDOWN_SPELLS[SHIELD_WALL_SPELL_ID];
    raidCooldowns["preview-sw"] = {
        sourceGUID = "preview-guid-sw",
        name = "Tankyboy",
        classFile = "WARRIOR",
        spellId = SHIELD_WALL_SPELL_ID,
        icon = swInfo.icon,
        spellName = swInfo.name,
        expiryTime = now + 1500,
    };

    -- Unlock frames for dragging while options are open
    HealerManaFrame:EnableMouse(true);
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
    HealerManaFrame:EnableMouse(not db.locked);
    HealerManaFrame:SetFrameStrata("MEDIUM");
    CooldownFrame:EnableMouse(not db.locked);
    CooldownFrame:SetFrameStrata("MEDIUM");

    RefreshDisplay();
end

--------------------------------------------------------------------------------
-- Options GUI (native Settings API)
--------------------------------------------------------------------------------

local healerManaCategoryID;

-- Sort value mapping (Settings dropdown uses numeric keys)
local SORT_MAP = { [1] = "mana", [2] = "name" };
local SORT_REVERSE = { mana = 1, name = 2 };

local function RegisterSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("HealerMana");

    -- Helper: register a boolean proxy setting + checkbox
    local function AddCheckbox(key, name, tooltip, onChange)
        local setting = Settings.RegisterProxySetting(category,
            "HEALERMANA_" .. key:upper(), Settings.VarType.Boolean, name,
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
            "HEALERMANA_" .. key:upper(), Settings.VarType.Number, name,
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

    AddCheckbox("enabled", "Enable HealerMana",
        "Toggle the HealerMana display on or off.",
        function() RefreshDisplay(); end);

    AddCheckbox("showAverageMana", "Show Average Mana",
        "Display the average mana percentage across all healers in the header row.");

    AddCheckbox("locked", "Lock Frame Position",
        "Prevent the frames from being dragged.",
        function(value)
            HealerManaFrame:EnableMouse(not value);
            CooldownFrame:EnableMouse(not value);
            UpdateResizeHandleVisibility();
            UpdateCdResizeHandleVisibility();
        end);

    AddCheckbox("splitFrames", "Separate Cooldown Frame",
        "Show cooldowns in a separate, independently movable frame.",
        function() RefreshDisplay(); end);

    -- Sort dropdown
    local sortSetting = Settings.RegisterProxySetting(category,
        "HEALERMANA_SORT_BY", Settings.VarType.Number, "Sort Healers By",
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

    -------------------------
    -- Section: Status Indicators
    -------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Status Indicators"));

    AddCheckbox("showDrinking", "Drinking",
        "Indicate when a healer is drinking to restore mana.");

    AddCheckbox("showInnervate", "Innervate",
        "Indicate when a healer has Innervate active.");

    AddCheckbox("showManaTide", "Mana Tide",
        "Indicate when a healer is affected by Mana Tide Totem.");

    AddCheckbox("showSoulstone", "Soulstone",
        "Indicate Soulstone on dead healers who have the buff.");

    AddCheckbox("showSymbolOfHope", "Symbol of Hope",
        "Indicate when a healer is receiving mana from Symbol of Hope.");

    AddCheckbox("showPotionCooldown", "Potion Cooldowns",
        "Display mana potion cooldown timers.");

    AddCheckbox("showRaidCooldowns", "Cooldowns",
        "Track group cooldowns (Innervate, Mana Tide, Bloodlust, etc.) with Ready/on-cooldown timers.");

    AddCheckbox("showStatusDuration", "Buff Durations",
        "Show remaining seconds on active buffs like Innervate, Mana Tide, and Drinking.");

    AddCheckbox("statusIcons", "Status Icons",
        "Show spell icons instead of text labels for healer status indicators (Drinking, Innervate, etc.).");

    AddCheckbox("cooldownIcons", "Cooldown Icons",
        "Display spell icons instead of spell names in the cooldowns section.");

    AddCheckbox("showRowHighlight", "Row Hover Highlight",
        "Highlight rows on mouse hover for visual feedback.");

    AddCheckbox("enableCdRequest", "Click-to-Request Cooldowns",
        "Click a healer or cooldown row to whisper a caster requesting a cooldown.");

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
            HealerManaFrame:SetScale(value / 100);
            CooldownFrame:SetScale(value / 100);
        end,
        function(raw) return floor(raw * 100 + 0.5); end,
        function(value) return value / 100; end);

    AddSlider("bgOpacity", "Display Opacity (%)",
        "Background opacity of both frames.",
        0, 100, 5,
        function(value)
            HealerManaFrame:SetBackdropColor(0, 0, 0, value / 100);
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
        "Send a chat warning to party/raid when average healer mana drops below the warning threshold.");

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
    healerManaCategoryID = category:GetID();
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
        if not HealerManaDB then
            HealerManaDB = {};
        end

        -- Copy defaults for missing keys
        for key, value in pairs(DEFAULT_SETTINGS) do
            if HealerManaDB[key] == nil then
                HealerManaDB[key] = value;
            end
        end

        db = HealerManaDB;

        -- Clean up removed settings
        db.optionsBgOpacity = nil;
        db.warningThresholdHigh = nil;
        db.warningThresholdMed = nil;
        db.warningThresholdLow = nil;
        db.shortenedStatus = nil;
        db.showSolo = nil;
        db.sendWarningsSolo = nil;

        -- Register native settings panel
        RegisterSettings();

        -- Apply saved position (healer frame)
        if db.frameX and db.frameY then
            HealerManaFrame:ClearAllPoints();
            HealerManaFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.frameX, db.frameY);
        else
            HealerManaFrame:SetPoint("LEFT", UIParent, "LEFT", 20, 100);
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
        HealerManaFrame:SetScale(db.scale);
        HealerManaFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        HealerManaFrame:EnableMouse(not db.locked);
        CooldownFrame:SetScale(db.scale);
        CooldownFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        CooldownFrame:EnableMouse(not db.locked);
    
        UpdateResizeHandleVisibility();

        self:UnregisterEvent("ADDON_LOADED");
        print("|cff00ff00HealerMana|r loaded. Type |cff00ffff/hm|r or visit Options > AddOns.");

    elseif event == "PLAYER_LOGIN" then
        if IsInGroup() then
            ScanGroupComposition();
        end

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
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
    end
end

EventFrame:SetScript("OnEvent", OnEvent);
EventFrame:RegisterEvent("ADDON_LOADED");
EventFrame:RegisterEvent("PLAYER_LOGIN");
EventFrame:RegisterEvent("GROUP_ROSTER_UPDATE");
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
EventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED");
EventFrame:RegisterEvent("INSPECT_READY");
EventFrame:RegisterEvent("UNIT_POWER_UPDATE");
EventFrame:RegisterEvent("UNIT_AURA");
EventFrame:RegisterEvent("PLAYER_REGEN_DISABLED");
EventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

local function OpenOptions()
    if not previewActive then
        StartPreview();
    end
    previewFromSettings = true;
    HealerManaFrame:SetFrameStrata("TOOLTIP");
    CooldownFrame:SetFrameStrata("TOOLTIP");
    Settings.OpenToCategory(healerManaCategoryID);
end

local function SlashCommandHandler(msg)
    msg = msg and msg:lower():trim() or "";

    if msg == "" or msg == "options" or msg == "config" then
        OpenOptions();

    elseif msg == "lock" then
        db.locked = not db.locked;
        HealerManaFrame:EnableMouse(not db.locked);
        CooldownFrame:EnableMouse(not db.locked);
    
        UpdateResizeHandleVisibility();
        UpdateCdResizeHandleVisibility();
        if db.locked then
            print("|cff00ff00HealerMana|r frames locked.");
        else
            print("|cff00ff00HealerMana|r frames unlocked. Drag to reposition.");
        end

    elseif msg == "test" then
        if previewActive then
            StopPreview();
            print("|cff00ff00HealerMana|r preview stopped.");
        else
            StartPreview();
            print("|cff00ff00HealerMana|r showing preview. Use |cff00ffff/hm test|r again to stop.");
        end

    elseif msg == "reset" then
        for key, value in pairs(DEFAULT_SETTINGS) do
            db[key] = value;
        end
        HealerManaFrame:SetScale(db.scale);
        HealerManaFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        HealerManaFrame:EnableMouse(not db.locked);
        CooldownFrame:SetScale(db.scale);
        CooldownFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        CooldownFrame:EnableMouse(not db.locked);
    
        UpdateResizeHandleVisibility();
        UpdateCdResizeHandleVisibility();
        HealerManaFrame:ClearAllPoints();
        HealerManaFrame:SetPoint("LEFT", UIParent, "LEFT", 20, 100);
        CooldownFrame:ClearAllPoints();
        CooldownFrame:SetPoint("LEFT", UIParent, "LEFT", 20, -50);
        db.frameX = nil;
        db.frameY = nil;
        db.cdFrameX = nil;
        db.cdFrameY = nil;
        db.cdFrameWidth = nil;
        db.cdFrameHeight = nil;
        print("|cff00ff00HealerMana|r settings reset to defaults.");

    elseif msg == "help" then
        print("|cff00ff00HealerMana|r commands:");
        print("  |cff00ffff/hm|r - Open Options > AddOns > HealerMana");
        print("  |cff00ffff/hm lock|r - Toggle frame lock");
        print("  |cff00ffff/hm test|r - Show test healer data");
        print("  |cff00ffff/hm reset|r - Reset to defaults");
        print("  |cff00ffff/hm help|r - Show this help");

    else
        print("|cff00ff00HealerMana|r: Unknown command. Use |cff00ffff/hm help|r for commands.");
    end
end

SLASH_HEALERMANA1 = "/healermana";
SLASH_HEALERMANA2 = "/hm";
SlashCmdList["HEALERMANA"] = SlashCommandHandler;

--------------------------------------------------------------------------------
-- Initialize db reference (will be overwritten on ADDON_LOADED)
--------------------------------------------------------------------------------

db = DEFAULT_SETTINGS;
