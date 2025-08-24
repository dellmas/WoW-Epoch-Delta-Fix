-- DWD Tooltip Delta Fix (WotLK 3.3.5)
-- MIT License — Copyright (c) 2025 dellmas
-- See LICENSE file in this repository for full text.
-- • No Blizzard/Epoch ShoppingTooltip (no yellow block/flicker)
-- • Deltas only on compare tooltips (not the hovered/main tooltip)
-- • "Currently Equipped" header on compare tooltips
-- • Neat side-by-side layout, clamped on-screen
-- • NEW: Suppress compare tooltips when hovering equipped slots

------------------------------------------------------------
-- Config
------------------------------------------------------------
local ALWAYS_SHOW_COMPARE     = true    -- show our compare tooltips without Shift
local SHOW_DELTAS_ON_MAIN     = false   -- keep main tooltip clean
local SHOW_DELTAS_ON_COMPARE  = true
local SUPPRESS_WHEN_HOVERING_EQUIPPED = true  -- << new

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
-- Read stats
------------------------------------------------------------
local function getStats(link)
  local st = { ARMOR=0, DPS=nil, STR=0, AGI=0, STA=0, INT=0, SPI=0 }
  if not link then return st end
  scan:ClearLines(); scan:SetHyperlink(link)
  local minD, maxD, spd
  for i = 2, scan:NumLines() do
    local s = _G["DWDScanTTTextLeft"..i]:GetText()
    if s then
      local lower = s:lower()
      local a = lower:match("([%d,]+)%s*armor"); if a then st.ARMOR = tonum(a) or st.ARMOR end
      local v = lower:match("%+(%d+)%s+strength"); if v then st.STR = st.STR + tonumber(v) end
      v = lower:match("%+(%d+)%s+agility");        if v then st.AGI = st.AGI + tonumber(v) end
      v = lower:match("%+(%d+)%s+stamina");        if v then st.STA = st.STA + tonumber(v) end
      v = lower:match("%+(%d+)%s+intellect");      if v then st.INT = st.INT + tonumber(v) end
      v = lower:match("%+(%d+)%s+spirit");         if v then st.SPI = st.SPI + tonumber(v) end
      local dps = lower:match("%(([%d%.]+)%s*damage per second%)")
      if dps then st.DPS = tonumber(dps) end
      local d1, d2 = lower:match("(%d+)%s*%-%s*(%d+)%s*damage"); if d1 and d2 then minD, maxD = tonumber(d1), tonumber(d2) end
      local sp = lower:match("speed%s*([%d%.]+)"); if sp then spd = tonumber(sp) end
    end
  end
  if not st.DPS and minD and maxD and spd and spd > 0 then
    st.DPS = ((minD + maxD) / 2) / spd
  end
  return st
end

------------------------------------------------------------
-- Deltas
------------------------------------------------------------
local function addDeltaLine(tt, label, delta, isFloat)
  if delta == nil or delta == 0 then return end
  if isFloat then delta = tonumber(string.format("%.1f", delta)) end
  local r,g,b = (delta < 0) and 1 or 0, (delta < 0) and 0 or 1, 0
  local fmt = isFloat and "%+.1f %s" or "%+d %s"
  tt:AddLine(string.format(fmt, delta, label), r,g,b)
end
local function appendCorrectDeltas(tt, newLink, oldLink)
  if tt._dwd_added or not newLink then return end
  if oldLink and itemID(newLink) == itemID(oldLink) then return end
  local N, O = getStats(newLink), getStats(oldLink)
  tt:AddLine("Correct stat changes if equipped:", 1, 0.82, 0)
  addDeltaLine(tt, "Armor", (N.ARMOR or 0) - (O.ARMOR or 0), false)
  addDeltaLine(tt, "Damage Per Second", (N.DPS or 0) - (O.DPS or 0), true)
  addDeltaLine(tt, "Strength", (N.STR or 0) - (O.STR or 0), false)
  addDeltaLine(tt, "Agility",  (N.AGI or 0) - (O.AGI or 0), false)
  addDeltaLine(tt, "Stamina",  (N.STA or 0) - (O.STA or 0), false)
  addDeltaLine(tt, "Intellect",(N.INT or 0) - (O.INT or 0), false)
  addDeltaLine(tt, "Spirit",   (N.SPI or 0) - (O.SPI or 0), false)
  tt._dwd_added = true; tt:Show()
end

------------------------------------------------------------
-- Remove only the yellow block
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
          else break end
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

-- layout
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

local function showOurCompare(mainTT, newLink)
  hideOurCompares()
  if not newLink then return end
  local equipLoc = select(9, GetItemInfo(newLink))
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
      addEquippedHeader(f)
      if SHOW_DELTAS_ON_COMPARE then appendCorrectDeltas(f, newLink, oldLink) end
      scrubYellowBlock(f)
      f:Show()
    end
  end
  layoutCompares(mainTT)
end

-- kill Blizzard/Epoch compare path
GameTooltip_ShowCompareItem = function() end
for i = 1, 6 do local s = _G["ShoppingTooltip"..i]; if s then s:HookScript("OnShow", function(self) self:Hide() end) end end

------------------------------------------------------------
-- Helper: detect "hovering equipped"
------------------------------------------------------------
local CharacterFrame = CharacterFrame  -- available in 3.3.5
local function isChildOf(frame, root)
  while frame do if frame == root then return true end frame = frame:GetParent() end
  return false
end
local function isHoveringEquippedSlot(tt, link)
  if not SUPPRESS_WHEN_HOVERING_EQUIPPED then return false end
  local owner = tt:GetOwner() or GetMouseFocus()
  local name = owner and owner.GetName and owner:GetName()
  -- Fast path: CharacterXSlot buttons
  if name and name:match("^Character.+Slot$") then return true end
  -- Fallback: same itemID as something worn AND the owner lives under CharacterFrame
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
-- Main tooltip patch
------------------------------------------------------------
local function patchGameTooltip(tt)
  if not tt or tt._dwd_patched then return end
  tt._dwd_patched = true
  tt:SetClampedToScreen(true)

  tt:HookScript("OnTooltipCleared", function(self) self._dwd_added = false end)

  tt:HookScript("OnTooltipSetItem", function(self)
    self._dwd_added = false
    local _, newLink = self:GetItem(); if not newLink then return end

    if SHOW_DELTAS_ON_MAIN then
      local equipLoc = select(9, GetItemInfo(newLink))
      local slots = slotsForEquipLoc(equipLoc)
      local oldLink = slots and GetInventoryItemLink("player", slots[1]) or nil
      appendCorrectDeltas(self, newLink, oldLink)
    end

    -- NEW: skip compare if we're hovering an equipped slot
    if ALWAYS_SHOW_COMPARE and not isHoveringEquippedSlot(self, newLink) then
      showOurCompare(self, newLink)
    else
      hideOurCompares()
    end

    scrubYellowBlock(self)
  end)
end

patchGameTooltip(GameTooltip)
patchGameTooltip(ItemRefTooltip)
