-- Options panel (Esc > Options > AddOns > AutoRank, or /autorank). Settings write
-- straight into AutoRankDB.
local _, ns = ...

local category

local function Header(layout, title, tip)
    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title, tip))
    end
end

-- Toggling on should swap bars now (after combat), not wait for the next bag change
-- (read the table: callback arguments differ between client builds)
local function OnChange(variable, tbl, key, fn)
    if Settings.SetOnValueChangedCallback then
        Settings.SetOnValueChangedCallback(variable, function() fn(tbl[key]) end)
    end
end

local function Register()
    if category or not (Settings and Settings.RegisterVerticalLayoutCategory) then
        return
    end
    local db = ns.db()
    db.conjured = db.conjured or {}
    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("AutoRank")

    local on = Settings.RegisterAddOnSetting(category, "AUTORANK_ON", "on", db,
        Settings.VarType.Boolean, "AutoRank on", true)
    Settings.CreateCheckbox(category, on, "When you learn a new rank, buttons holding "
        .. "your previous top rank move up to it, and conjured item buttons get your best "
        .. "one. Off: your bars are left alone. /autorank on||off does the same.")
    OnChange("AUTORANK_ON", db, "on", ns.SetOn)

    Header(layout, "Conjured items", "A button holding any one of these gets the best "
        .. "you have in your bags, out of combat. /autorank <item> on||off does the same.")
    for _, fam in ipairs(ns.FAMILIES) do
        local variable = "AUTORANK_CONJURED_" .. fam.key:upper()
        local setting = Settings.RegisterAddOnSetting(category, variable, fam.key,
            db.conjured, Settings.VarType.Boolean, fam.name, true)
        Settings.CreateCheckbox(category, setting, ("A button holding any %s is switched "
            .. "to the best one in your bags that you can use. With none in bags it is left "
            .. "as it is. /autorank %s on||off"):format(fam.name:lower(), fam.key))
        OnChange(variable, db.conjured, fam.key, function(value)
            ns.SetConjured({ fam.key }, value)
        end)
    end

    Header(layout, "Pinned buttons", "Drag a low rank from the spellbook onto a button "
        .. "to keep it there. /autorank pins lists them.")
    if layout and CreateSettingsButtonInitializer then
        local function Unpin()
            local n = ns.PinCount()
            ns.Print(("%d pin%s removed."):format(n, n == 1 and "" or "s"))
            ns.UnpinAll()
        end
        layout:AddInitializer(CreateSettingsButtonInitializer("All pins", "Unpin all",
            Unpin, "Let every button you kept at a low rank upgrade again. /autorank unpin",
            true))
    end
    Settings.RegisterAddOnCategory(category)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local ok, err = pcall(Register)
    if not ok then geterrorhandler()(err) end
end)

function ns.OpenSettings()
    if not category then return false end
    Settings.OpenToCategory(category:GetID())
    return true
end

function AutoRank_OnAddonCompartmentClick()
    if not ns.OpenSettings() then ns.Help() end
end
