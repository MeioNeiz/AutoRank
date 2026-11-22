-- AutoRank: real spells stay on your bars; when you learn a new rank, buttons that held your
-- previous top rank are swapped to it. A spell that replaces another (Demon Skin -> Demon
-- Armor, Lesser Heal -> Heal) counts as its next rank. Lower ranks you put on a button stay.
-- A button holding a conjured item (Healthstone, Soulstone, mana gem, conjured water...)
-- gets the best of that kind in your bags. Every bar change waits until combat ends.
--
-- Keeping a low rank: drag that rank from the spellbook onto the button. A rank you place
-- yourself is pinned to that button and never upgraded (until something else goes there).
-- /autorank help lists the commands; Esc > Options > AddOns > AutoRank has the settings.
local _, ns = ...

AutoRankDB = AutoRankDB or {}
local db = AutoRankDB
local pins = {}   -- slot -> spellID kept on purpose (AutoRankCharDB.pins once loaded)

local BANKS = Enum and Enum.SpellBookSpellBank
local BANK = (BANKS and BANKS.Player) or 0
local PET_BANK = (BANKS and BANKS.Pet) or 1
local TYPE_SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
local TYPE_PET = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.PetAction
local PickupSpell = (C_Spell and C_Spell.PickupSpell) or _G.PickupSpell
local GetSpellName = C_Spell.GetSpellName
local GetSpellSubtext = (C_Spell and C_Spell.GetSpellSubtext) or _G.GetSpellSubtext
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
local PickupItem = (C_Item and C_Item.PickupItem) or _G.PickupItem
local IsSecret = _G.issecretvalue or function() return false end
-- "Rank 3" on English clients; RANK is the client's own word for other languages
local RANK_PATTERNS = { "Rank (%d+)" }
if type(RANK) == "string" and RANK ~= "Rank" then
    RANK_PATTERNS[2] = RANK:gsub("%p", "%%%0") .. " (%d+)"
end

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cffb090ffAutoRank:|r " .. msg) end
local function OnOff(v) return v and "|cff80ff80on|r" or "|cffff8080off|r" end
local function Cmd(s) return "|cffffd100" .. s .. "|r" end
local function Muted(s) return "|cff999999" .. s .. "|r" end

local function RankOf(subtext)
    if type(subtext) ~= "string" or IsSecret(subtext) then return nil end
    for _, p in ipairs(RANK_PATTERNS) do
        local n = tonumber(subtext:match(p))
        if n then return n end
    end
end

