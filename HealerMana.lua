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
    showPotionCooldown = true,
    showAverageMana = true,
    shortenedStatus = true,
    showStatusDuration = false,
    showSolo = false,
    optionsBgOpacity = 0.9,
    sendWarnings = false,
    warningThresholdHigh = 30,
    warningThresholdMed = 20,
    warningThresholdLow = 10,
    warningCooldown = 30,
    colorThresholdGreen = 75,
    colorThresholdYellow = 50,
    colorThresholdOrange = 25,
    sortBy = "mana",
    showRaidCooldowns = true,
    frameWidth = nil,
    frameHeight = nil,
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
local concat = table.concat;
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
local InCombatLockdown = InCombatLockdown;
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

-- Canonical spell ID for multi-rank spells (any rank → rank 1 for consistent keys)
local CANONICAL_SPELL_ID = {
    [20484] = 20484, [20739] = 20484, [20742] = 20484,
    [20747] = 20484, [20748] = 20484, [26994] = 20484,  -- Rebirth
    [633] = 633, [2800] = 633, [10310] = 633, [27154] = 633,  -- Lay on Hands
};

-- Class-baseline raid cooldowns (every member of the class has these)
local CLASS_COOLDOWN_SPELLS = {
    ["DRUID"] = { INNERVATE_SPELL_ID, 20484 },                   -- Innervate, Rebirth
    ["PALADIN"] = { 633, DIVINE_INTERVENTION_SPELL_ID },          -- Lay on Hands, Divine Intervention
    -- Shaman BL/Heroism handled separately (faction-dependent)
};

-- Talent-based cooldowns to check for player via IsSpellKnown
local TALENT_COOLDOWN_SPELLS = {
    ["SHAMAN"] = { MANA_TIDE_CAST_SPELL_ID },
    ["PRIEST"] = { POWER_INFUSION_SPELL_ID },
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

-- Row frame pool
local rowPool = {};
local activeRows = {};

-- Reusable table caches (avoid per-frame allocations)
local sortedCache = {};
local rowDataCache = {};
local statusLabelParts = {};
local statusDurParts = {};

-- Raid cooldown tracking
local raidCooldowns = {};
local sortedCooldownCache = {};
local cdRowPool = {};
local activeCdRows = {};
local savedRaidCooldowns = nil;

-- Warning state
local lastWarningTime = 0;
local warningTriggered = { high = false, med = false, low = false };

-- Update throttling
local updateElapsed = 0;
local UPDATE_INTERVAL = 0.2;
local inspectElapsed = 0;

-- Preview state
local previewActive = false;
local previewHealers = {};
local savedHealers = nil;

-- Forward declarations
local RefreshDisplay;
local ScanGroupComposition;

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
    elseif db and db.showSolo then
        tinsert(results, "player");
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

-- Returns two strings: statusLabel (colored label), statusDuration (duration + overflow)
-- The label and duration are rendered in separate FontStrings for pixel-perfect alignment.
local function FormatStatusText(data)
    wipe(statusLabelParts);
    wipe(statusDurParts);
    local short = db.shortenedStatus;
    local now = GetTime();

    if data.isDrinking and db.showDrinking then
        local label = short and "Drink" or "Drinking";
        tinsert(statusLabelParts, format("|cff55ccff%s|r", label));
        tinsert(statusDurParts, FormatDuration(data.drinkExpiry, now));
    end
    if data.hasInnervate and db.showInnervate then
        local label = short and "Inn" or "Innervate";
        tinsert(statusLabelParts, format("|cffba55d3%s|r", label));
        tinsert(statusDurParts, FormatDuration(data.innervateExpiry, now));
    end
    if data.hasManaTide and db.showManaTide then
        local label = short and "Tide" or "Mana Tide";
        tinsert(statusLabelParts, format("|cff00c8ff%s|r", label));
        tinsert(statusDurParts, FormatDuration(data.manaTideExpiry, now));
    end
    if db.showPotionCooldown and data.potionExpiry and data.potionExpiry > now then
        local remaining = floor(data.potionExpiry - now);
        local minutes = floor(remaining / 60);
        local seconds = remaining % 60;
        local label = short and "Pot" or "Potion";
        tinsert(statusLabelParts, format("|cffffaa00%s|r", label));
        tinsert(statusDurParts, format("%d:%02d", minutes, seconds));
    end

    if #statusLabelParts == 0 then return "", ""; end

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

    return labelStr, durStr;
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

    -- Don't re-queue if we already know their status
    if healers[guid] and healers[guid].isHealer ~= nil then return; end

    tinsert(inspectQueue, { unit = unit, guid = guid });
end

local function CheckSelfSpec()
    local guid = UnitGUID("player");
    if not guid or not healers[guid] then return; end

    local isCapable, classFile = IsHealerCapableClass("player");
    if not isCapable then
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
        if primaryRole == "HEALER" then
            healers[guid].isHealer = true;
        elseif primaryRole then
            healers[guid].isHealer = false;
        else
            -- role is nil in Classic; use talent tab mapping
            local healTabs = HEALING_TALENT_TABS[classFile];
            healers[guid].isHealer = (healTabs and healTabs[primaryTab]) or false;
        end
    else
        -- API returned no data; assume healer in small groups
        healers[guid].isHealer = (GetNumGroupMembers() <= 5);
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

    if maxPoints > 0 and primaryTab then
        if primaryRole == "HEALER" then
            data.isHealer = true;
        elseif primaryRole then
            data.isHealer = false;
        else
            -- role is nil in Classic; use talent tab mapping
            local healTabs = HEALING_TALENT_TABS[classFile];
            data.isHealer = (healTabs and healTabs[primaryTab]) or false;
        end
    else
        -- API returned no data; assume healer in small groups, retry in raids
        if GetNumGroupMembers() <= 5 then
            data.isHealer = true;
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

            local isCapable, classFile = IsHealerCapableClass(unit);
            local name = UnitName(unit);
            local assignedHealer = (UnitGroupRolesAssigned(unit) == "HEALER");

            if not healers[guid] then
                healers[guid] = {
                    unit = unit,
                    name = name or "Unknown",
                    classFile = classFile or "UNKNOWN",
                    isHealer = nil,
                    manaPercent = 100,
                    isDrinking = false,
                    hasInnervate = false,
                    hasManaTide = false,
                    potionExpiry = 0,
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
        end
    end

    -- Remove entries for players who left
    for guid in pairs(healers) do
        if not seenGUIDs[guid] then
            healers[guid] = nil;
            inspectRetries[guid] = nil;
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
    data.drinkExpiry = 0;
    data.innervateExpiry = 0;
    data.manaTideExpiry = 0;

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
-- Raid Cooldown Cleanup
--------------------------------------------------------------------------------

local function CleanExpiredCooldowns()
    -- No-op: keep expired entries so they show as "Ready"
    -- Entries are removed only when the caster leaves the group (ScanGroupComposition)
end

--------------------------------------------------------------------------------
-- Potion Tracking via Combat Log
--------------------------------------------------------------------------------

local function ProcessCombatLog()
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, _, _, _, _, spellId, spellName =
        CombatLogGetCurrentEventInfo();

    if subevent ~= "SPELL_CAST_SUCCESS" then return; end

    -- Potion tracking (existing)
    if POTION_SPELL_IDS[spellId] then
        local data = healers[sourceGUID];
        if data and data.isHealer then
            data.potionExpiry = GetTime() + POTION_COOLDOWN_DURATION;
        end
    end

    -- Raid cooldown tracking
    local cdInfo = RAID_COOLDOWN_SPELLS[spellId];
    if cdInfo and db.showRaidCooldowns then
        -- Verify source is in our group (COMBATLOG_OBJECT_AFFILIATION_MINE/PARTY/RAID = 0x07)
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

    -- Reset warnings if mana recovered
    if avgMana > db.warningThresholdHigh then
        warningTriggered.high = false;
        warningTriggered.med = false;
        warningTriggered.low = false;
        return;
    end

    local chatType = IsInRaid() and "RAID" or "PARTY";
    local message = nil;

    if avgMana <= db.warningThresholdLow and not warningTriggered.low then
        message = format("[HealerMana] CRITICAL: Healer mana at %d%%!", avgMana);
        warningTriggered.low = true;
        warningTriggered.med = true;
        warningTriggered.high = true;
    elseif avgMana <= db.warningThresholdMed and not warningTriggered.med then
        message = format("[HealerMana] WARNING: Healer mana at %d%%", avgMana);
        warningTriggered.med = true;
        warningTriggered.high = true;
    elseif avgMana <= db.warningThresholdHigh and not warningTriggered.high then
        message = format("[HealerMana] Healer mana below %d%% (avg: %d%%)", db.warningThresholdHigh, avgMana);
        warningTriggered.high = true;
    end

    if message then
        SendChatMessage(message, chatType);
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
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
});
HealerManaFrame:SetBackdropColor(0, 0, 0, 0.7);
HealerManaFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9);
HealerManaFrame:SetClampedToScreen(true);
HealerManaFrame:SetMovable(true);
HealerManaFrame:EnableMouse(true);
HealerManaFrame:Hide();

