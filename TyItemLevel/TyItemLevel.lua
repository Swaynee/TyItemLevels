-- TyItemLevel.lua
TyIL = {}
local addon = TyIL
local _G = _G
local myname, myfullname = ...
if C_AddOns and myname then myfullname = C_AddOns.GetAddOnMetadata(myname, "Title") or myname end
-- expose addon name/title for config module (TOC loads TyItemLevel.lua first)
addon.name = myname
addon.title = myfullname

-- Standard-Konfiguration
addon.config = {
    items = {
        enabled = true,
        showAverage = true,
        fontSize = 12,
        -- 1=None, 2=OUTLINE, 3=THICKOUTLINE, 4=Shadow
        fontOutline = 4,
    },
    enchants = {
        enabled = true,
        fontSize = 10,
        fontOutline = 4,
        maxLength = 18,
        showQuality = false,
    },
    gems = {
        enabled = true,
    }
}

-- SavedVariables (will be declared in TOC as TyItemLevelDB)

-- Options UI and SavedVariables handling moved to TyItemLevel_Config.lua
-- CreateOptionsPanel and LoadSavedVariables are exposed on the addon table there.

-- Listen for ADDON_LOADED to initialize saved variables
-- (ADDON_LOADED handling will be registered on the frame created below)


-- Statusvariablen
addon.characterOpen = false
addon.inspecting = false
addon.lastInspectUnit = nil
addon.lastInspectGuid = nil
addon.itemInfoRequested = {}

------------------------------------------------
-- ========== CODE AUS Tyfons WEAKAURA =========
------------------------------------------------

addon.characterOpen = false;

-- itemIDs for async loading
addon.itemInfoRequested = {}

-- Hooking NotifyInspect to remember the unit last inspected
-- This will be used async when INSPECT_READY is called
addon.inspecting = false;
addon.lastInspectUnit = nil
addon.lastInspectGuid = nil

hooksecurefunc("NotifyInspect", function(unit)
        --print("NotifyInspect: " .. unit .. " (" .. UnitGUID(unit) .. ")")
        
        -- don't run on mouseover
        if (unit == "mouseover") then return end
        
        -- there's some weird thing where inspect is called on yourself? Ignore these
        if (unit == GetUnitName("player")) then return end
        
        addon.lastInspectUnit = unit
        addon.lastInspectGuid = UnitGUID(unit)
end)

-- Get the name of the item frame
local getSlotFrameName = function(unit, slot)
    local slotName
    local prefix = "Inspect"
    if (unit == "player") then
        prefix = "Character"
    end
    
    if (slot == 1) then
        slotName = "Head"
    elseif (slot == 2) then
        slotName = "Neck"
    elseif (slot == 3) then
        slotName = "Shoulder"
    elseif (slot == 4) then
        slotName = "Shirt"
    elseif (slot == 5) then
        slotName = "Chest"
    elseif (slot == 6) then
        slotName = "Waist"
    elseif (slot == 7) then
        slotName = "Legs"
    elseif (slot == 8) then
        slotName = "Feet"
    elseif (slot == 9) then
        slotName = "Wrist"
    elseif (slot == 10) then
        slotName = "Hands"
    elseif (slot == 11) then
        slotName = "Finger0"
    elseif (slot == 12) then
        slotName = "Finger1"
    elseif (slot == 13) then
        slotName = "Trinket0"
    elseif (slot == 14) then
        slotName = "Trinket1"
    elseif (slot == 15) then
        slotName = "Back"
    elseif (slot == 16) then
        slotName = "MainHand"
    elseif (slot == 17) then
        slotName = "SecondaryHand"
    elseif (slot == 19) then
        slotName = "Tabard"
    else
        return nil
    end
    
    return prefix .. slotName .. "Slot"
end

-- Returns true if the slot is on the right side of the character panel
local isRightSide = function(slot)
    if (slot == 6 or slot == 7 or slot == 8 or slot == 10 or slot == 11 or slot == 12 or slot == 13 or slot == 14 or
    slot == 16) then
        return true
    end
    return false
end

local fontMap = {
    nil, -- none
    "OUTLINE",
    "THICKOUTLINE",
    nil -- drop shadow
}

-- removed old hard-coded level->rarity fallback; we now use item-quality colors directly

