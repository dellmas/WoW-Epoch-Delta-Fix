-- DWD Tooltip Delta Fix (WotLK 3.3.5)
-- • Clean compare tooltips (no flicker / no yellow block)
-- • Correct deltas (Armor, DPS, Str/Agi/Sta/Int/Spi)
-- • Works in vendors, inventory, quest rewards, hyperlinks
-- • Works in trainer/tradeskill recipe tooltips
-- • "Currently Equipped" header, clamped layout
-- • Skips compare when hovering equipped slots
-- • Retry + no-empty-header safeguards
-- • Header shows hovered item name: "<item name> changes:"
-- • Ignore normal ability/talent tooltips (no compares on abilities)
-- • NEW: More robust stat parsing (both columns, multiple phrasings)
-- • NEW: Optional set info in compare pane

------------------------------------------------------------
-- Config
------------------------------------------------------------
local ALWAYS_SHOW_COMPARE           = true
local SHOW_DELTAS_ON_MAIN           = false
local SHOW_DELTAS_ON_COMPARE        = true
local SUPPRESS_WHEN_HOVERING_EQUIPPED = true
local SHOW_SET_INFO_ON_COMPARE      = true   -- <— new

-- layout tuning
local COMPARE_X_PAD   = 0
local COMPARE_Y_PAD   = -10
local SCREEN_MARGIN   = 12

------------------------------------------------------------
-- Scanner
------------------------------------------------------------
local scan = CreateFrame("GameTooltip", "DWDScanTT", UIParent, "GameTooltipTemplate")
scan:SetOwner(UIParent, "ANCHOR_NONE")
for i = 1, 40 do
  local L = scan:CreateFontString("DWDScanTTTextLeft"..i, nil, "GameFontNormal")
  local R = scan:CreateFontString("DWDScanTTTextRight"..i, nil, "GameFontNormal")
  scan:AddFontStrings(L, R)
end

local function tonum(s) if not s then return nil end s = s:gsub(",", "") return tonumber(s) end
local function itemID(link) return link and link:match("item:(%d+):") end

-- equiploc → slot(s)
local SLOT_SINGLE = {
  INVTYPE_HEAD=1, INVTYPE_NECK=2, INVTYPE_SHOULDER=3, INVTYPE_BODY=4,
  INVTYPE_CHEST=5, INVTYPE_ROBE=5, INVTYPE_WAIST=6, INVTYPE_LEGS=7,
  INVTYPE_FEET=8, INVTYPE_WRIST=9, INVTYPE_HAND=10, INVTYPE_CLOAK=15,
  INVTYPE_RANGED=18, INVTYPE_RANGEDRIGHT=18, INVTYPE_THROWN=18, INVTYPE_RELIC=18,
  INVTYPE_TABARD=19,
}
local function slotsForEquipLoc(equipLoc)
  if not equipLoc then
    return nil
  elseif equipLoc == "INVTYPE_FINGER" then
    return {11, 12}
  elseif equipLoc == "INVTYPE_TRINKET" then
    return {13, 14}
  elseif equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_HOLDABLE" then
    return {17}
  elseif equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
    return {16, 17}
  else
    local s = SLOT_SINGLE[equipLoc]
    if s then return {s} end
  end
  return nil
end

------------------------------------------------------------
-- Robust parsing helpers
------------------------------------------------------------
local STAT_KEYS = { strength="STR", agility="AGI", stamina="STA", intellect="INT", spirit="SPI" }

local function stripColorCodes(s)
  if not s then return nil end
  -- strip |cAARRGGBB ... |r just in case
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return s
end