-- Title / average mana text (centered)
HealerManaFrame.title = HealerManaFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
HealerManaFrame.title:SetPoint("TOP", 0, -7);
HealerManaFrame.title:SetJustifyH("CENTER");

-- Separator line below header
HealerManaFrame.separator = HealerManaFrame:CreateTexture(nil, "ARTWORK");
HealerManaFrame.separator:SetHeight(1);
HealerManaFrame.separator:SetColorTexture(0.5, 0.5, 0.5, 0.4);
HealerManaFrame.separator:Hide();

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

-- Resize handle (bottom-right corner, visible when unlocked)
-- Drags width + height of the frame container; text size stays constant.
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

resizeHandle:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return; end
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
    self:SetScript("OnUpdate", nil);
end);

local function UpdateResizeHandleVisibility()
    if db and not db.locked and HealerManaFrame:IsShown() then
        resizeHandle:Show();
    else
        resizeHandle:Hide();
    end
end

HealerManaFrame:HookScript("OnShow", UpdateResizeHandleVisibility);
HealerManaFrame:HookScript("OnHide", UpdateResizeHandleVisibility);

--------------------------------------------------------------------------------
-- Row Frame Pool
--------------------------------------------------------------------------------

local function CreateRowFrame()
    local frame = CreateFrame("Frame", nil, HealerManaFrame);
    frame:SetSize(400, 16);
    frame:Hide();

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

    return frame;
end

local function AcquireRow()
    return tremove(rowPool) or CreateRowFrame();
end

local function ReleaseRow(frame)
    frame:Hide();
    frame:ClearAllPoints();
    tinsert(rowPool, frame);
end

local function ReleaseAllRows()
    for i = #activeRows, 1, -1 do
        ReleaseRow(tremove(activeRows, i));
    end
end

--------------------------------------------------------------------------------
-- Cooldown Row Frame Pool
--------------------------------------------------------------------------------

local function CreateCdRowFrame()
    local frame = CreateFrame("Frame", nil, HealerManaFrame);
    frame:SetSize(400, 16);
    frame:Hide();

    -- Spell icon (left-anchored, trimmed borders)
    frame.icon = frame:CreateTexture(nil, "ARTWORK");
    frame.icon:SetSize(14, 14);
    frame.icon:SetPoint("LEFT", 0, 0);
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);

    -- Caster name (class-colored, after icon)
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.nameText:SetPoint("LEFT", frame.icon, "RIGHT", 4, 0);
    frame.nameText:SetJustifyH("LEFT");
    frame.nameText:SetWordWrap(false);

    -- Timer countdown
    frame.timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.timerText:SetJustifyH("LEFT");

    return frame;
end

local function AcquireCdRow()
    return tremove(cdRowPool) or CreateCdRowFrame();
end

local function ReleaseCdRow(frame)
    frame:Hide();
    frame:ClearAllPoints();
    tinsert(cdRowPool, frame);
end

local function ReleaseAllCdRows()
    for i = #activeCdRows, 1, -1 do
        ReleaseCdRow(tremove(activeCdRows, i));
    end
end

--------------------------------------------------------------------------------
-- Display Update
--------------------------------------------------------------------------------