-- Spells a later one replaces, oldest first, by any rank's ID (names come from the client,
-- so any language works). A later spell outranks every rank of an earlier one. Conjure
-- Mana gems aren't chained: a mage keeps a button per gem.
local CHAIN_IDS = {
    { 687, 706 },             -- Demon Skin, Demon Armor
    { 168, 7302 },            -- Frost Armor, Ice Armor
    { 2050, 2054, 2060 },     -- Lesser Heal, Heal, Greater Heal
    { 5487, 9634 },           -- Bear Form, Dire Bear Form
    { 5784, 23161 },          -- Summon Felsteed, Summon Dreadsteed
    { 13819, 23214 },         -- Summon Warhorse, Summon Charger
}
local chainOf
-- spell name -> { key = the chain's first ID, index = place in the chain }
local function Chains()
    if chainOf then return chainOf end
    local t, all = {}, true
    for _, ids in ipairs(CHAIN_IDS) do
        for i, id in ipairs(ids) do
            local name = GetSpellName(id)
            if type(name) == "string" and not IsSecret(name) then
                t[name] = { key = ids[1], index = i }
            else
                all = false
            end
        end
    end
    if all then chainOf = t end
    return t
end
-- What a spell competes with for a button: its chain's key (or its own name) and its rank
-- within that line
local function LineOf(name, rank)
    local c = Chains()[name]
    if c then return c.key, (c.index - 1) * 100 + rank end
    return name, rank
end
-- A bar spell's line, effective rank, name and own rank; nil for an unranked spell outside
-- every chain
local function BarLine(id)
    local name = GetSpellName(id)
    if type(name) ~= "string" or IsSecret(name) then return end
    local rank = RankOf(GetSpellSubtext(id))
    if not rank and not Chains()[name] then return end
    local key, eff = LineOf(name, rank or 0)
    return key, eff, name, rank or 0
end
local function Describe(name, rank)
    return rank > 0 and ("%s rank %d"):format(name, rank) or name
end

-- known: spell name -> { id = highest known rank's spellID, rank = n, slot, bank } (rank 0
-- for spells without ranks). lines: LineOf key -> the best of that line, the same entry
-- plus name and eff. Pet spells only while that pet is out. Cached until the spellbook
-- changes: the action bar events ask often.
local knownCache, linesCache
-- The book's real length, so a scan never walks past it; nil if this client can't say
local function BookEnd(bank)
    local book = C_SpellBook
    if bank == PET_BANK then
        local n = book.HasPetSpells and book.HasPetSpells()
        return type(n) == "number" and n > 0 and n or nil
    end
    if not (book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo) then return end
    local last = 0
    for i = 1, book.GetNumSpellBookSkillLines() or 0 do
        local line = book.GetSpellBookSkillLineInfo(i)
        if line and line.itemIndexOffset and line.numSpellBookItems then
            last = math.max(last, line.itemIndexOffset + line.numSpellBookItems)
        end
    end
    return last > 0 and last or nil
end
local function ScanBank(bank, best)
    local trailing, any = 0, false
    for slot = 1, BookEnd(bank) or 2000 do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
        if info and type(info.name) == "string" and not IsSecret(info.name) then
            trailing = 0
            local pet = bank == PET_BANK
            -- a pet book's actionID is a pet action, not a spell: spellID only
            local id = info.spellID or (not pet and info.actionID or nil)
            local learned = not info.isPassive and (TYPE_SPELL == nil
                or info.itemType == TYPE_SPELL or (pet and info.itemType == TYPE_PET))
            if learned and type(id) == "number" and not IsSecret(id) then
                local r = RankOf(info.subName) or 0
                local cur = best[info.name]
                if not cur or r > cur.rank then
                    best[info.name] = { id = id, rank = r, slot = slot, bank = bank }
                end
                any = true
            end
        else
            trailing = trailing + 1
            if trailing > 40 then break end
        end
    end
    return any
end
local function KnownSpells()
    if knownCache then return knownCache, linesCache end
    local best, lines = {}, {}
    local any = ScanBank(BANK, best)
    if UnitExists("pet") then ScanBank(PET_BANK, best) end
    for name, v in pairs(best) do
        local key, eff = LineOf(name, v.rank)
        v.name, v.eff = name, eff
        if not lines[key] or eff > lines[key].eff then lines[key] = v end
    end
    -- an empty book is the client not ready yet: ask again next time
    if any then knownCache, linesCache = best, lines end
    return best, lines
end

local busy = false
-- slot -> spell/item ID we put there ourselves (so its slot-changed event isn't a pin)
local placed = {}
-- Never runs while something is on the cursor: ClearCursor would drop what the player is
-- dragging, and PlaceAction would drop it on this button. A failed pickup aborts too, so
-- PlaceAction never sees anything but our own spell/item. Every caller already waits for
-- combat to end; the check here keeps any new caller from writing a bar in combat.
local function CursorBusy() return GetCursorInfo() ~= nil end
local function Place(slot, pickup, id)
    if type(slot) ~= "number" or slot < 1 or slot > 180 or slot % 1 ~= 0 then return false end
    if InCombatLockdown() or CursorBusy() then return false end
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
-- pet spells are picked up from the pet's book; PickupSpell by ID may not take them
local PickupBookItem = C_SpellBook and C_SpellBook.PickupSpellBookItem
local function PlaceKnown(slot, top)
    if top.bank == PET_BANK and PickupBookItem then
        return Place(slot, function() PickupBookItem(top.slot, PET_BANK) end, top.id)
    end
    return PlaceSpell(slot, top.id)
end

-- The pet bar is its own 10 buttons, and autocast belongs to the spell, not the button: a
-- pet with the old rank there (autocast on) keeps casting it after learning a new one.
local NUM_PET_SLOTS = NUM_PET_ACTION_SLOTS or 10
local SetAutoCast = C_SpellBook and C_SpellBook.SetSpellBookItemAutoCastEnabled
local function PetBookSlot(id)
    for slot = 1, BookEnd(PET_BANK) or 0 do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, PET_BANK)
        if info and info.spellID == id then return slot end
    end
end
local function SetPetAutoCast(slot, on)
    if slot and SetAutoCast then pcall(SetAutoCast, slot, PET_BANK, on) end
end
local function PlacePet(i, top, oldID, autoCast)
    if InCombatLockdown() or CursorBusy() or not PickupBookItem then return false end
    busy = true
    PickupBookItem(top.slot, PET_BANK)
    if CursorBusy() then PickupPetAction(i) end
    ClearCursor()
    busy = false
    local spellID = select(7, GetPetActionInfo(i))
    if spellID ~= top.id then return false end
    if autoCast then
        SetPetAutoCast(PetBookSlot(oldID), false)
        SetPetAutoCast(top.slot, true)
    end
    return true
end
-- Always the top rank: nothing on the pet bar is pinned
local function UpgradePetBar(known)
    if not (UnitExists("pet") and GetPetActionInfo) then return 0 end
    local n = 0
    for i = 1, NUM_PET_SLOTS do
        local _, _, isToken, _, _, autoCast, id = GetPetActionInfo(i)
        if not isToken and type(id) == "number" and not IsSecret(id) then
            local rank = RankOf(GetSpellSubtext(id))
            local name = rank and GetSpellName(id)
            local top = name and known[name]
            if top and top.bank == PET_BANK and top.rank > rank and top.id ~= id
                and PlacePet(i, top, id, autoCast) then
                n = n + 1
                Print(("pet bar %s: rank %d -> rank %d"):format(name, rank, top.rank))
            end
        end
    end
    return n
end

-- Conjured item families, weakest to strongest (IDs and required levels from ItemSparse).
-- On this client Spellstone and Firestone are use items that imbue the weapon, so they sit
-- on bars like a Healthstone. req: required level per item, so a mage's water above your
-- level is never put on your button. keepRanks: a mage may keep one button per gem on
-- purpose, so a gem still in bags is left alone when the best gem is already on a button.
local FAMILIES = {
    { key = "healthstone", name = "Healthstone",
      -- each Improved Healthstone talent rank is its own item
      items = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009,
          5510, 19010, 19011, 9421, 19012, 19013 },
      req = { 1, 1, 1, 12, 12, 12, 24, 24, 24, 36, 36, 36, 48, 48, 48 } },
    { key = "soulstone", name = "Soulstone", items = { 5232, 16892, 16893, 16895, 16896 } },
    { key = "spellstone", name = "Spellstone", items = { 5522, 13602, 13603 } },
    { key = "firestone", name = "Firestone", items = { 1254, 13699, 13700, 13701 } },
    { key = "gem", name = "Mana gem", items = { 5514, 5513, 8007, 8008 },
      req = { 23, 38, 48, 58 }, keepRanks = true },
    { key = "food", name = "Conjured food",
      items = { 5349, 1113, 1114, 1487, 8075, 8076, 22895 },
      req = { 1, 5, 15, 25, 35, 45, 55 } },
    { key = "water", name = "Conjured water",
      items = { 5350, 2288, 2136, 3772, 8077, 8078, 8079 },
      req = { 1, 5, 15, 25, 35, 45, 55 } },
}
local FAMILY_OF, FAMILY_BY_KEY = {}, {}
for _, fam in ipairs(FAMILIES) do
    FAMILY_BY_KEY[fam.key] = fam
    for _, id in ipairs(fam.items) do FAMILY_OF[id] = fam end