-- Parse a single line for primary stats using multiple phrasings and allow multiple stats on one line.
-- Parse "+11 Strength", "Strength +11", "Increases your Strength by 11", etc.
local function consumePrimaryStats(line, st)
  if not line or line == "" then return end
  line = stripColorCodes(line)
  local l = line:lower()
  local function add(v, key) if v then st[key] = (st[key] or 0) + tonumber(v) end end

  -- +N Stat / Stat +N
  add(l:match("%+(%d+)%s+strength"), "STR");   add(l:match("strength%s*%+(%d+)"), "STR")
  add(l:match("%+(%d+)%s+agility"),  "AGI");   add(l:match("agility%s*%+(%d+)"),  "AGI")
  add(l:match("%+(%d+)%s+stamina"),  "STA");   add(l:match("stamina%s*%+(%d+)"),  "STA")
  add(l:match("%+(%d+)%s+intellect"),"INT");   add(l:match("intellect%s*%+(%d+)"),"INT")
  add(l:match("%+(%d+)%s+spirit"),   "SPI");   add(l:match("spirit%s*%+(%d+)"),   "SPI")

  -- Increases/Improves (with or without "your")
  add(l:match("increases%s+your%s+strength%s+by%s+(%d+)") or l:match("increases%s+strength%s+by%s+(%d+)"), "STR")
  add(l:match("increases%s+your%s+agility%s+by%s+(%d+)")  or l:match("increases%s+agility%s+by%s+(%d+)"),  "AGI")
  add(l:match("increases%s+your%s+stamina%s+by%s+(%d+)")  or l:match("increases%s+stamina%s+by%s+(%d+)"),  "STA")
  add(l:match("increases%s+your%s+intellect%s+by%s+(%d+)")or l:match("increases%s+intellect%s+by%s+(%d+)"),"INT")
  add(l:match("increases%s+your%s+spirit%s+by%s+(%d+)")   or l:match("increases%s+spirit%s+by%s+(%d+)"),   "SPI")

  add(l:match("improves%s+your%s+strength%s+by%s+(%d+)")  or l:match("improves%s+strength%s+by%s+(%d+)"),  "STR")
  add(l:match("improves%s+your%s+agility%s+by%s+(%d+)")   or l:match("improves%s+agility%s+by%s+(%d+)"),   "AGI")
  add(l:match("improves%s+your%s+stamina%s+by%s+(%d+)")   or l:match("improves%s+stamina%s+by%s+(%d+)"),   "STA")
  add(l:match("improves%s+your%s+intellect%s+by%s+(%d+)") or l:match("improves%s+intellect%s+by%s+(%d+)"), "INT")
  add(l:match("improves%s+your%s+spirit%s+by%s+(%d+)")    or l:match("improves%s+spirit%s+by%s+(%d+)"),    "SPI")

  -- +N All Stats (gems/enchants)
  local all = l:match("%+(%d+)%s+all%s+stats") or l:match("all%s+stats%s*%+(%d+)")
  if all then
    all = tonumber(all)
    st.STR = st.STR + all; st.AGI = st.AGI + all; st.STA = st.STA + all; st.INT = st.INT + all; st.SPI = st.SPI + all
  end
end

-- Read both columns and compute DPS if needed
local function parseStatsFromTooltip(tt)
  local st = { ARMOR=0, DPS=nil, STR=0, AGI=0, STA=0, INT=0, SPI=0 }
  local name = tt:GetName()
  local minD, maxD, spd
  for i = 2, tt:NumLines() do
    local L = _G[name.."TextLeft"..i];  local sL = L and L:GetText()
    local R = _G[name.."TextRight"..i]; local sR = R and R:GetText()

    local function eat(s)
      if not s then return end
      s = stripColorCodes(s)
      local l = s:lower()
      local a = l:match("([%d,]+)%s*armor"); if a then st.ARMOR = tonum(a) or st.ARMOR end
      consumePrimaryStats(s, st)
      local dps = l:match("%(([%d%.]+)%s*damage per second%)"); if dps then st.DPS = tonumber(dps) end
      local d1, d2 = l:match("(%d+)%s*%-%s*(%d+)%s*damage"); if d1 and d2 then minD, maxD = tonumber(d1), tonumber(d2) end
      local sp = l:match("speed%s*([%d%.]+)"); if sp then spd = tonumber(sp) end
    end

    eat(sL); eat(sR)
  end
  if not st.DPS and minD and maxD and spd and spd > 0 then
    st.DPS = ((minD + maxD) / 2) / spd
  end
  return st
end


