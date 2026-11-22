-- AutoRank: real spells stay on your bars; when you learn a new rank, buttons that held your
-- previous top rank are swapped to it (waits until combat ends). Lower ranks you put on a
-- button stay.
--
--   /autorank                  status and commands
--   /autorank all              raise every unpinned button to the top rank now
--   /autorank off | on         stop / resume upgrading everywhere
--   /autorank pins             buttons kept at a low rank on purpose
--   /autorank unpin [slot]     let a pinned button (or all) upgrade again
--   /autorank stones off | on  stop / resume the Healthstone swap
--   /autorank unmacro [apply]  preview / do: bar macros that are just "/cast Spell" become
--                              the real spell (the macros themselves are kept)
--
-- Keeping a low rank: drag that rank from the spellbook onto the button. A rank you place
-- yourself is pinned to that button and never upgraded (until something else goes there).
--
-- Healthstones: any button holding a Healthstone is switched to the best one in your bags
-- (out of combat). With none in bags the button is left as it is.

AutoRankDB = AutoRankDB or {}
local pins = {}   -- slot -> spellID kept on purpose (AutoRankCharDB.pins once loaded)

local BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
local TYPE_SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
local PickupSpell = (C_Spell and C_Spell.PickupSpell) or _G.PickupSpell
local GetSpellName = (C_Spell and C_Spell.GetSpellName)
    or function(id) return (GetSpellInfo(id)) end
local GetSpellSubtext = (C_Spell and C_Spell.GetSpellSubtext) or _G.GetSpellSubtext
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local IsSecret = _G.issecretvalue or function() return false end
-- "Rank 3" on English clients; RANK is the client's own word for other languages
local RANK_PATTERNS = { "Rank (%d+)" }
if type(RANK) == "string" and RANK ~= "Rank" then
    RANK_PATTERNS[2] = RANK:gsub("%p", "%%%0") .. " (%d+)"
end

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff8788eeAutoRank|r: " .. msg) end

local function RankOf(subtext)
    if type(subtext) ~= "string" or IsSecret(subtext) then return nil end
    for _, p in ipairs(RANK_PATTERNS) do
        local n = tonumber(subtext:match(p))
        if n then return n end
    end
end

-- spell name -> { id = highest known rank's spellID, rank = n } (rank 0 for spells without
-- ranks). Cached until the spellbook changes: the action bar events ask often.
local knownCache
local function KnownSpells()
    if knownCache then return knownCache end
    local best, trailing, any = {}, 0, false
    for slot = 1, 2000 do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, BANK)
        if info and type(info.name) == "string" and not IsSecret(info.name) then
            trailing = 0
            local id = info.spellID or info.actionID
            local learned = (TYPE_SPELL == nil or info.itemType == TYPE_SPELL)
                and not info.isPassive
            if learned and type(id) == "number" and not IsSecret(id) then
                local r = RankOf(info.subName) or 0
                local cur = best[info.name]
                if not cur or r > cur.rank then best[info.name] = { id = id, rank = r } end
                any = true
            end
        else
            trailing = trailing + 1
            if trailing > 40 then break end
        end
    end
    -- an empty book is the client not ready yet: ask again next time
    if any then knownCache = best end
    return best
end

local busy = false
-- slot -> spell/item ID we put there ourselves (so its slot-changed event isn't a pin)
local placed = {}
-- Never runs while something is on the cursor: ClearCursor would drop what the player is
-- dragging, and PlaceAction would drop it on this button. A failed pickup aborts too, so
-- PlaceAction never sees anything but our own spell/item.
local function CursorBusy() return GetCursorInfo() ~= nil end
local function Place(slot, pickup, id)
    if type(slot) ~= "number" or slot < 1 or slot > 180 or slot % 1 ~= 0 then return false end
    if CursorBusy() then return false end
    busy = true
    pickup(id)
    if not CursorBusy() then
        busy = false
        Print(("couldn't pick up %s for slot %d, left it alone"):format(tostring(id), slot))
        return false
    end
    placed[slot] = id
    PlaceAction(slot)
    ClearCursor()
    busy = false
    local _, got = GetActionInfo(slot)
    if got ~= id then
        Print(("slot %d: wrote %s but it holds %s"):format(slot, tostring(id), tostring(got)))
    end
    return true
end
local function PlaceSpell(slot, id) return Place(slot, PickupSpell, id) end

-- weakest to strongest; each Improved Healthstone talent rank is its own item
local STONES = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009,
    5510, 19010, 19011, 9421, 19012, 19013 }
local IS_STONE = {}
for _, id in ipairs(STONES) do IS_STONE[id] = true end
local GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
local PickupItem = (C_Item and C_Item.PickupItem) or _G.PickupItem