-- Compute an average color hex (AArrGgBb) from the qualities of equipped items on the unit.
local function computeAverageQualityHex(unit)
    local rsum, gsum, bsum, count = 0, 0, 0, 0
    for slot = 1, 19 do
        local link = GetInventoryItemLink(unit, slot)
        if link and link ~= "" then
            local _, _, quality = C_Item.GetItemInfo(link)
            -- if quality not available synchronously, skip this slot - GET_ITEM_INFO_RECEIVED will trigger later
            if quality and quality >= 0 then
                local added = false
                -- Prefer ColorManager if present
                if ColorManager and ColorManager.GetColorDataForItemQuality then
                    local cd = ColorManager.GetColorDataForItemQuality(quality)
                    if cd and cd.hex then
                        local hex = cd.hex
                        local r = tonumber(string.sub(hex, 3, 4), 16) or 255
                        local g = tonumber(string.sub(hex, 5, 6), 16) or 255
                        local b = tonumber(string.sub(hex, 7, 8), 16) or 255
                        rsum = rsum + (r / 255)
                        gsum = gsum + (g / 255)
                        bsum = bsum + (b / 255)
                        count = count + 1
                        added = true
                    end
                end

                if (not added) and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality] then
                    local tbl = _G.ITEM_QUALITY_COLORS[quality]
                    if tbl and tbl.color then
                        local c = tbl.color
                        rsum = rsum + (c.r or 1)
                        gsum = gsum + (c.g or 1)
                        bsum = bsum + (c.b or 1)
                        count = count + 1
                        added = true
                    end
                end
                -- if still not added, we can't compute color for this slot now
            end
        end
    end

    if count == 0 then return "FFFFFFFF" end
    local rr = math.floor((rsum / count) * 255 + 0.5)
    local gg = math.floor((gsum / count) * 255 + 0.5)
    local bb = math.floor((bsum / count) * 255 + 0.5)
    return string.format("FF%02X%02X%02X", rr, gg, bb)
end