local function getStatsFromLink(link)
  -- defaults
  local st = { ARMOR=0, DPS=nil, STR=0, AGI=0, STA=0, INT=0, SPI=0 }
  if not link then return st end

  -- 1) Trust the game API first (localization- & format-safe)
  local S = GetItemStats(link)
  if S then
    -- primary stats
    st.STR = (S["ITEM_MOD_STRENGTH_SHORT"] or S["ITEM_MOD_STRENGTH"] or 0)
    st.AGI = (S["ITEM_MOD_AGILITY_SHORT"]  or S["ITEM_MOD_AGILITY"]  or 0)
    st.STA = (S["ITEM_MOD_STAMINA_SHORT"]  or S["ITEM_MOD_STAMINA"]  or 0)
    st.INT = (S["ITEM_MOD_INTELLECT_SHORT"]or S["ITEM_MOD_INTELLECT"]or 0)
    st.SPI = (S["ITEM_MOD_SPIRIT_SHORT"]   or S["ITEM_MOD_SPIRIT"]   or 0)
    -- armor (Blizz used either of these keys in WotLK)
    st.ARMOR = (S["ITEM_MOD_ARMOR_SHORT"] or S["RESISTANCE0_NAME"] or 0)
  end

  -- 2) Fallback/augment with a tooltip read (DPS/Armor calc & odd items)
  scan:ClearLines(); scan:SetHyperlink(link)
  local t = parseStatsFromTooltip(scan)
  -- prefer DPS from tooltip math when API doesn't return it
  if not st.DPS then st.DPS = t.DPS end
  if (st.ARMOR or 0) <= 0 and (t.ARMOR or 0) > 0 then st.ARMOR = t.ARMOR end

  -- if an Epoch-custom item hid primaries from GetItemStats, adopt tooltip values
  if st.STR==0 and st.AGI==0 and st.STA==0 and st.INT==0 and st.SPI==0 then
    st.STR,st.AGI,st.STA,st.INT,st.SPI = t.STR,t.AGI,t.STA,t.INT,t.SPI
  end
  return st
end


local function getStatsFromShown(tt)
  return parseStatsFromTooltip(tt)
end

------------------------------------------------------------
-- Parse set info (for the hovered item) and optionally show it
------------------------------------------------------------
local function extractSetInfoFromTooltip(tt)
  local name = tt:GetName()
  local set = nil
  for i = 2, tt:NumLines() do
    local L = _G[name.."TextLeft"..i]; local s = L and stripColorCodes(L:GetText())
    if s and s ~= "" then
      local nm, eq, total = s:match("^(.+)%s*%((%d+)%/(%d+)%)$")
      if nm and eq and total then
        set = { name = nm, equipped = tonumber(eq), total = tonumber(total), bonuses = {} }
      elseif set then
        local need, text = s:match("^%((%d+)%)%s*Set:%s*(.+)$")
        if need and text then table.insert(set.bonuses, {need = tonumber(need), text = text}) end
      end
    end
  end
  return set
end

local function getSetInfoFromLink(link)
  if not link then return nil end
  scan:ClearLines(); scan:SetHyperlink(link)
  return extractSetInfoFromTooltip(scan)
end

local function appendSetInfo(tt, set)
  if not set then return end
  tt:AddLine(" ")
  tt:AddLine(("Set: %s (%d/%d)"):format(set.name, set.equipped or 0, set.total or 0), 0.6, 0.8, 1)
  for _, b in ipairs(set.bonuses or {}) do
    local active = (set.equipped or 0) >= (b.need or 0)
    local r,g,bcol = active and 0 or 0.75, active and 1 or 0.75, active and 0 or 0.75
    tt:AddLine(("  (%d) %s"):format(b.need or 0, b.text or ""), r,g,bcol)
  end
  tt:Show()
end