RefreshDisplay = function()
    if not db or not db.enabled then
        HealerManaFrame:Hide();
        return;
    end

    if not previewActive and not IsInGroup() and not db.showSolo then
        HealerManaFrame:Hide();
        return;
    end

    local sortedHealers = GetSortedHealers();
    if #sortedHealers == 0 then
        HealerManaFrame:Hide();
        return;
    end

    ReleaseAllRows();

    local fontPath = "Fonts\\FRIZQT__.TTF";
    local rowHeight = max(db.fontSize + 4, 16);
    local colGap = 6;
    local leftMargin = 10;
    local rightMargin = 14;
    local topPadding = 8;
    local bottomPadding = 8;

    -- Pre-compute text for all rows so we can measure actual content widths
    wipe(rowDataCache);
    local maxNameWidth = 0;
    local maxManaWidth = 0;
    local maxStatusLabelWidth = 0;
    local maxStatusDurWidth = 0;

    for _, data in ipairs(sortedHealers) do
        local manaStr;
        if data.manaPercent == -2 then
            manaStr = "DEAD";
        elseif data.manaPercent == -1 then
            manaStr = "DC";
        else
            manaStr = format("%d%%", data.manaPercent);
        end

        local statusLabel, statusDur = FormatStatusText(data);
        -- Measure without color codes for accurate width
        local labelPlain = statusLabel:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "");
        local durPlain = statusDur:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "");

        local nw = MeasureText(data.name, db.fontSize);
        local mw = MeasureText(manaStr, db.fontSize);
        local slw = 0;
        if labelPlain ~= "" then
            slw = MeasureText(labelPlain, db.fontSize - 1);
        end
        local sdw = 0;
        if durPlain ~= "" then
            sdw = MeasureText(durPlain, db.fontSize - 1);
        end

        if nw > maxNameWidth then maxNameWidth = nw; end
        if mw > maxManaWidth then maxManaWidth = mw; end
        if slw > maxStatusLabelWidth then maxStatusLabelWidth = slw; end
        if sdw > maxStatusDurWidth then maxStatusDurWidth = sdw; end

        tinsert(rowDataCache, {
            data = data,
            manaStr = manaStr,
            statusLabel = statusLabel,
            statusDur = statusDur,
        });
    end

    -- Add rendering buffer for outline font overshoot
    local pad = max(4, floor(db.fontSize * 0.35 + 0.5));
    maxNameWidth = maxNameWidth + pad;
    maxManaWidth = maxManaWidth + pad;
    if maxStatusLabelWidth > 0 then
        maxStatusLabelWidth = maxStatusLabelWidth + pad;
    end
    if maxStatusDurWidth > 0 then
        maxStatusDurWidth = maxStatusDurWidth + pad;
    end

    -- Calculate total width from actual content
    local contentWidth = maxNameWidth + colGap + maxManaWidth;
    if maxStatusLabelWidth > 0 then
        contentWidth = contentWidth + colGap + maxStatusLabelWidth;
        if maxStatusDurWidth > 0 then
            contentWidth = contentWidth + colGap + maxStatusDurWidth;
        end
    end
    local totalWidth = leftMargin + contentWidth + rightMargin;

    -- Ensure minimum width
    totalWidth = max(totalWidth, 120);

    local yOffset = -topPadding;

    -- Average mana header (centered)
    if db.showAverageMana then
        local avgMana = GetAverageMana();
        local ar, ag, ab = GetManaColor(avgMana);
        HealerManaFrame.title:SetFont(fontPath, db.fontSize, "OUTLINE");
        HealerManaFrame.title:SetFormattedText("Avg Mana: |cff%02x%02x%02x%d%%|r",
            ar * 255, ag * 255, ab * 255, avgMana);
        HealerManaFrame.title:Show();

        -- Ensure frame is wide enough for title
        local titleWidth = MeasureText("Avg Mana: " .. avgMana .. "%", db.fontSize) + leftMargin + rightMargin;
        if titleWidth > totalWidth then totalWidth = titleWidth; end

        yOffset = yOffset - rowHeight;

        -- Position and show separator
        HealerManaFrame.separator:ClearAllPoints();
        HealerManaFrame.separator:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", leftMargin, yOffset);
        HealerManaFrame.separator:SetPoint("TOPRIGHT", HealerManaFrame, "TOPRIGHT", -rightMargin, yOffset);
        HealerManaFrame.separator:Show();
        yOffset = yOffset - 4;
    else
        HealerManaFrame.title:Hide();
        HealerManaFrame.separator:Hide();
    end

    -- Healer rows
    for _, rd in ipairs(rowDataCache) do
        local data = rd.data;
        local row = AcquireRow();

        row:SetSize(totalWidth, rowHeight);
        row.nameText:SetFont(fontPath, db.fontSize, "OUTLINE");
        row.manaText:SetFont(fontPath, db.fontSize, "OUTLINE");
        row.statusText:SetFont(fontPath, db.fontSize - 1, "OUTLINE");
        row.durationText:SetFont(fontPath, db.fontSize - 1, "OUTLINE");

        -- Column widths and anchors
        row.nameText:SetWidth(maxNameWidth);
        row.manaText:SetWidth(maxManaWidth);
        row.statusText:SetWidth(maxStatusLabelWidth);

        row.manaText:ClearAllPoints();
        row.manaText:SetPoint("LEFT", row.nameText, "RIGHT", colGap, 0);
        row.statusText:ClearAllPoints();
        row.statusText:SetPoint("LEFT", row.manaText, "RIGHT", colGap, 0);
        row.durationText:ClearAllPoints();
        row.durationText:SetPoint("LEFT", row.statusText, "RIGHT", colGap, 0);

        -- Class-colored name
        local cr, cg, cb = GetClassColor(data.classFile);
        row.nameText:SetText(data.name);
        row.nameText:SetTextColor(cr, cg, cb);

        -- Mana % with color coding
        if data.manaPercent == -2 or data.manaPercent == -1 then
            row.manaText:SetText(rd.manaStr);
            row.manaText:SetTextColor(0.5, 0.5, 0.5);
        else
            row.manaText:SetText(rd.manaStr);
            local mr, mg, mb = GetManaColor(data.manaPercent);
            row.manaText:SetTextColor(mr, mg, mb);
        end

        -- Status label + duration (separate FontStrings for alignment)
        row.statusText:SetText(rd.statusLabel);
        row.durationText:SetText(rd.statusDur);

        row:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", leftMargin, yOffset);
        row:Show();
        tinsert(activeRows, row);

        yOffset = yOffset - rowHeight;
    end

    -- Raid cooldown section
    ReleaseAllCdRows();
    HealerManaFrame.cdSeparator:Hide();

    if db.showRaidCooldowns then
        -- Collect active cooldowns into sorted cache
        wipe(sortedCooldownCache);
        for _, entry in pairs(raidCooldowns) do
            tinsert(sortedCooldownCache, entry);
        end

        if #sortedCooldownCache > 0 then
            local now = GetTime();
            sort(sortedCooldownCache, function(a, b)
                local aReady = a.expiryTime <= now;
                local bReady = b.expiryTime <= now;
                if aReady ~= bReady then return bReady; end  -- on-CD first, ready last
                return a.expiryTime < b.expiryTime;
            end);

            -- Draw separator
            yOffset = yOffset - 4;
            HealerManaFrame.cdSeparator:ClearAllPoints();
            HealerManaFrame.cdSeparator:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", leftMargin, yOffset);
            HealerManaFrame.cdSeparator:SetPoint("TOPRIGHT", HealerManaFrame, "TOPRIGHT", -rightMargin, yOffset);
            HealerManaFrame.cdSeparator:Show();
            yOffset = yOffset - 4;

            -- Measure max name width for alignment
            local cdNameMax = 0;
            local cdTimerMax = 0;
            local iconSize = max(db.fontSize, 12);
            local cdFontSize = db.fontSize - 1;
            local now = GetTime();

            for _, entry in ipairs(sortedCooldownCache) do
                local nw = MeasureText(entry.name, cdFontSize);
                if nw > cdNameMax then cdNameMax = nw; end
                local timerStr;
                if entry.expiryTime <= now then
                    timerStr = "Ready";
                else
                    local remaining = entry.expiryTime - now;
                    timerStr = format("%d:%02d", floor(remaining / 60), floor(remaining) % 60);
                end
                local tw = MeasureText(timerStr, cdFontSize);
                if tw > cdTimerMax then cdTimerMax = tw; end
            end

            local cdPad = max(4, floor(cdFontSize * 0.35 + 0.5));
            cdNameMax = cdNameMax + cdPad;
            cdTimerMax = cdTimerMax + cdPad;

            -- Check if cooldown section is wider than healer content
            local cdContentWidth = iconSize + 4 + cdNameMax + colGap + cdTimerMax;
            local cdTotalWidth = leftMargin + cdContentWidth + rightMargin;
            if cdTotalWidth > totalWidth then totalWidth = cdTotalWidth; end

            -- Render cooldown rows
            for _, entry in ipairs(sortedCooldownCache) do
                local cdRow = AcquireCdRow();

                cdRow.icon:SetSize(iconSize, iconSize);
                cdRow.icon:SetTexture(entry.icon);

                cdRow.nameText:SetFont(fontPath, cdFontSize, "OUTLINE");
                cdRow.nameText:SetWidth(cdNameMax);
                local cr, cg, cb = GetClassColor(entry.classFile);
                cdRow.nameText:SetText(entry.name);
                cdRow.nameText:SetTextColor(cr, cg, cb);

                cdRow.timerText:ClearAllPoints();
                cdRow.timerText:SetPoint("LEFT", cdRow.nameText, "RIGHT", colGap, 0);
                cdRow.timerText:SetFont(fontPath, cdFontSize, "OUTLINE");
                if entry.expiryTime <= now then
                    cdRow.timerText:SetText("Ready");
                    cdRow.timerText:SetTextColor(0.0, 1.0, 0.0);
                else
                    local remaining = entry.expiryTime - now;
                    cdRow.timerText:SetText(format("%d:%02d", floor(remaining / 60), floor(remaining) % 60));
                    cdRow.timerText:SetTextColor(0.8, 0.8, 0.8);
                end

                cdRow:SetSize(totalWidth, rowHeight);
                cdRow:SetPoint("TOPLEFT", HealerManaFrame, "TOPLEFT", leftMargin, yOffset);
                cdRow:Show();
                tinsert(activeCdRows, cdRow);

                yOffset = yOffset - rowHeight;
            end
        end
    end

    -- Track content-driven minimums (used by resize handle to prevent clipping)
    local totalHeight = -yOffset + bottomPadding;
    contentMinWidth = totalWidth;
    contentMinHeight = totalHeight;

    -- Respect user-set dimensions as minimums
    totalHeight = max(totalHeight, db.frameHeight or 30);
    totalWidth = max(totalWidth, db.frameWidth or 120);
    HealerManaFrame:SetHeight(totalHeight);
    HealerManaFrame:SetWidth(totalWidth);
    HealerManaFrame:Show();