-- Update a Specific Slot
addon.updateSlot = function(unit, slot)
    if (unit == nil or slot == nil) then
        return
    end
    
    local itemLink = GetInventoryItemLink(unit, slot)
    local slotFrameName = getSlotFrameName(unit, slot)
    if (slotFrameName == nil or _G[slotFrameName] == nil) then return end
    
    local rightSide = isRightSide(slot)
    local framePoint = rightSide and "RIGHT" or "LEFT"
    local parentPoint = rightSide and "LEFT" or "RIGHT"
    local offsetX = rightSide and -10 or 9
    
    local LevelText = _G[slotFrameName .. "TyIlvl"]
    local AverageLevelText = _G["TyAvgIlvl"]
    local EnchantText = _G[slotFrameName .. "TyEnchant"]
    local GemFrames = {}
    for i = 1, 3 do
        GemFrames[i] = _G[slotFrameName .. "TyGem" .. i]
    end
    
    -- create and position frames if they don't exist
    if (LevelText == nil) then
        LevelText = _G[slotFrameName]:CreateFontString(slotFrameName .. "TyIlvl", "ARTWORK", "GameTooltipText")
        if (slot == 16 or slot == 17) then -- weapons put the ilvl on top
            LevelText:SetPoint("BOTTOM", _G[slotFrameName], "TOP", 0, 5)
        else
            LevelText:SetPoint(framePoint, _G[slotFrameName], parentPoint, offsetX, 0)
        end
    end
    
    if (_G["InspectModelFrame"] ~= nil) then
        if (AverageLevelText == nil) then
            AverageLevelText = _G["InspectModelFrame"]:CreateFontString("TyAvgIlvl", "OVERLAY", "GameTooltipText")
        end
        
        if (addon.config.items.showAverage) then
            AverageLevelText:SetPoint("TOP", _G["InspectModelFrame"], "TOP", 0, -5)
            
            if (addon.config.items.fontOutline == 4) then
                AverageLevelText:SetShadowColor(0, 0, 0)
                AverageLevelText:SetShadowOffset(0, 0)
                AverageLevelText:SetShadowOffset(1, -1)
            end
            local avgLevelFont = AverageLevelText:GetFont()
            AverageLevelText:SetFont(avgLevelFont, addon.config.items.fontSize,
                fontMap[addon.config.items.fontOutline])
            
            -- Use cached average level/color computed by updateAllSlots when available
            local averageLevel = addon._cachedAverageLevel or C_PaperDollInfo.GetInspectItemLevel(unit)
            local rarityColor = addon._cachedAverageHex or computeAverageQualityHex(unit) or "FFFFFFFF"
            -- Only show a positive average; avoid showing 0 which can occur during
            -- transitional states of the inspect APIs. If no positive value is
            -- available, clear and hide the field (previous behavior looked
            -- better than showing '0').
            if averageLevel and averageLevel > 0 then
                AverageLevelText:SetText("|c" .. rarityColor .. averageLevel .. "|r")
                AverageLevelText:Show()
            else
                AverageLevelText:SetText("")
                AverageLevelText:Hide()
            end
        else
            AverageLevelText:SetText("")
            AverageLevelText:Hide()
        end
    end
    
    if (EnchantText == nil) then
        EnchantText = _G[slotFrameName]:CreateFontString(slotFrameName .. "TyEnchant", "ARTWORK", "GameTooltipText")
        EnchantText:SetPoint(framePoint, _G[slotFrameName], parentPoint, offsetX, -12)
        -- allow long enchant text to wrap onto multiple lines
        EnchantText:SetWordWrap(true)
        EnchantText:SetWidth(140)
        -- justify text depending on which side the slot is on so it grows away from the icon
        if rightSide then
            EnchantText:SetJustifyH("RIGHT")
        else
            EnchantText:SetJustifyH("LEFT")
        end
    end
    
    -- set up gems
    local ilvlSpacingX = 27 * (addon.config.items.fontSize / 12);
    for i = 1, 3 do
        if (GemFrames[i] == nil) then
            GemFrames[i] = CreateFrame("Button", slotFrameName .. "TyGem" .. i, _G[slotFrameName],
            "UIPanelButtonTemplate")
            GemFrames[i]:SetSize(14, 14)
        end
        if (slot == 16 or slot == 17) then
            GemFrames[i]:SetPoint("BOTTOM", _G[slotFrameName], "TOP", -14 + (15 * (i - 1)), 18)
        else
            local gemOffsetX = rightSide and offsetX - (15 * (i - 1)) or offsetX + (15 * (i - 1))
            if (addon.config.items.enabled) then
                gemOffsetX = rightSide and gemOffsetX - ilvlSpacingX or gemOffsetX + ilvlSpacingX
            end
            GemFrames[i]:SetPoint(framePoint, _G[slotFrameName], parentPoint, gemOffsetX, 0)
        end
    end
    
    -- clear all if no item equipped
    if (itemLink == nil or itemLink == "") then
        LevelText:SetText("")
        EnchantText:SetText("")
        for i = 1, 3 do
            GemFrames[i]:Hide()
        end
        return
    end
    
    -- get item information
    local _, _, itemQuality, itemLevel = C_Item.GetItemInfo(itemLink)
    if (itemLevel == nil) then
        local itemId = C_Item.GetItemInfoInstant(itemLink)
        addon.itemInfoRequested[itemId] = { unit = unit, slot = slot }
        return
    end
    
    -- need to parse tooltip for full item info
    local ItemTooltip = _G["TyScanningTooltip"] or
    CreateFrame("GameTooltip", "TyScanningTooltip", WorldFrame, "GameTooltipTemplate") --[[@as GameTooltip]]
    ItemTooltip:SetOwner(WorldFrame, "ANCHOR_NONE");
    ItemTooltip:ClearLines()
    ItemTooltip:SetHyperlink(itemLink)
    local enchant = ""
    for i = 1, ItemTooltip:NumLines() do
        local foundEnchant = _G["TyScanningTooltipTextLeft" .. i]:GetText():match(ENCHANTED_TOOLTIP_LINE:gsub("%%s",
        "(.+)"))
        if foundEnchant then
            enchant = foundEnchant
        end
        
        local foundLevel = _G["TyScanningTooltipTextLeft" .. i]:GetText():match(ITEM_LEVEL:gsub("%%d", "(%%d+)"))
        if foundLevel then
            itemLevel = foundLevel
        end
    end
    
    -- set iLvl
    if (addon.config.items.enabled) then
        local levelFont = LevelText:GetFont()
        LevelText:SetFont(levelFont, addon.config.items.fontSize, fontMap[addon.config.items.fontOutline])
        if (addon.config.items.fontOutline == 4) then
            LevelText:SetShadowColor(0, 0, 0)
            LevelText:SetShadowOffset(0, 0)
            LevelText:SetShadowOffset(1, -1)
        end
        
        local colorInfo = ColorManager.GetColorDataForItemQuality(itemQuality)
        LevelText:SetText(colorInfo.hex .. itemLevel .. "|r")
        LevelText:Show()
    else
        LevelText:Hide()
    end
    
    -- set enchant
    if (addon.config.enchants.enabled) then
        if (addon.config.enchants.fontOutline == 4) then
            EnchantText:SetShadowColor(0, 0, 0)
            EnchantText:SetShadowOffset(0, 0)
            EnchantText:SetShadowOffset(1, -1)
        end
        local enchantFont = EnchantText:GetFont()
        EnchantText:SetFont(enchantFont, addon.config.enchants.fontSize, fontMap
            [addon.config.enchants.fontOutline])
        
        local color = "FF00FF00"
        
        -- find and strip existing color
        local newColor, coloredEnchant = enchant:match("|c(%x%x%x%x%x%x%x%x)(.+)|r") -- hex codes
        if (coloredEnchant == nil) then
            newColor, coloredEnchant = enchant:match("|c(n.+:)(.+)|r")               -- named color
        end
        if (coloredEnchant) then
            color = newColor
            enchant = coloredEnchant
        end
        
        -- need to check for quality symbols
        local qualityStart = string.find(enchant, "|A")
        local quality = ""
        if (qualityStart) then
            quality = string.sub(enchant, qualityStart)
            enchant = string.sub(enchant, 1, qualityStart - 1)
        end
        
        local maxLength = addon.config.enchants.maxLength
        if (maxLength > 0 and strlen(enchant) > maxLength) then
            enchant = format("%." .. maxLength .. "s", enchant) .. "..."
        end
        if (addon.config.enchants.showQuality) then
            enchant = enchant .. quality;
        end
        EnchantText:SetText("|c" .. color .. enchant .. "|r")
        EnchantText:Show()
    else
        EnchantText:Hide()
    end
    
    -- set gems
    local gemCount = C_Item.GetItemNumSockets(itemLink)
    for i = 1, 3 do
        if (addon.config.gems.enabled and i <= gemCount) then
            local gemId = C_Item.GetItemGemID(itemLink, i)
            if (gemId ~= nil) then
                local gem = Item:CreateFromItemID(gemId);
                
                -- Gem may not be loaded even if the item is, load async
                gem:ContinueOnItemLoad(function()
                        local gemIcon = C_Item.GetItemIconByID(gemId);
                        local _, gemLink = C_Item.GetItemInfo(gemId)
                        GemFrames[i]:SetNormalTexture(gemIcon)
                        GemFrames[i]:SetScript("OnEnter", function()
                                GameTooltip:SetOwner(GemFrames[i], "ANCHOR_CURSOR")
                                GameTooltip:SetHyperlink(gemLink)
                                GameTooltip:Show()
                        end);
                        GemFrames[i]:SetScript("OnLeave", function()
                                GameTooltip:Hide()
                        end)
                        GemFrames[i]:Show()
                end)
            else
                GemFrames[i]:SetNormalTexture("Interface\\ITEMSOCKETINGFRAME\\UI-EmptySocket-Prismatic.blp")
                GemFrames[i]:SetScript("OnEnter", nil)
                GemFrames[i]:SetScript("OnLeave", nil)
                GemFrames[i]:Show()
            end
        else
            GemFrames[i]:Hide()
        end
    end
