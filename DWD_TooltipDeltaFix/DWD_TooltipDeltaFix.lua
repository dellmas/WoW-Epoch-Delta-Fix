-- DWD Tooltip Delta Fix (WotLK 3.3.5)
-- • Clean compare tooltips (no flicker, strip yellow “If you replace…” block)
-- • Correct deltas (Armor, DPS, Str/Agi/Sta/Int/Spi)
-- • Works in vendors, inventory, quest rewards, hyperlinks, recipes/trainers
-- • “Currently Equipped” header, clamped layout, side-by-side compares
-- • Skip compares when hovering your own equipped slots
-- • Header shows hovered item name: "<item name> changes:"
-- • Always mirror green, class/form-conditional info onto BOTH main + compare

------------------------------------------------------------
-- Config
------------------------------------------------------------
local ALWAYS_SHOW_COMPARE     = true
local SHOW_DELTAS_ON_MAIN     = false      -- keep false; deltas live on compare tooltips
local SHOW_DELTAS_ON_COMPARE  = true
local SUPPRESS_WHEN_HOVERING_EQUIPPED = true

-- layout tuning
local COMPARE_X_PAD   = 0
local COMPARE_Y_PAD   = -10
local SCREEN_MARGIN   = 12

------------------------------------------------------------
-- Hidden scanner tooltip
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

-- Equip location -> slot(s)
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
-- Parse stats
------------------------------------------------------------
local function parseStatsFromLines(getLine, numLines)
  local st = { ARMOR=0, DPS=nil, STR=0, AGI=0, STA=0, INT=0, SPI=0 }
  local minD, maxD, spd
  for i = 2, numLines do
    local s = getLine(i)
    if s then
      local lower = s:lower()
      -- Armor
      local a = lower:match("([%d,]+)%s*armor"); if a then st.ARMOR = tonum(a) or st.ARMOR end
      -- Primary stats
      local v = lower:match("%+(%d+)%s+strength"); if v then st.STR = st.STR + tonumber(v) end
      v = lower:match("%+(%d+)%s+agility");        if v then st.AGI = st.AGI + tonumber(v) end
      v = lower:match("%+(%d+)%s+stamina");        if v then st.STA = st.STA + tonumber(v) end
      v = lower:match("%+(%d+)%s+intellect");      if v then st.INT = st.INT + tonumber(v) end
      v = lower:match("%+(%d+)%s+spirit");         if v then st.SPI = st.SPI + tonumber(v) end
      -- DPS (explicit)
      local dps = lower:match("%(([%d%.]+)%s*damage per second%)")
      if dps then st.DPS = tonumber(dps) end
      -- DPS (fallback from damage range + speed)
      local d1, d2 = lower:match("(%d+)%s*%-%s*(%d+)%s*damage"); if d1 and d2 then minD, maxD = tonumber(d1), tonumber(d2) end
      local sp = lower:match("speed%s*([%d%.]+)"); if sp then spd = tonumber(sp) end
    end
  end
  if not st.DPS and minD and maxD and spd and spd > 0 then
    st.DPS = ((minD + maxD) / 2) / spd
  end
  return st
end

local function getStatsFromLink(link)
  if not link then return { ARMOR=0, DPS=nil, STR=0, AGI=0, STA=0, INT=0, SPI=0 } end
  scan:ClearLines(); scan:SetHyperlink(link)
  return parseStatsFromLines(function(i) local L=_G["DWDScanTTTextLeft"..i]; return L and L:GetText() end, scan:NumLines())
end

local function getStatsFromShown(tt)
  local name = tt:GetName()
  return parseStatsFromLines(function(i) local L=_G[name.."TextLeft"..i]; return L and L:GetText() end, tt:NumLines())
end

-- Derive equipLoc by reading visible text (recipe/trainer)
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
local function getEquipLocFromShown(tt)
  local name = tt:GetName()
  for i = 2, tt:NumLines() do
    local s = _G[name.."TextLeft"..i]
    s = s and s:GetText()
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
-- Display name for header
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
  tt._dwd_added = true; tt:Show()
  return true
end

-- Retry wrapper for uncached items
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
-- Strip yellow "If you replace this item..." block (if server/UI adds it)
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
-- ALWAYS show green class/form conditional info on ANY tooltip
------------------------------------------------------------
local CLASS_OR_FORM_KEYS = {
  "cat","bear","dire bear","moonkin",
  "warrior","paladin","hunter","rogue","priest","shaman","mage","warlock","death knight","deathknight",
  -- feel free to extend for Epoch-specific forms/classes if any
}

local function containsAny(hay, list)
  for _, needle in ipairs(list) do
    if hay:find(needle, 1, true) then return true end
  end
  return false
end

local function tooltipHasSubstring(tt, substrLow)
  local name = tt:GetName()
  for i = 2, tt:NumLines() do
    local L = _G[name.."TextLeft"..i]
    local s = L and L:GetText()
    if s and s:lower():find(substrLow, 1, true) then return true end
  end
  return false
end