------------------------------------------------------------
-- Derive equipLoc by reading the visible tooltip (for trainer/recipes)
------------------------------------------------------------
local SLOT_WORD_TO_EQUIP = {
  ["head"] = "INVTYPE_HEAD", ["neck"] = "INVTYPE_NECK", ["shoulder"] = "INVTYPE_SHOULDER",
  ["shirt"] = "INVTYPE_BODY", ["chest"] = "INVTYPE_CHEST", ["robe"] = "INVTYPE_ROBE",
  ["waist"] = "INVTYPE_WAIST", ["legs"] = "INVTYPE_LEGS", ["feet"] = "INVTYPE_FEET",
  ["wrist"] = "INVTYPE_WRIST", ["hands"] = "INVTYPE_HAND", ["finger"] = "INVTYPE_FINGER",
  ["trinket"] = "INVTYPE_TRINKET", ["back"] = "INVTYPE_CLOAK", ["tabard"] = "INVTYPE_TABARD",
  ["main hand"] = "INVTYPE_WEAPONMAINHAND", ["off hand"] = "INVTYPE_WEAPONOFFHAND",
  ["held in off-hand"] = "INVTYPE_HOLDABLE",
  ["one-hand"] = "INVTYPE_WEAPON", ["two-hand"] = "INVTYPE_2HWEAPON",
  ["ranged"] = "INVTYPE_RANGED", ["thrown"] = "INVTYPE_THROWN", ["relic"] = "INVTYPE_RELIC",
}

-- Only treat spell tooltips as "items" if they look like items
local function tooltipLooksLikeItem(tt)
  local name = tt:GetName()
  for i = 2, tt:NumLines() do
    local s = _G[name.."TextLeft"..i]; s = s and s:GetText()
    if s then
      local l = s:lower()
      if l:find("binds when equipped", 1, true)
         or l:find("durability", 1, true)
         or l:find("requires level", 1, true)
         or l:match("^[%+%-]%d+%s+%a+")
         or l:match("([%d,]+)%s*armor")
         or l:match("%d+%s*%-%s*%d+%s*damage")
         or l:find("damage per second", 1, true) then
        return true
      end
    end
  end
  return false
end

local function getEquipLocFromShown(tt)
  if not tooltipLooksLikeItem(tt) then return nil end
  local name = tt:GetName()
  for i = 2, tt:NumLines() do
    local s = _G[name.."TextLeft"..i]; s = s and s:GetText()
    if s then
      local l = s:lower()
      for key, loc in pairs(SLOT_WORD_TO_EQUIP) do
        if l:find(key, 1, true) then return loc end
      end
    end
  end
  return nil
end

------------------------------------------------------------
-- Resolve a display name for the header
------------------------------------------------------------
local function getDisplayName(newObj, tt, provided)
  if provided and provided ~= "" then return provided end
  if type(newObj) == "string" then
    local n = GetItemInfo(newObj)
    if n then return n end
    local bracket = newObj:match("%[(.-)%]")
    if bracket then return bracket end
  end
  if tt and tt.GetName then
    local l1 = _G[tt:GetName().."TextLeft1"]
    local t = l1 and l1:GetText()
    if t then
      local after = t:match(":%s*(.+)$")
      return after or t
    end
  end
  return "Correct stat changes"
end

------------------------------------------------------------
-- Delta rendering
------------------------------------------------------------
local function addDeltaLine(tt, label, delta, isFloat)
  if delta == nil or delta == 0 then return false end
  if isFloat then delta = tonumber(string.format("%.1f", delta)) end
  local r,g,b = (delta < 0) and 1 or 0, (delta < 0) and 0 or 1, 0
  local fmt = isFloat and "%+.1f %s" or "%+d %s"
  tt:AddLine(string.format(fmt, delta, label), r,g,b)
  return true
end

local function toStats(obj)
  if type(obj) == "table" then return obj end
  return getStatsFromLink(obj)
end