end
local STONES = { "healthstone", "soulstone", "spellstone", "firestone" }

-- nil counts as on: a missing key or table is a fresh install
local function IsOn() return db.on ~= false end
local function FamilyOn(fam) return not db.conjured or db.conjured[fam.key] ~= false end

local function BestInBags(fam)
    local level = UnitLevel("player") or 0
    for i = #fam.items, 1, -1 do
        local id = fam.items[i]
        if (not fam.req or fam.req[i] <= level) and (GetItemCount(id) or 0) > 0 then
            return id
        end
    end
end

local conjuredPending = false
local function Conjured()
    if not IsOn() then return end
    if InCombatLockdown() then conjuredPending = true; return end
    if CursorBusy() then C_Timer.After(1, Conjured); return end
    conjuredPending = false
    local best, onBar, slots = {}, {}, {}
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        local fam = kind == "item" and not IsSecret(id) and FAMILY_OF[id]
        if fam and FamilyOn(fam) then
            if best[fam] == nil then best[fam] = BestInBags(fam) or false end
            onBar[id] = true
            slots[#slots + 1] = { slot = slot, id = id, fam = fam }
        end
    end
    for _, s in ipairs(slots) do
        local to = best[s.fam]
        local keep = s.fam.keepRanks and onBar[to] and (GetItemCount(s.id) or 0) > 0
        if to and to ~= s.id and not keep and Place(s.slot, PickupItem, to) then
            onBar[to] = true
            Print(("%s on slot %d -> %s"):format(s.fam.name, s.slot, GetItemInfo(to) or to))
        end
    end
end

-- Only move a button up when a NEW rank is learned, and only if that button held the
-- previous top rank. A lower rank you chose (e.g. Life Tap rank 1) is never touched, even
-- when its pin was missed. tops = name -> highest rank already seen (per character).
local tops = {}
local pending, pendingFull = false, false
local function Upgrade(full)
    if not IsOn() then return end
    if InCombatLockdown() then
        pending = true
        pendingFull = pendingFull or full
        return
    end
    if CursorBusy() then C_Timer.After(1, function() Upgrade(full) end); return end
    full = full or pendingFull
    pending, pendingFull = false, false
    local known, lines = KnownSpells()
    -- Chains are new in 1.1.0: a replacement learned before then isn't new, so an older
    -- spell already on a bar stays (/autorank all moves it)
    if not AutoRankCharDB.chainsSeeded and knownCache then
        for _, ids in ipairs(CHAIN_IDS) do
            local top = lines[ids[1]]
            if top and top.eff > (tops[ids[1]] or 0) then tops[ids[1]] = top.eff end
        end
        AutoRankCharDB.chainsSeeded = true
    end
    local n = 0
    for slot = 1, 180 do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and type(id) == "number" and not IsSecret(id) then
            local key, eff, name, rank = BarLine(id)
            local top = key and lines[key]
            local prev = top and (tops[key] or top.eff)
            local due = top and top.eff > eff
                and (full or (top.eff > prev and eff >= prev))
            if due and top.id ~= id and pins[slot] ~= id and PlaceKnown(slot, top) then
                n = n + 1
                if top.name == name then
                    Print(("%s: rank %d -> rank %d (slot %d)")
                        :format(name, rank, top.rank, slot))
                else
                    Print(("%s -> %s (slot %d)"):format(Describe(name, rank),
                        Describe(top.name, top.rank), slot) .. Muted(" - to keep "
                        .. name .. ", drag it back from the spellbook"))
                end
            end
        end
    end
    n = n + UpgradePetBar(known)
    for key, v in pairs(lines) do
        if v.eff > 0 and v.eff > (tops[key] or 0) then tops[key] = v.eff end
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
    if InCombatLockdown() or CursorBusy() then return nil end
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

local function NotInCombat()
    if not InCombatLockdown() then return true end
    Print("bars can't be changed in combat; try again after.")
end

local function Unmacro(apply)
    if not NotInCombat() then return end
    local known = KnownSpells()
    local lower = {}
    for name, v in pairs(known) do lower[name:lower()] = { name = name, top = v } end
    local n = 0
    for slot = 1, 180 do
        local idx = MacroIndexAt(slot)
        if idx then
            local mname, _, body = GetMacroInfo(idx)
            local spell = CastOnly(body)
            local hit = spell and lower[spell:lower()]
            if hit and (not apply or PlaceKnown(slot, hit.top)) then
                n = n + 1
                Print(("slot %d: macro '%s' -> %s%s"):format(slot, mname or "?", hit.name,
                    apply and "" or " (preview)"))
            end
        end
    end
    if n == 0 then
        Print("no plain /cast macros on your bars.")
    elseif not apply then
        Print("type " .. Cmd("/autorank unmacro apply") .. " to swap them. The macros"
            .. " themselves are kept.")
    end
end

local f = CreateFrame("Frame")
local queued = false
local function Queue()
    if busy or queued then return end
    queued = true
    C_Timer.After(0.5, function() queued = false; Upgrade(false); Conjured() end)
end
local conjuredQueued = false
local function QueueConjured()
    if conjuredQueued then return end
    conjuredQueued = true
    C_Timer.After(0.5, function() conjuredQueued = false; Conjured() end)
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
    local key, eff, name, rank = BarLine(id)
    local top = key and select(2, KnownSpells())[key]
    if top and top.eff > eff then
        if pins[slot] ~= id then
            pins[slot] = id
            Print(("keeping %s on this button (slot %d). %s to undo.")
                :format(Describe(name, rank), slot, Cmd("/autorank unpin " .. slot)))
        end
    elseif pins[slot] then
        pins[slot] = nil
    end
end

local SPELLBOOK_EVENTS = { SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true,
    LEARNED_SPELL_IN_TAB = true, PLAYER_ENTERING_WORLD = true, PET_BAR_UPDATE = true,
    UNIT_PET = true, PLAYER_LEVEL_UP = true }

local function LoadDB()
    -- AutoRankDB = AutoRankDB above ran before the saved copy loaded
    AutoRankDB = AutoRankDB or {}
    db = AutoRankDB
    if db.on == nil then db.on = not db.off end
    db.conjured = db.conjured or {}
    if db.stonesOff then db.conjured.healthstone = false end
    db.stonesOff = nil
    for _, fam in ipairs(FAMILIES) do
        if db.conjured[fam.key] == nil then db.conjured[fam.key] = true end
    end
    db.off = nil
    AutoRankCharDB = AutoRankCharDB or {}
    AutoRankCharDB.pins = AutoRankCharDB.pins or {}
    pins = AutoRankCharDB.pins
    AutoRankCharDB.tops = AutoRankCharDB.tops or {}
    tops = AutoRankCharDB.tops
end

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_LEVEL_UP")
-- each exists on some clients only
pcall(f.RegisterEvent, f, "LEARNED_SPELL_IN_SKILL_LINE")
pcall(f.RegisterEvent, f, "LEARNED_SPELL_IN_TAB")
f:RegisterEvent("PET_BAR_UPDATE")
f:RegisterUnitEvent("UNIT_PET", "player")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == "AutoRank" then
            LoadDB()
            f:UnregisterEvent("ADDON_LOADED")
        end
        return
    end
    if SPELLBOOK_EVENTS[event] then knownCache = nil end
    if event == "ACTIONBAR_SLOT_CHANGED" then SlotChanged(arg); return end
    -- A loading screen fires a burst of spell, bar and bag events: one pass once it settles
    if event == "PLAYER_ENTERING_WORLD" then
        watching = false
        C_Timer.After(5, function() watching = true; Queue() end)
        return
    end
    if not watching then return end
    if event == "BAG_UPDATE_DELAYED" then
        QueueConjured()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and conjuredPending and not pending then
        QueueConjured()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" and not pending then return end
    Queue()
end)