end

-- loop all slots
addon.updateAllSlots = function(unit)
    -- compute aggregate values once to avoid repeating work per-slot
    addon._cachedAverageHex = nil
    addon._cachedAverageLevel = nil
    -- compute the average level and color for the inspected unit
    if _G.InspectModelFrame then
        local ok, avg = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
        if ok and avg then
            addon._cachedAverageLevel = avg
            addon._cachedAverageHex = computeAverageQualityHex(unit)
        end
    end

    for slot = 1, 19 do
        addon.updateSlot(unit, slot)
    end
end

-- instead of using triggers, just run when the character frame is shown
local paperDollFrame = _G["PaperDollFrame"]
paperDollFrame:HookScript("OnShow", function(self)
        if (not addon.characterOpen) then -- OnShow can be called multiple times?
            addon.updateAllSlots("player")
        end
        
        addon.characterOpen = true
end)

paperDollFrame:HookScript("OnHide", function(self)
        addon.characterOpen = false
end)

-- inspect is delay loaded, but we can hook functions instead
local inspectHooked = false;
hooksecurefunc("InspectFrame_LoadUI", function()
        if (not inspectHooked) then
            local inspectPaperDollFrame = _G["InspectPaperDollFrame"]
            inspectPaperDollFrame:HookScript("OnHide", function(self)
                    addon.inspecting = false
            end)
            inspectHooked = true
        end
        
        addon.inspecting = true;
end)

------------------------------------------------
-- ========== EVENT HANDLING ===================
------------------------------------------------

local frame = CreateFrame("Frame")

frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("INSPECT_READY")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if (event == "ADDON_LOADED" and arg1 == "TyItemLevel") then
        if addon.LoadSavedVariables then
            addon.LoadSavedVariables()
        end
        return
    end

    -- no legacy fallback handling required

    if (event == "PLAYER_EQUIPMENT_CHANGED" and addon.characterOpen and arg1 ~= nil) then
        addon.updateSlot("player", arg1)

    elseif (event == "INSPECT_READY" and addon.inspecting and arg1 == addon.lastInspectGuid) then
        addon.updateAllSlots(addon.lastInspectUnit)

    elseif (event == "GET_ITEM_INFO_RECEIVED" and addon.itemInfoRequested[arg1] ~= nil) then
        local request = addon.itemInfoRequested[arg1]
        addon.itemInfoRequested[arg1] = nil
        if (addon.characterOpen) then
            addon.updateSlot(request.unit, request.slot)
        end

    elseif (event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" and addon.characterOpen) then
        addon.updateAllSlots(arg1)
    end
end)