local function appendCorrectDeltas(tt, newObj, oldObj, dispName)
  if tt._dwd_added or not newObj then return false end
  if type(newObj)=="string" and type(oldObj)=="string" and itemID(newObj) and itemID(newObj) == itemID(oldObj) then
    return false
  end

  local N, O = toStats(newObj), toStats(oldObj)
  local deltas = {
    { "Armor",              (N.ARMOR or 0) - (O.ARMOR or 0), false },
    { "Damage Per Second",  (N.DPS   or 0) - (O.DPS   or 0), true  },
    { "Strength",           (N.STR   or 0) - (O.STR   or 0), false },
    { "Agility",            (N.AGI   or 0) - (O.AGI   or 0), false },
    { "Stamina",            (N.STA   or 0) - (O.STA   or 0), false },
    { "Intellect",          (N.INT   or 0) - (O.INT   or 0), false },
    { "Spirit",             (N.SPI   or 0) - (O.SPI   or 0), false },
  }

  local any = false
  for _, d in ipairs(deltas) do if d[2] and d[2] ~= 0 then any = true; break end end
  if not any then return false end

  local header = (getDisplayName(newObj, tt, dispName) or "Correct stat changes") .. " changes:"
  tt:AddLine(header, 1, 0.82, 0)
  for _, d in ipairs(deltas) do addDeltaLine(tt, d[1], d[2], d[3]) end

  -- Optionally show set info about the NEW item directly under the deltas
  if SHOW_SET_INFO_ON_COMPARE and type(newObj) == "string" then
    local set = getSetInfoFromLink(newObj)
    if set then appendSetInfo(tt, set) end
  end

  tt._dwd_added = true; tt:Show()
  return true
end

-- Retry wrapper for uncached items (first hovers)
local DWDRetryFrame = CreateFrame("Frame"); DWDRetryFrame:Hide()
local pending = {}
DWDRetryFrame:SetScript("OnUpdate", function(self)
  for i = #pending, 1, -1 do
    local p = pending[i]
    if not p.tt:IsShown() or GetTime() > p.deadline then
      table.remove(pending, i)
    else
      if appendCorrectDeltas(p.tt, p.newObj, p.oldObj, p.name) then
        table.remove(pending, i)
      end
    end
  end
  if #pending == 0 then self:Hide() end
end)
local function appendWithRetry(tt, newObj, oldObj, dispName)
  if type(newObj) ~= "string" then
    appendCorrectDeltas(tt, newObj, oldObj, dispName); return
  end
  if appendCorrectDeltas(tt, newObj, oldObj, dispName) then return end
  table.insert(pending, { tt = tt, newObj = newObj, oldObj = oldObj, deadline = GetTime() + 0.6, name = dispName })
  DWDRetryFrame:Show()
end

------------------------------------------------------------
-- Remove only the yellow block (keeps DPS/Armor)
------------------------------------------------------------
local function scrubYellowBlock(tt)
  if not tt or not tt:GetName() then return end
  local name = tt:GetName()
  local n = tt:NumLines()
  for i = 1, n do
    local L = _G[name.."TextLeft"..i]
    local text = L and L:GetText()
    if type(text) == "string" and text:lower():find("if you replace this item") then
      for j = i, math.min(i + 12, n) do
        local Lj = _G[name.."TextLeft"..j]; if not Lj then break end
        local tj = Lj:GetText()
        if type(tj) == "string" then
          local low = tj:lower()
          if j == i or low:match("^%s*[+%-]%s*[%d%.]+") or low:find("damage per second")
             or low:find("armor") or low:find("strength") or low:find("agility")
             or low:find("stamina") or low:find("intellect") or low:find("spirit") then
            Lj:SetText("")
          else
            break
          end
        end
      end
      tt:Show(); return
    end
  end
end

------------------------------------------------------------
-- Our compare tooltips
------------------------------------------------------------
local DWDCompare1 = CreateFrame("GameTooltip", "DWDCompareTooltip1", UIParent, "GameTooltipTemplate")
local DWDCompare2 = CreateFrame("GameTooltip", "DWDCompareTooltip2", UIParent, "GameTooltipTemplate")
local OUR_COMPARES = { DWDCompare1, DWDCompare2 }
for _, f in ipairs(OUR_COMPARES) do
  f:SetClampedToScreen(true)
  f:HookScript("OnTooltipCleared", function(self) self._dwd_added = false; self._dwd_equippedHdr = false end)
end
local function hideOurCompares() for _, f in ipairs(OUR_COMPARES) do f:Hide() end end
GameTooltip:HookScript("OnHide", hideOurCompares)

local function addEquippedHeader(tt)
  local name = tt:GetName()
  local l1 = name and _G[name.."TextLeft1"]
  if not l1 or tt._dwd_equippedHdr then return end
  local t = l1:GetText()
  if t and not t:lower():find("currently equipped") then
    l1:SetText("|cff7f7f7fCurrently Equipped|r\n"..t)
  end
  tt._dwd_equippedHdr = true