end

--------------------------------------------------------------------------------
-- OnUpdate Handler
--------------------------------------------------------------------------------

local previewTimer = 0;

-- Display OnUpdate: runs only when HealerManaFrame is visible (animations, mana updates)
HealerManaFrame:SetScript("OnUpdate", function(self, elapsed)
    updateElapsed = updateElapsed + elapsed;
    if updateElapsed >= UPDATE_INTERVAL then
        updateElapsed = 0;

        if previewActive then
            -- Animate mock mana values: slow drift with occasional drinking recovery
            previewTimer = previewTimer + UPDATE_INTERVAL;
            local now = GetTime();
            for guid, data in pairs(healers) do
                if data.isHealer and data.baseMana then
                    local seed = (data.driftSeed or 1);
                    local drift = sin(previewTimer * 0.4 * seed) * 0.8 + cos(previewTimer * 0.15 * seed) * 0.5;
                    data.manaPercent = max(0, min(100, data.baseMana + floor(drift * 12)));
                    -- Loop status durations so they restart after expiring
                    if data.isDrinking and data.drinkExpiry > 0 and data.drinkExpiry <= now then
                        data.drinkExpiry = now + 18;
                    end
                    if data.hasInnervate and data.innervateExpiry > 0 and data.innervateExpiry <= now then
                        data.innervateExpiry = now + 12;
                    end
                    if data.hasManaTide and data.manaTideExpiry > 0 and data.manaTideExpiry <= now then
                        data.manaTideExpiry = now + 8;
                    end
                end
            end
            -- Loop some preview raid cooldown timers; leave others as "Ready"
            for key, entry in pairs(raidCooldowns) do
                if entry.expiryTime <= now then
                    if key == "preview-inn" or key == "preview-rebirth" then
                        -- Leave expired so they show "Ready"
                    else
                        entry.expiryTime = now + RAID_COOLDOWN_SPELLS[entry.spellId].duration;
                    end
                end
            end
        else
            UpdateManaValues();
            UpdateAllHealerBuffs();
            CleanExpiredCooldowns();
            CheckManaWarnings();
        end

        RefreshDisplay();
    end
end);

-- Background OnUpdate: always runs (inspect queue + display visibility check)
-- Separate frame because HealerManaFrame is hidden until healers are confirmed,
-- and hidden frames don't receive OnUpdate in WoW.
local BackgroundFrame = CreateFrame("Frame");
BackgroundFrame:SetScript("OnUpdate", function(self, elapsed)
    if previewActive then return; end

    inspectElapsed = inspectElapsed + elapsed;
    if inspectElapsed >= INSPECT_REQUEUE_INTERVAL then
        inspectElapsed = 0;
        -- Re-queue members still awaiting inspection
        if #inspectQueue == 0 and not inspectPending then
            for guid, data in pairs(healers) do
                if data.isHealer == nil and data.unit and UnitExists(data.unit) then
                    QueueInspect(data.unit);
                end
            end
        end
        ProcessInspectQueue();
    end

    -- When main frame is hidden, periodically check if it should become visible
    if not HealerManaFrame:IsShown() then
        updateElapsed = updateElapsed + elapsed;
        if updateElapsed >= UPDATE_INTERVAL then
            updateElapsed = 0;
            UpdateManaValues();
            RefreshDisplay();
        end
    end
end);