local function Debug()
    if not NotInCombat() then return end
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

local function PinCount()
    local n = 0
    for _ in pairs(pins) do n = n + 1 end
    return n
end

local function Status()
    Print(OnOff(IsOn()) .. Muted(IsOn()
        and " - when you learn a new rank, buttons holding your previous top rank move up"
        or " - your bars are left alone"))
    local on, off = {}, {}
    for _, fam in ipairs(FAMILIES) do
        local t = FamilyOn(fam) and on or off
        t[#t + 1] = fam.name
    end
    Print("conjured item swap: " .. (#on > 0 and table.concat(on, ", ")
        or "none") .. (#off > 0 and Muted(" (off: " .. table.concat(off, ", ") .. ")")
        or ""))
    Print(("%d pinned button%s. %s for commands."):format(PinCount(),
        PinCount() == 1 and "" or "s", Cmd("/autorank help")))
end

local function Help()
    local function Line(cmd, what)
        DEFAULT_CHAT_FRAME:AddMessage("  " .. Cmd(cmd) .. " - " .. what)
    end
    Print("keeps the top rank of your spells, and the best conjured items, on your bars")
    Line("/autorank", "open the settings")
    Line("/autorank status", "what it's doing now")
    Line("/autorank on||off", "everything below; off leaves your bars alone (now "
        .. OnOff(IsOn()) .. ")")
    Line("/autorank all", "raise every unpinned button to the top rank now")
    Line("/autorank pins", "list buttons kept at a low rank on purpose")
    Line("/autorank unpin [slot]", "let a pinned button (or all of them) upgrade again")
    local keys, off = {}, {}
    for _, fam in ipairs(FAMILIES) do
        keys[#keys + 1] = fam.key
        if not FamilyOn(fam) then off[#off + 1] = fam.key end
    end
    Line("/autorank <item> on||off", "a button holding that conjured item gets your best"
        .. " one: " .. table.concat(keys, ", ") .. " (now " .. (#off == 0 and OnOff(true)
        .. " for all" or OnOff(false) .. ": " .. table.concat(off, ", ")) .. ")")
    Line("/autorank stones on||off", "the four warlock stones at once")
    Line("/autorank unmacro [apply]", "list, then swap, bar macros that are just"
        .. " \"/cast Spell\" for the spell (the macros are kept)")
    Line("/autorank debug", "print the spellbook size and every bar macro")
    DEFAULT_CHAT_FRAME:AddMessage("  Settings: Esc > Options > AddOns > AutoRank ("
        .. Cmd("/autorank settings") .. ")")
end

local function SetConjured(keys, on)
    db.conjured = db.conjured or {}
    for _, key in ipairs(keys) do db.conjured[key] = on end
    if on then Conjured() end
end
local function SetOn(on)
    db.on = on
    if on then Upgrade(false); Conjured() end
end
local function UnpinAll()
    wipe(pins)
    Upgrade(false)
end

ns.db = function() return db end
ns.FAMILIES = FAMILIES
ns.Print, ns.OnOff = Print, OnOff
ns.SetOn, ns.SetConjured, ns.UnpinAll, ns.PinCount = SetOn, SetConjured, UnpinAll, PinCount
ns.Help = Help

local function PrintPins()
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
end

SLASH_AUTORANK1 = "/autorank"
SlashCmdList.AUTORANK = function(msg)
    msg = strtrim((msg or ""):lower())
    local word, rest = msg:match("^(%S*)%s*(.-)$")
    local fam = FAMILY_BY_KEY[word]
    if msg == "" or word == "settings" or word == "options" then
        if not (ns.OpenSettings and ns.OpenSettings()) then Help() end
    elseif word == "help" or word == "?" then
        Help()
    elseif word == "status" then
        Status()
    elseif msg == "on" or msg == "off" then
        local on = msg == "on"
        Print(OnOff(on) .. (on and "" or Muted(" - your bars are left alone")))
        SetOn(on)
    elseif msg == "all" then
        if InCombatLockdown() then Print("after combat: raising every unpinned button.") end
        Upgrade(true)
    elseif (fam or word == "stones") and (rest == "on" or rest == "off") then
        Print((fam and fam.name .. " swap " or "Healthstone, Soulstone, Spellstone and"
            .. " Firestone swap ") .. OnOff(rest == "on"))
        SetConjured(fam and { fam.key } or STONES, rest == "on")
    elseif msg == "pins" then
        PrintPins()
    elseif word == "unpin" then
        local slot = tonumber(rest)
        Print(slot and ("slot %d will upgrade again."):format(slot) or "all pins removed.")
        if slot then pins[slot] = nil; Upgrade(false) else UnpinAll() end
    elseif msg == "debug" then
        Debug()
    elseif word == "unmacro" then
        Unmacro(rest == "apply")
    else
        Print(("unknown command \"%s\""):format(msg))
        Help()
    end
end