end

-- place side-by-side & keep on screen (prefer LEFT of the hovered tooltip)
local function layoutCompares(mainTT)
  if not mainTT or not mainTT:IsShown() then return end

  local uiW   = UIParent:GetWidth()
  local left  = mainTT:GetLeft()  or 0
  local right = mainTT:GetRight() or 0

  local w1 = DWDCompare1:IsShown() and (DWDCompare1:GetWidth() or 0) or 0
  local w2 = DWDCompare2:IsShown() and (DWDCompare2:GetWidth() or 0) or 0
  local panes = (DWDCompare1:IsShown() and 1 or 0) + (DWDCompare2:IsShown() and 1 or 0)

  local approx = (panes > 0) and (180 * panes + (panes > 1 and COMPARE_X_PAD or 0)) or 0
  local total  = math.max(w1 + ((w2 > 0 and (COMPARE_X_PAD + w2)) or 0), approx)

  local spaceRight = uiW - right - SCREEN_MARGIN
  local spaceLeft  = left - SCREEN_MARGIN

  local placed = false

  -- Try LEFT first
  if spaceLeft >= total then
    if DWDCompare1:IsShown() then
      DWDCompare1:ClearAllPoints()
      DWDCompare1:SetPoint("TOPRIGHT", mainTT, "TOPLEFT", -COMPARE_X_PAD, COMPARE_Y_PAD)
    end
    if DWDCompare2:IsShown() then
      DWDCompare2:ClearAllPoints()
      DWDCompare2:SetPoint("TOPRIGHT", DWDCompare1, "TOPLEFT", -COMPARE_X_PAD, 0)
    end
    placed = true
  -- Fall back to RIGHT
  elseif spaceRight >= total then
    if DWDCompare1:IsShown() then
      DWDCompare1:ClearAllPoints()
      DWDCompare1:SetPoint("TOPLEFT", mainTT, "TOPRIGHT", COMPARE_X_PAD, COMPARE_Y_PAD)
    end
    if DWDCompare2:IsShown() then
      DWDCompare2:ClearAllPoints()
      DWDCompare2:SetPoint("TOPLEFT", DWDCompare1, "TOPRIGHT", COMPARE_X_PAD, 0)
    end
    placed = true
  end

  -- Final fallback: stack below the hovered tooltip
  if not placed then
    if DWDCompare1:IsShown() then
      DWDCompare1:ClearAllPoints()
      DWDCompare1:SetPoint("TOPLEFT", mainTT, "BOTTOMLEFT", 0, -8)
    end
    if DWDCompare2:IsShown() then
      DWDCompare2:ClearAllPoints()
      DWDCompare2:SetPoint("TOPLEFT", DWDCompare1, "BOTTOMLEFT", 0, -8)
    end
  end
end

-- show compare tooltips; newObj can be a link (string) or a stats table
local function showOurCompare(mainTT, newObj, equipLocHint, statsHint, dispName)
  hideOurCompares()

  -- Figure out where the item would go
  local equipLoc = equipLocHint
  if not equipLoc and type(newObj) == "string" then
    equipLoc = select(9, GetItemInfo(newObj))
  end
  if not equipLoc then return end

  local slots = slotsForEquipLoc(equipLoc)
  if not slots or #slots == 0 then return end

  local shown = 0
  local hadAnyEquipped = false

  -- Normal path: show compares for any actually equipped items we’re replacing
  for _, slot in ipairs(slots) do
    local oldLink = GetInventoryItemLink("player", slot)
    if oldLink and OUR_COMPARES[shown + 1] then
      hadAnyEquipped = true
      shown = shown + 1
      local f = OUR_COMPARES[shown]
      f:SetOwner(mainTT, "ANCHOR_NONE")
      f._dwd_added = false; f._dwd_equippedHdr = false
      f:SetInventoryItem("player", slot)
      if SHOW_DELTAS_ON_COMPARE then
        appendWithRetry(f, statsHint or newObj, oldLink, dispName or (type(newObj)=="string" and GetItemInfo(newObj)) )
      end
      local name = f:GetName()
      local l1 = name and _G[name.."TextLeft1"]
      if l1 then
        l1:SetText("|cff7f7f7fCurrently Equipped|r\n"..(l1:GetText() or ""))
        f._dwd_equippedHdr = true
      end
      scrubYellowBlock(f)
      f:Show()
    end
  end

  -- Fallback: if nothing is equipped in those slots, still show ONE compare pane
  if not hadAnyEquipped and OUR_COMPARES[1] then
    local f = OUR_COMPARES[1]
    shown = 1
    f:SetOwner(mainTT, "ANCHOR_NONE")
    f._dwd_added = false; f._dwd_equippedHdr = true
    f:ClearLines()
    f:AddLine("|cff7f7f7fCurrently Equipped|r", 1, 1, 1)
    f:AddLine("None", 0.8, 0.8, 0.8)

    local displayName = dispName
    if type(newObj) == "string" and not displayName then displayName = GetItemInfo(newObj) end
    if SHOW_DELTAS_ON_COMPARE then
      appendWithRetry(f, statsHint or newObj, nil, displayName)
    end
    f:Show()
  end

  layoutCompares(mainTT)