--------------------------------------------------------------------------------
-- Preview System
--------------------------------------------------------------------------------

local PREVIEW_DATA = {
    { name = "Holypriest", classFile = "PRIEST", baseMana = 82, driftSeed = 1.0 },
    { name = "Treehugger", classFile = "DRUID", baseMana = 45, isDrinking = true, driftSeed = 1.4 },
    { name = "Palaheals", classFile = "PALADIN", baseMana = 18, hasInnervate = true, driftSeed = 0.7 },
    { name = "Tidecaller", classFile = "SHAMAN", baseMana = 64, hasManaTide = true, driftSeed = 1.2 },
};

local function StartPreview()
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
            unit = nil,
            name = td.name,
            classFile = td.classFile,
            isHealer = true,
            manaPercent = td.baseMana,
            baseMana = td.baseMana,
            driftSeed = td.driftSeed,
            isDrinking = td.isDrinking or false,
            hasInnervate = td.hasInnervate or false,
            hasManaTide = td.hasManaTide or false,
            drinkExpiry = td.isDrinking and (GetTime() + 18) or 0,
            innervateExpiry = td.hasInnervate and (GetTime() + 12) or 0,
            manaTideExpiry = td.hasManaTide and (GetTime() + 8) or 0,
            potionExpiry = 0,
        };
    end

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
        expiryTime = now + 180,
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
        expiryTime = now + 900,
    };

    -- Unlock frame for dragging while options are open
    HealerManaFrame:EnableMouse(true);
    RefreshDisplay();
end

local function StopPreview()
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

    -- Restore lock state
    HealerManaFrame:EnableMouse(not db.locked);
    RefreshDisplay();
end

--------------------------------------------------------------------------------
-- Options GUI
--------------------------------------------------------------------------------

local OptionsFrame;

-- Backdrop templates (matching ScrollingLoot style)
local FrameBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
};

local SliderBackdrop = {
    bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
    edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 3, right = 3, top = 6, bottom = 6 }
};

local EditBoxBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, edgeSize = 1, tileSize = 5,
};

local PaneBackdrop = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 5, bottom = 3 }
};

-- Create a slider widget
local function CreateSlider(parent, label, minVal, maxVal, step, width)
    local container = CreateFrame("Frame", nil, parent);
    container:SetSize(width or 200, 50);

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    labelText:SetPoint("TOPLEFT");
    labelText:SetPoint("TOPRIGHT");
    labelText:SetJustifyH("CENTER");
    labelText:SetHeight(15);
    labelText:SetText(label);
    labelText:SetTextColor(1, 0.82, 0);

    local slider = CreateFrame("Slider", nil, container, "BackdropTemplate");
    slider:SetOrientation("HORIZONTAL");
    slider:SetSize(width or 200, 15);
    slider:SetPoint("TOP", labelText, "BOTTOM", 0, -2);
    slider:SetBackdrop(SliderBackdrop);
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal");
    slider:SetMinMaxValues(minVal, maxVal);
    slider:SetValueStep(step or 1);
    slider:SetObeyStepOnDrag(true);

    local lowText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, 3);
    lowText:SetText(minVal);

    local highText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, 3);
    highText:SetText(maxVal);

    local editBox = CreateFrame("EditBox", nil, container, "BackdropTemplate");
    editBox:SetAutoFocus(false);
    editBox:SetFontObject(GameFontHighlightSmall);
    editBox:SetPoint("TOP", slider, "BOTTOM", 0, -2);
    editBox:SetSize(60, 14);
    editBox:SetJustifyH("CENTER");
    editBox:EnableMouse(true);
    editBox:SetBackdrop(EditBoxBackdrop);
    editBox:SetBackdropColor(0, 0, 0, 0.5);
    editBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8);

    slider:SetScript("OnValueChanged", function(self, value)
        value = floor(value / step + 0.5) * step;
        editBox:SetText(value);
        if container.OnValueChanged then
            container:OnValueChanged(value);
        end
    end);

    editBox:SetScript("OnEnterPressed", function(self)
        local value = tonumber(self:GetText());
        if value then
            value = max(minVal, min(maxVal, value));
            slider:SetValue(value);
        end
        self:ClearFocus();
    end);

    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(floor(slider:GetValue() / step + 0.5) * step);
        self:ClearFocus();
    end);

    container.slider = slider;
    container.editBox = editBox;
    container.labelText = labelText;

    function container:SetValue(value)
        slider:SetValue(value);
        editBox:SetText(floor(value / step + 0.5) * step);
    end

    function container:GetValue()
        return slider:GetValue();
    end

    return container;
end

-- Create a checkbox widget
local function CreateCheckbox(parent, label, width)
    local container = CreateFrame("Frame", nil, parent);
    container:SetSize(width or 200, 24);

    local checkbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate");
    checkbox:SetPoint("LEFT");
    checkbox:SetSize(24, 24);

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    labelText:SetPoint("LEFT", checkbox, "RIGHT", 2, 0);
    labelText:SetText(label);

    checkbox:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and 856 or 857);
        if container.OnValueChanged then
            container:OnValueChanged(self:GetChecked());
        end
    end);

    container.checkbox = checkbox;
    container.labelText = labelText;

    function container:SetValue(value)
        checkbox:SetChecked(value);
    end

    function container:GetValue()
        return checkbox:GetChecked();
    end

    return container;
end

