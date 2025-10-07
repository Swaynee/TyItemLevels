-- TyItemLevel_Config.lua
-- Options panel and SavedVariables handling moved here to separate UI from logic
-- The config file may be loaded before the main file in some environments; guard against TyIL being nil.
local _G = _G
local function getAddon()
    if TyIL then return TyIL end
    -- create a temporary table to avoid runtime errors; the real addon table will overwrite functions later
    if not _G.__TyItemLevelTemp then _G.__TyItemLevelTemp = {} end
    return _G.__TyItemLevelTemp
end
-- don't capture addon at load-time; retrieve when needed to avoid nil during load ordering

-- Merge defaults helper (copied from main)
local function MergeDefaults(t, d)
    if type(d) ~= "table" then return end
    if type(t) ~= "table" then t = {} end
    for k, v in pairs(d) do
        if type(v) == "table" then
            if type(t[k]) ~= "table" then t[k] = {} end
            MergeDefaults(t[k], v)
        else
            if t[k] == nil then t[k] = v end
        end
    end
    return t
end

-- UI helpers
local function MakeCheckbox(parent, globalName, label, category, key, x, y)
    local a = getAddon()
    local cb = CreateFrame("CheckButton", globalName, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if _G[globalName .. "Text"] then _G[globalName .. "Text"]:SetText(label) end
    local cur = a.config and a.config[category] and a.config[category][key]
    if cur ~= nil and cb.SetChecked then cb:SetChecked(cur) end
    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        local addon = getAddon()
        if addon.config and addon.config[category] then addon.config[category][key] = checked end
        if TyItemLevelDB and TyItemLevelDB[category] then TyItemLevelDB[category][key] = checked end
    end)
    return cb
end

local function MakeSlider(parent, name, label, category, key, x, y, minV, maxV, step)
    local a = getAddon()
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    slider:SetMinMaxValues(minV, maxV)
    local stepVal = step or 1
    slider:SetValueStep(stepVal)
    slider:SetObeyStepOnDrag(true)
    if _G[name .. "Text"] then _G[name .. "Text"]:SetText(label) end
    -- clamp initial value
    local init = a.config and a.config[category] and a.config[category][key] or minV
    if init < minV then init = minV end
    if init > maxV then init = maxV end
    slider:SetValue(init)
    slider:SetScript("OnValueChanged", function(self, val)
        local v = math.floor((val + stepVal / 2) / stepVal) * stepVal
        if v < minV then v = minV end
        if v > maxV then v = maxV end
        if TyItemLevelDB and TyItemLevelDB[category] then TyItemLevelDB[category][key] = v end
        local addon = getAddon()
        if addon.config and addon.config[category] then addon.config[category][key] = v end
    end)
    return slider
end