end

-- kill Blizzard/Epoch compare path
GameTooltip_ShowCompareItem = function() end
for i = 1, 6 do local s = _G["ShoppingTooltip"..i]; if s then s:HookScript("OnShow", function(self) self:Hide() end) end end

------------------------------------------------------------
-- Detect hovering an equipped slot
------------------------------------------------------------
local function isChildOf(frame, root)
  while frame do if frame == root then return true end frame = frame:GetParent() end
  return false
end

local function isHoveringEquippedSlot(tt, link)
  if not SUPPRESS_WHEN_HOVERING_EQUIPPED then return false end
  local owner = tt:GetOwner() or GetMouseFocus()
  local name = owner and owner.GetName and owner:GetName()
  if name and name:match("^Character.+Slot$") then return true end
  local id = itemID(link)
  if id then
    for slot = 1, 19 do
      local eq = GetInventoryItemLink("player", slot)
      if eq and itemID(eq) == id then
        if owner and CharacterFrame and isChildOf(owner, CharacterFrame) then
          return true
        end
      end
    end
  end
  return false
end

------------------------------------------------------------
-- Main tooltip hooks
------------------------------------------------------------
local function patchGameTooltip(tt)
  if not tt or tt._dwd_patched then return end
  tt._dwd_patched = true
  tt:SetClampedToScreen(true)

  tt:HookScript("OnTooltipCleared", function(self) self._dwd_added = false end)

  -- Normal item hovers
  tt:HookScript("OnTooltipSetItem", function(self)
    self._dwd_added = false
    local _, newLink = self:GetItem(); if not newLink then return end

    if SHOW_DELTAS_ON_MAIN then
      local equipLoc = select(9, GetItemInfo(newLink))
      local slots = slotsForEquipLoc(equipLoc)
      local oldLink = slots and GetInventoryItemLink("player", slots[1]) or nil
      appendWithRetry(self, newLink, oldLink, GetItemInfo(newLink))
    end

    if ALWAYS_SHOW_COMPARE and not isHoveringEquippedSlot(self, newLink) then
      showOurCompare(self, newLink, nil, nil, GetItemInfo(newLink))
    else
      hideOurCompares()
    end

    scrubYellowBlock(self)
  end)

  -- Recipe/trainer *item output* tooltips only (skip abilities/talents)
  tt:HookScript("OnTooltipSetSpell", function(self)
    self._dwd_added = false

    if not tooltipLooksLikeItem(self) then return end

    local equipLoc = getEquipLocFromShown(self); if not equipLoc then return end
    local stats = getStatsFromShown(self)
    local nameFS = _G[self:GetName().."TextLeft1"]
    local disp = nameFS and nameFS:GetText() or ""
    disp = disp:gsub("^.-:%s*", "") -- strip "Blacksmithing: "

    if ALWAYS_SHOW_COMPARE then
      showOurCompare(self, stats, equipLoc, stats, disp)
    end
  end)
end

patchGameTooltip(GameTooltip)
patchGameTooltip(ItemRefTooltip)