-- Create a dropdown widget
local function CreateDropdown(parent, label, options, width)
    local container = CreateFrame("Frame", nil, parent);
    container:SetSize(width or 200, 50);

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    labelText:SetPoint("TOPLEFT");
    labelText:SetPoint("TOPRIGHT");
    labelText:SetJustifyH("CENTER");
    labelText:SetHeight(15);
    labelText:SetText(label);
    labelText:SetTextColor(1, 0.82, 0);

    local dropdown = CreateFrame("Frame", nil, container, "BackdropTemplate");
    dropdown:SetSize(width or 200, 24);
    dropdown:SetPoint("TOP", labelText, "BOTTOM", 0, -2);
    dropdown:SetBackdrop(PaneBackdrop);
    dropdown:SetBackdropColor(0.1, 0.1, 0.1);
    dropdown:SetBackdropBorderColor(0.4, 0.4, 0.4);

    local selectedText = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    selectedText:SetPoint("LEFT", 8, 0);
    selectedText:SetPoint("RIGHT", -24, 0);
    selectedText:SetJustifyH("LEFT");

    local expandButton = CreateFrame("Button", nil, dropdown);
    expandButton:SetSize(20, 20);
    expandButton:SetPoint("RIGHT", -2, 0);
    expandButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up");
    expandButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down");
    expandButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");

    local menuFrame = CreateFrame("Frame", nil, dropdown, "BackdropTemplate");
    menuFrame:SetBackdrop(PaneBackdrop);
    menuFrame:SetBackdropColor(0.1, 0.1, 0.1);
    menuFrame:SetBackdropBorderColor(0.4, 0.4, 0.4);
    menuFrame:SetPoint("TOP", dropdown, "BOTTOM", 0, 2);
    menuFrame:SetFrameStrata("TOOLTIP");
    menuFrame:SetFrameLevel(200);
    menuFrame:Hide();

    local buttonHeight = 20;
    local menuHeight = 4;

    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, menuFrame);
        btn:SetSize((width or 200) - 6, buttonHeight);
        btn:SetPoint("TOPLEFT", 3, -2 - (i - 1) * buttonHeight);

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
        btnText:SetPoint("LEFT", 4, 0);
        btnText:SetText(opt.text);

        local highlight = btn:CreateTexture(nil, "HIGHLIGHT");
        highlight:SetAllPoints();
        highlight:SetColorTexture(0.3, 0.3, 0.5, 0.5);

        btn:SetScript("OnClick", function()
            container.selectedValue = opt.value;
            selectedText:SetText(opt.text);
            menuFrame:Hide();
            PlaySound(856);
            if container.OnValueChanged then
                container:OnValueChanged(opt.value);
            end
        end);

        menuHeight = menuHeight + buttonHeight;
    end

    menuFrame:SetSize((width or 200), menuHeight + 4);

    local function ToggleMenu()
        if menuFrame:IsShown() then
            menuFrame:Hide();
        else
            menuFrame:Show();
        end
    end

    expandButton:SetScript("OnClick", ToggleMenu);
    dropdown:EnableMouse(true);
    dropdown:SetScript("OnMouseDown", ToggleMenu);

    menuFrame:SetScript("OnShow", function()
        menuFrame:SetScript("OnUpdate", function()
            if not dropdown:IsMouseOver() and not menuFrame:IsMouseOver() then
                menuFrame:Hide();
            end
        end);
    end);

    menuFrame:SetScript("OnHide", function()
        menuFrame:SetScript("OnUpdate", nil);
    end);

    container.dropdown = dropdown;
    container.selectedText = selectedText;

    function container:SetValue(value)
        container.selectedValue = value;
        for _, opt in ipairs(options) do
            if opt.value == value then
                selectedText:SetText(opt.text);
                break;
            end
        end
    end

    function container:GetValue()
        return container.selectedValue;
    end

    return container;
end