local function MakeFontOutlineDropdown(parent, name, label, category, key, x, y)
    local a = getAddon()
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    if _G[name .. "Text"] then _G[name .. "Text"]:SetText(label) end
    local options = {"None", "Outline", "Thick Outline", "Shadow"}
    UIDropDownMenu_Initialize(dd, function(self, level, menuList)
        for i = 1, #options do
            local info = UIDropDownMenu_CreateInfo()
            info.text = options[i]
            info.func = function()
                local addon = getAddon()
                if addon.config and addon.config[category] then addon.config[category][key] = i end
                if TyItemLevelDB and TyItemLevelDB[category] then TyItemLevelDB[category][key] = i end
                UIDropDownMenu_SetSelectedValue(dd, i)
            end
            info.value = i
            info.checked = (UIDropDownMenu_GetSelectedValue(self) == i)
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetWidth(dd, 140)
    if a.config and a.config[category] and a.config[category][key] then
        UIDropDownMenu_SetSelectedValue(dd, a.config[category][key])
    end
    return dd
end

-- Create and register the options panel
local function CreateOptionsPanel()
    local addon = getAddon()
    if _G["TyItemLevelOptionsPanel"] then return _G["TyItemLevelOptionsPanel"] end
    local panel = CreateFrame("Frame", "TyItemLevelOptionsPanel", nil)
    panel.name = "TyItemLevel"
    if addon then addon.optionsPanel = panel end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("TyItemLevel Settings")
    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetJustifyH("LEFT")
    desc:SetText("Choose which information should be displayed and saved.")

    local leftX = 16
    local rightX = 260
    local curY = -70

    -- Items
    local itemsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    itemsHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", leftX, curY + 8)
    itemsHeader:SetText("Item levels")
    curY = curY - 26
    MakeCheckbox(panel, "TyItemLevel_ItemsEnabledCB", "Enabled", "items", "enabled", leftX, curY)
    MakeCheckbox(panel, "TyItemLevel_ItemsShowAvgCB", "Show average inspect level", "items", "showAverage", rightX, curY)
    curY = curY - 58
    MakeSlider(panel, "TyItemLevel_ItemsFontSize", "Font size", "items", "fontSize", leftX + 4, curY, 10, 20, 2)
    MakeFontOutlineDropdown(panel, "TyItemLevel_ItemsFontOutline", "Font outline", "items", "fontOutline", rightX, curY)
    curY = curY - 74

    -- Enchants
    local enchHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    enchHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", leftX, curY + 8)
    enchHeader:SetText("Enchants")
    curY = curY - 26
    MakeCheckbox(panel, "TyItemLevel_EnchantsEnabledCB", "Enabled", "enchants", "enabled", leftX, curY)
    MakeCheckbox(panel, "TyItemLevel_EnchantsShowQualityCB", "Show quality", "enchants", "showQuality", rightX, curY)
    curY = curY - 58
    MakeSlider(panel, "TyItemLevel_EnchantsFontSize", "Font size", "enchants", "fontSize", leftX + 4, curY, 10, 20, 2)
    MakeFontOutlineDropdown(panel, "TyItemLevel_EnchantsFontOutline", "Font outline", "enchants", "fontOutline", rightX, curY)
    curY = curY - 54
    MakeSlider(panel, "TyItemLevel_EnchantsMaxLength", "Max display length", "enchants", "maxLength", leftX + 4, curY, 0, 100, 1)
    curY = curY - 74

    -- Gems
    local gemsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    gemsHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", leftX, curY + 8)
    gemsHeader:SetText("Gems")
    curY = curY - 26
    MakeCheckbox(panel, "TyItemLevel_GemsEnabledCB", "Enabled", "gems", "enabled", leftX, curY)
    curY = curY - 26

    -- register with Settings API if available
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local title = (addon and addon.title) or "TyItemLevel"
        local id = (addon and addon.name) or "TyItemLevel"
        local category, layout = Settings.RegisterCanvasLayoutCategory(panel, title)
        Settings.RegisterAddOnCategory(category)
        category.ID = id
        layout:AddAnchorPoint("TOPLEFT", 10, -10)
        layout:AddAnchorPoint("BOTTOMRIGHT", -10, 10)
        if addon then addon.panelRegistered = true end
    else
        if addon then addon.panelRegistered = false end
    end

    return panel
end

-- Load saved variables and sync UI
local function LoadSavedVariables()
    local addon = getAddon()
    if TyItemLevelDB == nil then TyItemLevelDB = {} end
    if addon and addon.config then
        MergeDefaults(TyItemLevelDB, addon.config)
        if TyItemLevelDB.items then for k, v in pairs(TyItemLevelDB.items) do addon.config.items[k] = v end end
        if TyItemLevelDB.enchants then for k, v in pairs(TyItemLevelDB.enchants) do addon.config.enchants[k] = v end end
        if TyItemLevelDB.gems then for k, v in pairs(TyItemLevelDB.gems) do addon.config.gems[k] = v end end
    else
        -- nothing to load into yet; MergeDefaults will be rerun when addon initializes
        return
    end

    CreateOptionsPanel()
    -- sync
    if _G["TyItemLevel_ItemsEnabledCB"] then _G["TyItemLevel_ItemsEnabledCB"]:SetChecked(addon.config.items.enabled) end
    if _G["TyItemLevel_ItemsShowAvgCB"] then _G["TyItemLevel_ItemsShowAvgCB"]:SetChecked(addon.config.items.showAverage) end
    if _G["TyItemLevel_ItemsFontSize"] then _G["TyItemLevel_ItemsFontSize"]:SetValue(addon.config.items.fontSize) end
    if UIDropDownMenu_SetSelectedValue and _G["TyItemLevel_ItemsFontOutline"] then UIDropDownMenu_SetSelectedValue(_G["TyItemLevel_ItemsFontOutline"], addon.config.items.fontOutline) end

    if _G["TyItemLevel_EnchantsEnabledCB"] then _G["TyItemLevel_EnchantsEnabledCB"]:SetChecked(addon.config.enchants.enabled) end
    if _G["TyItemLevel_EnchantsShowQualityCB"] then _G["TyItemLevel_EnchantsShowQualityCB"]:SetChecked(addon.config.enchants.showQuality) end
    if _G["TyItemLevel_EnchantsMaxLength"] then _G["TyItemLevel_EnchantsMaxLength"]:SetValue(addon.config.enchants.maxLength) end
    if _G["TyItemLevel_EnchantsFontSize"] then _G["TyItemLevel_EnchantsFontSize"]:SetValue(addon.config.enchants.fontSize) end
    if UIDropDownMenu_SetSelectedValue and _G["TyItemLevel_EnchantsFontOutline"] then UIDropDownMenu_SetSelectedValue(_G["TyItemLevel_EnchantsFontOutline"], addon.config.enchants.fontOutline) end

    if _G["TyItemLevel_GemsEnabledCB"] then _G["TyItemLevel_GemsEnabledCB"]:SetChecked(addon.config.gems.enabled) end
end

local a = getAddon()
a.CreateOptionsPanel = CreateOptionsPanel
a.LoadSavedVariables = LoadSavedVariables