-- Collect conditional class/form lines from an item link
local function getConditionalLinesFromLink(link)
  if not link then return nil end
  scan:ClearLines(); scan:SetHyperlink(link)
  local lines = {}
  for i = 2, scan:NumLines() do
    local L = _G["DWDScanTTTextLeft"..i]
    local s = L and L:GetText()
    if s then
      local low = s:lower()
      -- Heuristic: capture lines that are clearly conditional and class/form related
      local looksConditional = (low:find("increases", 1, true) or low:find("equip:", 1, true) or low:find("while", 1, true) or low:find("only", 1, true))
      if looksConditional and containsAny(low, CLASS_OR_FORM_KEYS) then
        table.insert(lines, s)
      end
    end
  end
  return (#lines > 0) and lines or nil
end

local function ensureConditionalInfoShown(tt, itemLink)
  local lines = getConditionalLinesFromLink(itemLink)
  if not lines then return end
  for _, s in ipairs(lines) do
    local low = s:lower()
    if not tooltipHasSubstring(tt, low) then
      tt:AddLine(s, 0, 1, 0) -- green
    end
  end
  tt:Show()
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

-- place side-by-side & keep on screen
local function layoutCompares(mainTT)
  local uiW   = UIParent:GetWidth()
  local left  = mainTT:GetLeft()  or 0
  local right = mainTT:GetRight() or 0
  local w1 = DWDCompare1:IsShown() and (DWDCompare1:GetWidth() or 0) or 0
  local w2 = DWDCompare2:IsShown() and (DWDCompare2:GetWidth() or 0) or 0
  local total = w1 + ((w2 > 0 and (COMPARE_X_PAD + w2)) or 0)
  local spaceRight = uiW - right - SCREEN_MARGIN
  local spaceLeft  = left - SCREEN_MARGIN
  local placeRight = (spaceRight >= total)
  local placeLeft  = (spaceLeft  >= total)
  if placeRight then
    if DWDCompare1:IsShown() then
      DWDCompare1:ClearAllPoints(); DWDCompare1:SetPoint("TOPLEFT", mainTT, "TOPRIGHT", COMPARE_X_PAD, COMPARE_Y_PAD)
    end
    if DWDCompare2:IsShown() then
      DWDCompare2:ClearAllPoints(); DWDCompare2:SetPoint("TOPLEFT", DWDCompare1, "TOPRIGHT", COMPARE_X_PAD, 0)
    end
  elseif placeLeft then
    if DWDCompare1:IsShown() then
      DWDCompare1:ClearAllPoints(); DWDCompare1:SetPoint("TOPRIGHT", mainTT, "TOPLEFT", -COMPARE_X_PAD, COMPARE_Y_PAD)
    end
    if DWDCompare2:IsShown() then
      DWDCompare2:ClearAllPoints(); DWDCompare2:SetPoint("TOPRIGHT", DWDCompare1, "TOPLEFT", -COMPARE_X_PAD, 0)
    end
  else
    if DWDCompare1:IsShown() then
      DWDCompare1:ClearAllPoints(); DWDCompare1:SetPoint("TOPLEFT", mainTT, "BOTTOMLEFT", 0, -8)
    end
    if DWDCompare2:IsShown() then
      DWDCompare2:ClearAllPoints(); DWDCompare2:SetPoint("TOPLEFT", DWDCompare1, "BOTTOMLEFT", 0, -8)
    end
  end
end

-- show compare tooltips; newObj can be a link (string) or a stats table
local function showOurCompare(mainTT, newObj, equipLocHint, statsHint, dispName)
  hideOurCompares()
  local equipLoc = equipLocHint
  if not equipLoc and type(newObj) == "string" then
    equipLoc = select(9, GetItemInfo(newObj))
  end
  if not equipLoc then return end
  local slots = slotsForEquipLoc(equipLoc); if not slots then return end

  local shown = 0
  for _, slot in ipairs(slots) do
    local oldLink = GetInventoryItemLink("player", slot)
    if oldLink and OUR_COMPARES[shown + 1] then
      shown = shown + 1
      local f = OUR_COMPARES[shown]
      f:SetOwner(mainTT, "ANCHOR_NONE")
      f._dwd_added = false; f._dwd_equippedHdr = false
      f:SetInventoryItem("player", slot)

      -- Mirror conditional class/form lines that ShoppingTooltip* usually gets
      ensureConditionalInfoShown(f, oldLink)

      addEquippedHeader(f)
      if SHOW_DELTAS_ON_COMPARE then
        appendWithRetry(f, statsHint or newObj, oldLink, dispName)
      end
      scrubYellowBlock(f)
      f:Show()
    end
  end
  layoutCompares(mainTT)
end

-- Kill Blizzard/Epoch compare path so we fully control it
GameTooltip_ShowCompareItem = function() end
for i = 1, 6 do
  local s = _G["ShoppingTooltip"..i]
  if s then s:HookScript("OnShow", function(self) self:Hide() end) end
end

------------------------------------------------------------
-- Hovering equipped slot? (suppress showing compares)
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

    -- Always mirror conditional class/form info onto the MAIN tooltip too
    ensureConditionalInfoShown(self, newLink)

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

  -- Recipe/trainer tooltips (no item link available)
  tt:HookScript("OnTooltipSetSpell", function(self)
    self._dwd_added = false
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