-- Create the main options frame
local function CreateOptionsFrame()
    if OptionsFrame then return OptionsFrame; end

    local frame = CreateFrame("Frame", "HealerManaOptionsFrame", UIParent, "BackdropTemplate");
    frame:SetSize(520, 680);
    frame:SetPoint("CENTER");
    frame:SetBackdrop(FrameBackdrop);
    frame:SetBackdropColor(0, 0, 0, db.optionsBgOpacity);
    frame:SetMovable(true);
    frame:EnableMouse(true);
    frame:SetToplevel(true);
    frame:SetFrameStrata("DIALOG");
    frame:SetFrameLevel(100);
    frame:Hide();

    -- Title bar
    local titleBg = frame:CreateTexture(nil, "OVERLAY");
    titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBg:SetTexCoord(0.31, 0.67, 0, 0.63);
    titleBg:SetPoint("TOP", 0, 12);
    titleBg:SetSize(200, 40);

    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    titleText:SetPoint("TOP", titleBg, "TOP", 0, -14);
    titleText:SetText("HealerMana Options");

    local titleBgL = frame:CreateTexture(nil, "OVERLAY");
    titleBgL:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBgL:SetTexCoord(0.21, 0.31, 0, 0.63);
    titleBgL:SetPoint("RIGHT", titleBg, "LEFT");
    titleBgL:SetSize(30, 40);

    local titleBgR = frame:CreateTexture(nil, "OVERLAY");
    titleBgR:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    titleBgR:SetTexCoord(0.67, 0.77, 0, 0.63);
    titleBgR:SetPoint("LEFT", titleBg, "RIGHT");
    titleBgR:SetSize(30, 40);

    -- Make draggable
    frame:RegisterForDrag("LeftButton");
    frame:SetScript("OnDragStart", frame.StartMoving);
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing);

    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
    closeButton:SetPoint("TOPRIGHT", -5, -5);

    -- Content area
    local contentWidth = 230;
    local leftX = 20;
    local rightX = 270;
    local startY = -35;

    -------------------------------
    -- LEFT COLUMN: Toggle Settings
    -------------------------------
    local y = startY;

    -- Section header
    local displayHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    displayHeader:SetPoint("TOPLEFT", leftX, y);
    displayHeader:SetText("Display Settings");
    displayHeader:SetTextColor(1, 0.82, 0);
    y = y - 22;

    local enabledCheck = CreateCheckbox(frame, "Enable HealerMana", contentWidth);
    enabledCheck:SetPoint("TOPLEFT", leftX, y);
    enabledCheck:SetValue(db.enabled);
    enabledCheck.OnValueChanged = function(self, value)
        db.enabled = value;
        RefreshDisplay();
    end;
    y = y - 26;

    local showSoloCheck = CreateCheckbox(frame, "Show When Solo", contentWidth);
    showSoloCheck:SetPoint("TOPLEFT", leftX, y);
    showSoloCheck:SetValue(db.showSolo);
    showSoloCheck.OnValueChanged = function(self, value)
        db.showSolo = value;
        if not previewActive and value and not IsInGroup() then
            ScanGroupComposition();
        end
    end;
    y = y - 26;

    local showAvgCheck = CreateCheckbox(frame, "Show Average Mana", contentWidth);
    showAvgCheck:SetPoint("TOPLEFT", leftX, y);
    showAvgCheck:SetValue(db.showAverageMana);
    showAvgCheck.OnValueChanged = function(self, value)
        db.showAverageMana = value;
    end;
    y = y - 26;

    local showDrinkCheck = CreateCheckbox(frame, "Show Drinking Status", contentWidth);
    showDrinkCheck:SetPoint("TOPLEFT", leftX, y);
    showDrinkCheck:SetValue(db.showDrinking);
    showDrinkCheck.OnValueChanged = function(self, value)
        db.showDrinking = value;
    end;
    y = y - 26;

    local showInnervateCheck = CreateCheckbox(frame, "Show Innervate", contentWidth);
    showInnervateCheck:SetPoint("TOPLEFT", leftX, y);
    showInnervateCheck:SetValue(db.showInnervate);
    showInnervateCheck.OnValueChanged = function(self, value)
        db.showInnervate = value;
    end;
    y = y - 26;

    local showManaTideCheck = CreateCheckbox(frame, "Show Mana Tide", contentWidth);
    showManaTideCheck:SetPoint("TOPLEFT", leftX, y);
    showManaTideCheck:SetValue(db.showManaTide);
    showManaTideCheck.OnValueChanged = function(self, value)
        db.showManaTide = value;
    end;
    y = y - 26;

    local showPotionCheck = CreateCheckbox(frame, "Show Potion Cooldowns", contentWidth);
    showPotionCheck:SetPoint("TOPLEFT", leftX, y);
    showPotionCheck:SetValue(db.showPotionCooldown);
    showPotionCheck.OnValueChanged = function(self, value)
        db.showPotionCooldown = value;
    end;
    y = y - 26;

    local showRaidCdCheck = CreateCheckbox(frame, "Show Raid Cooldowns", contentWidth);
    showRaidCdCheck:SetPoint("TOPLEFT", leftX, y);
    showRaidCdCheck:SetValue(db.showRaidCooldowns);
    showRaidCdCheck.OnValueChanged = function(self, value)
        db.showRaidCooldowns = value;
    end;
    y = y - 26;

    local shortenedCheck = CreateCheckbox(frame, "Shortened Status Labels", contentWidth);
    shortenedCheck:SetPoint("TOPLEFT", leftX, y);
    shortenedCheck:SetValue(db.shortenedStatus);
    shortenedCheck.OnValueChanged = function(self, value)
        db.shortenedStatus = value;
    end;
    y = y - 26;

    local showDurationCheck = CreateCheckbox(frame, "Show Buff Durations", contentWidth);
    showDurationCheck:SetPoint("TOPLEFT", leftX, y);
    showDurationCheck:SetValue(db.showStatusDuration);
    showDurationCheck.OnValueChanged = function(self, value)
        db.showStatusDuration = value;
    end;
    y = y - 26;

    local lockedCheck = CreateCheckbox(frame, "Lock Frame Position", contentWidth);
    lockedCheck:SetPoint("TOPLEFT", leftX, y);
    lockedCheck:SetValue(db.locked);
    lockedCheck.OnValueChanged = function(self, value)
        db.locked = value;
        HealerManaFrame:EnableMouse(not value);
        UpdateResizeHandleVisibility();
    end;
    y = y - 30;

    -- Warning section header
    local warnHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    warnHeader:SetPoint("TOPLEFT", leftX, y);
    warnHeader:SetText("Chat Warnings");
    warnHeader:SetTextColor(1, 0.82, 0);
    y = y - 22;

    local sendWarnCheck = CreateCheckbox(frame, "Send Warning Messages", contentWidth);
    sendWarnCheck:SetPoint("TOPLEFT", leftX, y);
    sendWarnCheck:SetValue(db.sendWarnings);
    sendWarnCheck.OnValueChanged = function(self, value)
        db.sendWarnings = value;
    end;
    y = y - 30;

    local warnCooldownSlider = CreateSlider(frame, "Warning Cooldown (sec)", 10, 120, 5, contentWidth);
    warnCooldownSlider:SetPoint("TOPLEFT", leftX, y);
    warnCooldownSlider:SetValue(db.warningCooldown);
    warnCooldownSlider.OnValueChanged = function(self, value)
        db.warningCooldown = value;
    end;
    y = y - 58;

    local warnHighSlider = CreateSlider(frame, "Warning High Threshold (%)", 10, 60, 5, contentWidth);
    warnHighSlider:SetPoint("TOPLEFT", leftX, y);
    warnHighSlider:SetValue(db.warningThresholdHigh);
    warnHighSlider.OnValueChanged = function(self, value)
        db.warningThresholdHigh = value;
    end;
    y = y - 58;

    local warnMedSlider = CreateSlider(frame, "Warning Medium Threshold (%)", 5, 50, 5, contentWidth);
    warnMedSlider:SetPoint("TOPLEFT", leftX, y);
    warnMedSlider:SetValue(db.warningThresholdMed);
    warnMedSlider.OnValueChanged = function(self, value)
        db.warningThresholdMed = value;
    end;
    y = y - 58;

    local warnLowSlider = CreateSlider(frame, "Warning Low Threshold (%)", 1, 30, 1, contentWidth);
    warnLowSlider:SetPoint("TOPLEFT", leftX, y);
    warnLowSlider:SetValue(db.warningThresholdLow);
    warnLowSlider.OnValueChanged = function(self, value)
        db.warningThresholdLow = value;
    end;

    --------------------------------
    -- RIGHT COLUMN: Appearance
    --------------------------------
    y = startY;

    local appearHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    appearHeader:SetPoint("TOPLEFT", rightX, y);
    appearHeader:SetText("Appearance");
    appearHeader:SetTextColor(1, 0.82, 0);
    y = y - 26;

    local fontSizeSlider = CreateSlider(frame, "Font Size", 8, 24, 1, contentWidth);
    fontSizeSlider:SetPoint("TOPLEFT", rightX, y);
    fontSizeSlider:SetValue(db.fontSize);
    fontSizeSlider.OnValueChanged = function(self, value)
        db.fontSize = value;
    end;
    y = y - 58;

    local scaleSlider = CreateSlider(frame, "Scale", 0.5, 2.0, 0.1, contentWidth);
    scaleSlider:SetPoint("TOPLEFT", rightX, y);
    scaleSlider:SetValue(db.scale);
    scaleSlider.OnValueChanged = function(self, value)
        db.scale = value;
        HealerManaFrame:SetScale(value);
    end;
    y = y - 58;

    local bgOpacitySlider = CreateSlider(frame, "Display Opacity (%)", 0, 100, 5, contentWidth);
    bgOpacitySlider:SetPoint("TOPLEFT", rightX, y);
    bgOpacitySlider:SetValue(db.bgOpacity * 100);
    bgOpacitySlider.OnValueChanged = function(self, value)
        db.bgOpacity = value / 100;
        HealerManaFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
    end;
    y = y - 58;

    local optBgSlider = CreateSlider(frame, "Options Panel Opacity (%)", 0, 100, 5, contentWidth);
    optBgSlider:SetPoint("TOPLEFT", rightX, y);
    optBgSlider:SetValue(db.optionsBgOpacity * 100);
    optBgSlider.OnValueChanged = function(self, value)
        db.optionsBgOpacity = value / 100;
        frame:SetBackdropColor(0, 0, 0, db.optionsBgOpacity);
    end;
    y = y - 62;

    -- Color threshold section
    local colorHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    colorHeader:SetPoint("TOPLEFT", rightX, y);
    colorHeader:SetText("Mana Color Thresholds");
    colorHeader:SetTextColor(1, 0.82, 0);
    y = y - 26;

    local greenSlider = CreateSlider(frame, "Green (above %)", 50, 100, 5, contentWidth);
    greenSlider:SetPoint("TOPLEFT", rightX, y);
    greenSlider:SetValue(db.colorThresholdGreen);
    greenSlider.OnValueChanged = function(self, value)
        db.colorThresholdGreen = value;
    end;
    y = y - 58;

    local yellowSlider = CreateSlider(frame, "Yellow (above %)", 25, 75, 5, contentWidth);
    yellowSlider:SetPoint("TOPLEFT", rightX, y);
    yellowSlider:SetValue(db.colorThresholdYellow);
    yellowSlider.OnValueChanged = function(self, value)
        db.colorThresholdYellow = value;
    end;
    y = y - 58;

    local orangeSlider = CreateSlider(frame, "Orange (above %)", 0, 50, 5, contentWidth);
    orangeSlider:SetPoint("TOPLEFT", rightX, y);
    orangeSlider:SetValue(db.colorThresholdOrange);
    orangeSlider.OnValueChanged = function(self, value)
        db.colorThresholdOrange = value;
    end;
    y = y - 62;

    -- Sort dropdown
    local sortDropdown = CreateDropdown(frame, "Sort Healers By", {
        { text = "Lowest Mana First", value = "mana" },
        { text = "Name (A-Z)", value = "name" },
    }, contentWidth);
    sortDropdown:SetPoint("TOPLEFT", rightX, y);
    sortDropdown:SetValue(db.sortBy);
    sortDropdown.OnValueChanged = function(self, value)
        db.sortBy = value;
    end;

    -- Reset button (bottom center)
    local resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    resetButton:SetSize(140, 24);
    resetButton:SetPoint("BOTTOM", 0, 18);
    resetButton:SetText("Reset Defaults");
    resetButton:SetScript("OnClick", function()
        for key, value in pairs(DEFAULT_SETTINGS) do
            db[key] = value;
        end
        -- Refresh all widgets
        enabledCheck:SetValue(db.enabled);
        showSoloCheck:SetValue(db.showSolo);
        showAvgCheck:SetValue(db.showAverageMana);
        showDrinkCheck:SetValue(db.showDrinking);
        showInnervateCheck:SetValue(db.showInnervate);
        showManaTideCheck:SetValue(db.showManaTide);
        showPotionCheck:SetValue(db.showPotionCooldown);
        showRaidCdCheck:SetValue(db.showRaidCooldowns);
        shortenedCheck:SetValue(db.shortenedStatus);
        showDurationCheck:SetValue(db.showStatusDuration);
        lockedCheck:SetValue(db.locked);
        sendWarnCheck:SetValue(db.sendWarnings);
        warnCooldownSlider:SetValue(db.warningCooldown);
        warnHighSlider:SetValue(db.warningThresholdHigh);
        warnMedSlider:SetValue(db.warningThresholdMed);
        warnLowSlider:SetValue(db.warningThresholdLow);
        fontSizeSlider:SetValue(db.fontSize);
        scaleSlider:SetValue(db.scale);
        bgOpacitySlider:SetValue(db.bgOpacity * 100);
        greenSlider:SetValue(db.colorThresholdGreen);
        yellowSlider:SetValue(db.colorThresholdYellow);
        orangeSlider:SetValue(db.colorThresholdOrange);
        sortDropdown:SetValue(db.sortBy);
        optBgSlider:SetValue(db.optionsBgOpacity * 100);
        frame:SetBackdropColor(0, 0, 0, db.optionsBgOpacity);
        -- Reset frame position
        HealerManaFrame:SetScale(db.scale);
        HealerManaFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        HealerManaFrame:EnableMouse(not db.locked);
        UpdateResizeHandleVisibility();
        HealerManaFrame:ClearAllPoints();
        HealerManaFrame:SetPoint("LEFT", UIParent, "LEFT", 20, 100);
        db.frameX = nil;
        db.frameY = nil;
        print("|cff00ff00HealerMana|r settings reset to defaults.");
    end);

    -- Live preview: show mock healers while options are open
    frame:SetScript("OnShow", function()
        if not previewActive then
            StartPreview();
        end
    end);

    frame:SetScript("OnHide", function()
        if previewActive then
            StopPreview();
        end
    end);

    -- ESC to close
    tinsert(UISpecialFrames, "HealerManaOptionsFrame");

    OptionsFrame = frame;
    return frame;
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

        -- Apply saved position
        if db.frameX and db.frameY then
            HealerManaFrame:ClearAllPoints();
            HealerManaFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.frameX, db.frameY);
        else
            HealerManaFrame:SetPoint("LEFT", UIParent, "LEFT", 20, 100);
        end

        -- Apply settings
        HealerManaFrame:SetScale(db.scale);
        HealerManaFrame:SetBackdropColor(0, 0, 0, db.bgOpacity);
        HealerManaFrame:EnableMouse(not db.locked);
        UpdateResizeHandleVisibility();

        self:UnregisterEvent("ADDON_LOADED");
        print("|cff00ff00HealerMana|r loaded. Type |cff00ffff/hm|r for options.");

    elseif event == "PLAYER_LOGIN" then
        if IsInGroup() or db.showSolo then
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