local stonesPending = false
local function Healthstones()
    if AutoRankDB.off or AutoRankDB.stonesOff then return end
    if InCombatLockdown() then stonesPending = true; return end
    if CursorBusy() then C_Timer.After(1, Healthstones); return end
    stonesPending = false
    local best
    for i = #STONES, 1, -1 do
        if (GetItemCount(STONES[i]) or 0) > 0 then best = STONES[i]; break end
    end
    if not best then return end
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        if kind == "item" and not IsSecret(id) and IS_STONE[id] and id ~= best then
            if Place(slot, PickupItem, best) then
                local name = GetItemInfo(best)
                Print(("Healthstone on slot %d -> %s"):format(slot, name or best))
            end
        end
    end
end

-- Only move a button up when a NEW rank is learned, and only if that button held the
-- previous top rank. A lower rank you chose (e.g. Life Tap rank 1) is never touched, even
-- when its pin was missed. tops = name -> highest rank already seen (per character).
local tops = {}
local pending = false
local function Upgrade(full)
    if AutoRankDB.off then return end
    if InCombatLockdown() then pending = true; return end
    if CursorBusy() then C_Timer.After(1, function() Upgrade(full) end); return end
    pending = false
    local known = KnownSpells()
    local n = 0
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and type(id) == "number" and not IsSecret(id) then
            local rank = RankOf(GetSpellSubtext(id))
            local name = rank and GetSpellName(id)
            local top = name and known[name]
            local prev = top and (tops[name] or top.rank)
            local due = top and top.rank > rank
                and (full or (top.rank > prev and rank >= prev))
            if due and top.id ~= id and pins[slot] ~= id then
                if PlaceSpell(slot, top.id) then
                    n = n + 1
                    Print(("%s: rank %d -> rank %d (slot %d)"):format(name, rank, top.rank, slot))
                end
            end
        end
    end
    for name, v in pairs(known) do
        if v.rank > 0 and v.rank > (tops[name] or 0) then tops[name] = v.rank end
    end
    if full and n == 0 then
        Print("every ranked spell on your bars is already the highest rank you know"
            .. " (pinned ones left alone).")
    end
end