local function ToggleOptionsFrame()
    local frame = CreateOptionsFrame();
    if frame:IsShown() then
        frame:Hide();
    else
        frame:Show();
    end
end

local function SlashCommandHandler(msg)
    msg = msg and msg:lower():trim() or "";

    if msg == "" or msg == "options" or msg == "config" then
        ToggleOptionsFrame();

    elseif msg == "lock" then
        db.locked = not db.locked;
        HealerManaFrame:EnableMouse(not db.locked);
        UpdateResizeHandleVisibility();
        if db.locked then
            print("|cff00ff00HealerMana|r frame locked.");
        else
            print("|cff00ff00HealerMana|r frame unlocked. Drag to reposition.");
        end

    elseif msg == "test" then
        if previewActive then
            -- Close options panel first to prevent its OnHide from interfering
            if OptionsFrame and OptionsFrame:IsShown() then
                OptionsFrame:Hide();
            end
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
        UpdateResizeHandleVisibility();
        HealerManaFrame:ClearAllPoints();
        HealerManaFrame:SetPoint("LEFT", UIParent, "LEFT", 20, 100);
        db.frameX = nil;
        db.frameY = nil;
        print("|cff00ff00HealerMana|r settings reset to defaults.");

    elseif msg == "help" then
        print("|cff00ff00HealerMana|r commands:");
        print("  |cff00ffff/hm|r - Open options panel");
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