-- "/cast X" (optionally with #showtooltip), nothing else
local function CastOnly(body)
    local lines = {}
    for line in (body or ""):gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and not line:lower():find("^#showtooltip") then
            lines[#lines + 1] = line
        end
    end
    if #lines ~= 1 then return nil end
    local spell = lines[1]:match("^/[Cc][Aa][Ss][Tt]%s+(.+)$")
    -- conditionals or several spells: leave it
    if not spell or spell:find("[%[;,]") then return nil end
    return spell
end

-- The macro index in a slot. For a macro that casts a spell this client returns the spell's
-- ID instead, so (as Myslot does) pick the button up, read the cursor and put it back.
local function MacroIndexAt(slot)
    local kind, idx, sub = GetActionInfo(slot)
    if kind ~= "macro" then return nil end
    if not sub or sub == "" then return idx end
    if CursorBusy() then return nil end
    busy = true
    PickupAction(slot)
    local cursorType, macroIndex = GetCursorInfo()
    if cursorType then PlaceAction(slot) end
    ClearCursor()
    busy = false
    if GetActionInfo(slot) ~= "macro" then
        Print(("slot %d: macro didn't go back, check this button"):format(slot))
    end
    return cursorType == "macro" and macroIndex or nil
end

local function Unmacro(apply)
    if InCombatLockdown() then Print("not in combat."); return end
    local known = KnownSpells()
    local lower = {}
    for name, v in pairs(known) do lower[name:lower()] = { name = name, id = v.id } end
    local n = 0
    for slot = 1, 180 do
        local idx = MacroIndexAt(slot)
        if idx then
            local mname, _, body = GetMacroInfo(idx)
            local spell = CastOnly(body)
            local hit = spell and lower[spell:lower()]
            if hit and (not apply or PlaceSpell(slot, hit.id)) then
                n = n + 1
                Print(("slot %d: macro '%s' -> %s%s"):format(slot, mname or "?", hit.name,
                    apply and "" or " (preview)"))
            end
        end
    end
    if n == 0 then
        Print("no plain /cast macros on your bars.")
    elseif not apply then
        Print("type /autorank unmacro apply to swap them. The macros themselves are kept.")
    end
end

local f = CreateFrame("Frame")
local queued = false
local function Queue()
    if busy or queued then return end
    queued = true
    C_Timer.After(0.5, function() queued = false; Upgrade(false); Healthstones() end)
end
local stonesQueued = false
local function QueueStones()
    if stonesQueued then return end
    stonesQueued = true
    C_Timer.After(0.5, function() stonesQueued = false; Healthstones() end)
end
-- A ranked spell that you put on a button yourself, below your highest rank, is pinned
-- there. Ignored for the first seconds after a loading screen, when the game fills every
-- button.
local watching = false
local function SlotChanged(slot)
    if not watching or busy or not slot or slot < 1 then return end
    local kind, id = GetActionInfo(slot)
    if placed[slot] then
        local ours = placed[slot] == id
        placed[slot] = nil
        if ours then return end
    end
    if kind ~= "spell" or type(id) ~= "number" or IsSecret(id) then
        if pins[slot] then pins[slot] = nil end
        return
    end
    local rank = RankOf(GetSpellSubtext(id))
    local name = rank and GetSpellName(id)
    local top = name and KnownSpells()[name]
    if top and top.rank > rank then
        if pins[slot] ~= id then
            pins[slot] = id
            Print(("keeping %s rank %d on this button (slot %d). /autorank unpin %d to undo.")
                :format(name, rank, slot, slot))
        end
    elseif pins[slot] then
        pins[slot] = nil
    end
end

local SPELLBOOK_EVENTS = { SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true,
    LEARNED_SPELL_IN_TAB = true, PLAYER_ENTERING_WORLD = true }

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
-- each exists on some clients only
pcall(f.RegisterEvent, f, "LEARNED_SPELL_IN_SKILL_LINE")
pcall(f.RegisterEvent, f, "LEARNED_SPELL_IN_TAB")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == "AutoRank" then
            AutoRankCharDB = AutoRankCharDB or {}
            AutoRankCharDB.pins = AutoRankCharDB.pins or {}
            pins = AutoRankCharDB.pins
            AutoRankCharDB.tops = AutoRankCharDB.tops or {}
            tops = AutoRankCharDB.tops
            f:UnregisterEvent("ADDON_LOADED")
        end
        return
    end
    if SPELLBOOK_EVENTS[event] then knownCache = nil end
    if event == "ACTIONBAR_SLOT_CHANGED" then SlotChanged(arg); return end
    if event == "BAG_UPDATE_DELAYED" then QueueStones(); return end
    if event == "PLAYER_REGEN_ENABLED" and stonesPending and not pending then
        QueueStones()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        watching = false
        C_Timer.After(5, function() watching = true end)
    end
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    Queue()
end)

local function Debug()
    if InCombatLockdown() then Print("not in combat."); return end
    local n = 0
    for _ in pairs(KnownSpells()) do n = n + 1 end
    Print(("spellbook: %d known spells"):format(n))
    for slot = 1, 180 do
        local kind, id, sub = GetActionInfo(slot)
        if kind == "macro" then
            local idx = MacroIndexAt(slot)
            local mname, _, body = GetMacroInfo(idx or 0)
            Print(("slot %d: macro id=%s sub=%s -> index %s '%s' cast=%s"):format(slot,
                tostring(id), tostring(sub), tostring(idx), tostring(mname),
                tostring(CastOnly(body))))
        end
    end
end

local function Help()
    Print(AutoRankDB.off and "off (/autorank on to resume)."
        or "on: when you learn a new rank, buttons holding your previous top rank move up."
        .. " Lower ranks you chose stay.")
    Print("Healthstone swap: " .. (AutoRankDB.stonesOff and "off" or "on") .. ".")
    Print("/autorank off | on | all (raise every unpinned button now) | pins | unpin [slot]"
        .. " | stones off | stones on | unmacro [apply]")
end

SLASH_AUTORANK1 = "/autorank"
SlashCmdList.AUTORANK = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "off" then
        AutoRankDB.off = true
        Print("off: ranks on your bars are left alone.")
    elseif msg == "on" then
        AutoRankDB.off = nil
        Print("on.")
        Upgrade(false)
    elseif msg == "all" then
        Upgrade(true)
    elseif msg == "stones off" then
        AutoRankDB.stonesOff = true
        Print("Healthstone swap off.")
    elseif msg == "stones on" then
        AutoRankDB.stonesOff = nil
        Print("Healthstone swap on.")
        Healthstones()
    elseif msg == "pins" then
        local any = false
        for slot, id in pairs(pins) do
            any = true
            Print(("slot %d: %s %s"):format(slot, GetSpellName(id) or "?",
                GetSpellSubtext(id) or ""))
        end
        if not any then
            Print("no pinned buttons. Drag a low rank from the spellbook onto a button to"
                .. " keep it.")
        end
    elseif msg:find("^unpin") then
        local slot = tonumber(msg:match("(%d+)"))
        if slot then pins[slot] = nil else wipe(pins) end
        Print(slot and ("slot %d will upgrade again."):format(slot) or "all pins removed.")
        Upgrade(false)
    elseif msg == "debug" then
        Debug()
    elseif msg:find("^unmacro") then
        Unmacro(msg:find("apply") ~= nil)
    else
        Help()
    end
end
