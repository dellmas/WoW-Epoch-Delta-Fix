-- DWD_TooltipDeltaFix_ElvUI (plugin for DWD Tooltip Delta Fix) (WotLK 3.3.5)
-- • Adds ElvUI skinning for compare tooltips when ElvUI is present (no ElvUI requirement)
-- • Adds retail-like anchoring so compare panes extend toward screen center
-- • Adds optional Shift-to-show gating for comparisons (config below)
-- • Non-invasive: original addon code remains untouched; hooks live in this plugin
-- • Requires: DWD_TooltipDeltaFix; Optional: ElvUI; Load order guaranteed via TOC

------------------------------------------------------------
-- Config (edit as desired)
------------------------------------------------------------
local REQUIRE_SHIFT   = true   -- if true, comparisons only show while holding Shift
local PADDING_X       = 0      -- horizontal gap between main tooltip and first compare pane
local PADDING_Y       = -10    -- vertical alignment offset for top edges
local SCREEN_MARGIN   = 12     -- minimum margin from screen edges
local TICK_INTERVAL   = 0.08   -- re-assert anchoring while tooltips are visible

------------------------------------------------------------
-- Utility: references to frames from the base addon
------------------------------------------------------------
local function GetCompareFrames()
  return _G.DWDCompareTooltip1, _G.DWDCompareTooltip2
end

local function GetMainTooltip()
  local c1, c2 = GetCompareFrames()
  if c1 and c1:IsShown() then
    local o = c1:GetOwner()
    if o and o.IsShown and o:IsShown() then return o end
  end
  if c2 and c2:IsShown() then
    local o = c2:GetOwner()
    if o and o.IsShown and o:IsShown() then return o end
  end
  if GameTooltip and GameTooltip:IsShown() then return GameTooltip end
  if ItemRefTooltip and ItemRefTooltip:IsShown() then return ItemRefTooltip end
  return nil
end

------------------------------------------------------------
-- ElvUI skin support (safe, optional)
------------------------------------------------------------
local function TryHookElvUISkin()
  local E  = type(_G.ElvUI) == "table" and _G.ElvUI[1] or nil
  local TT = E and E.GetModule and E:GetModule("Tooltip", true)
  if not (TT and TT.SetStyle) then return end

  local c1, c2 = GetCompareFrames()
  if c1 and not c1.__dwd_elvui_skind then
    c1:HookScript("OnShow", function(self) TT:SetStyle(self) end)
    c1.__dwd_elvui_skind = true
  end
  if c2 and not c2.__dwd_elvui_skind then
    c2:HookScript("OnShow", function(self) TT:SetStyle(self) end)
    c2.__dwd_elvui_skind = true
  end
end

------------------------------------------------------------
-- Retail-like anchoring (prefer “toward center”, with fallbacks)
------------------------------------------------------------
local function AnchorComparesTowardCenter()
  local c1, c2 = GetCompareFrames()
  if not c1 and not c2 then return end
  if (not c1 or not c1:IsShown()) and (not c2 or not c2:IsShown()) then return end

  local main = GetMainTooltip()
  if not main or not main:IsShown() then return end

  local uiW   = UIParent:GetWidth()
  local left  = main:GetLeft()  or 0
  local right = main:GetRight() or 0

  local w1 = (c1 and c1:IsShown()) and (c1:GetWidth() or 0) or 0
  local w2 = (c2 and c2:IsShown()) and (c2:GetWidth() or 0) or 0
  local panes = ((c1 and c1:IsShown()) and 1 or 0) + ((c2 and c2:IsShown()) and 1 or 0)

  -- Conservative estimate to reduce early-frame jitter
  local approx = (panes > 0) and (180 * panes + (panes > 1 and PADDING_X or 0)) or 0
  local total  = math.max(w1 + ((w2 > 0 and (PADDING_X + w2)) or 0), approx)

  local spaceRight = uiW - right - SCREEN_MARGIN
  local spaceLeft  = left - SCREEN_MARGIN

  local center        = (left + right) / 2
  local screenCenter  = uiW / 2
  local inwardIsRight = center < screenCenter

  local function placeRight()
    if c1 and c1:IsShown() then
      c1:ClearAllPoints()
      c1:SetPoint("TOPLEFT", main, "TOPRIGHT", PADDING_X, PADDING_Y)
    end
    if c2 and c2:IsShown() then
      c2:ClearAllPoints()
      c2:SetPoint("TOPLEFT", c1, "TOPRIGHT", PADDING_X, 0)
    end
  end

  local function placeLeft()
    if c1 and c1:IsShown() then
      c1:ClearAllPoints()
      c1:SetPoint("TOPRIGHT", main, "TOPLEFT", -PADDING_X, PADDING_Y)
    end
    if c2 and c2:IsShown() then
      c2:ClearAllPoints()
      c2:SetPoint("TOPRIGHT", c1, "TOPLEFT", -PADDING_X, 0)
    end
  end

  local function placeBelow()
    if c1 and c1:IsShown() then
      c1:ClearAllPoints()
      c1:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -8)
    end
    if c2 and c2:IsShown() then
      c2:ClearAllPoints()
      c2:SetPoint("TOPLEFT", c1, "BOTTOMLEFT", 0, -8)
    end
  end

  -- Inward first, then outward, then below
  if inwardIsRight then
    if spaceRight >= total then
      placeRight()
    elseif spaceLeft >= total then
      placeLeft()
    else
      placeBelow()
    end
  else
    if spaceLeft >= total then
      placeLeft()
    elseif spaceRight >= total then
      placeRight()
    else
      placeBelow()
    end
  end
end

------------------------------------------------------------
-- Ticker to keep anchors fresh while tooltips are visible
------------------------------------------------------------
local TickerFrame, accum = CreateFrame("Frame"), 0
TickerFrame:Hide()
TickerFrame:SetScript("OnUpdate", function(_, elapsed)
  accum = accum + elapsed
  if accum >= TICK_INTERVAL then
    accum = 0
    AnchorComparesTowardCenter()
  end
  local c1, c2 = GetCompareFrames()
  if (not c1 or not c1:IsShown()) and (not c2 or not c2:IsShown()) then
    TickerFrame:Hide()
  end
end)

------------------------------------------------------------
-- Shift gating (hide compare panes unless Shift is down)
------------------------------------------------------------
local function GateOnShowByShift(self)
  if not REQUIRE_SHIFT then return end
  if not IsShiftKeyDown() then
    self.__dwd_hidden_by_shift = true
    self:Hide()
  else
    self.__dwd_hidden_by_shift = false
  end
end

local function HookCompareVisibility()
  local c1, c2 = GetCompareFrames()
  if c1 and not c1.__dwd_vis_hooked then
    c1:HookScript("OnShow", function(self)
      -- Gate by Shift
      GateOnShowByShift(self)
      if not self:IsShown() then return end
      -- Style + place
      TryHookElvUISkin()
      AnchorComparesTowardCenter()
      TickerFrame:Show()
    end)
    c1:HookScript("OnHide", function(self)
      self.__dwd_hidden_by_shift = self.__dwd_hidden_by_shift or false
    end)
    c1.__dwd_vis_hooked = true
  end

  if c2 and not c2.__dwd_vis_hooked then
    c2:HookScript("OnShow", function(self)
      GateOnShowByShift(self)
      if not self:IsShown() then return end
      TryHookElvUISkin()
      AnchorComparesTowardCenter()
      TickerFrame:Show()
    end)
    c2:HookScript("OnHide", function(self)
      self.__dwd_hidden_by_shift = self.__dwd_hidden_by_shift or false
    end)
    c2.__dwd_vis_hooked = true
  end
end

-- React to Shift pressed/released and toggle our compare panes
local ShiftWatcher = CreateFrame("Frame")
ShiftWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
ShiftWatcher:SetScript("OnEvent", function(_, _, key)
  if not REQUIRE_SHIFT then return end
  if key ~= "LSHIFT" and key ~= "RSHIFT" and key ~= "SHIFT" then return end

  local c1, c2 = GetCompareFrames()
  local anyShown = false

  if IsShiftKeyDown() then
    if c1 and c1.__dwd_hidden_by_shift and not c1:IsShown() then
      c1.__dwd_hidden_by_shift = false
      c1:Show()
      anyShown = true
    end
    if c2 and c2.__dwd_hidden_by_shift and not c2:IsShown() then
      c2.__dwd_hidden_by_shift = false
      c2:Show()
      anyShown = true
    end
    if anyShown then
      TryHookElvUISkin()
      AnchorComparesTowardCenter()
      TickerFrame:Show()
    end
  else
    if c1 and c1:IsShown() then
      c1.__dwd_hidden_by_shift = true
      c1:Hide()
    end
    if c2 and c2:IsShown() then
      c2.__dwd_hidden_by_shift = true
      c2:Hide()
    end
  end
end)

------------------------------------------------------------
-- Initialization (runs after DWD_TooltipDeltaFix due to TOC dependency)
------------------------------------------------------------
local function Initialize()
  -- If the base addon isn’t present (shouldn’t happen due to RequiredDeps), bail out.
  if not (GetAddOnInfo and IsAddOnLoaded and IsAddOnLoaded("DWD_TooltipDeltaFix")) then
    return
  end

  TryHookElvUISkin()
  HookCompareVisibility()

  -- Also re-anchor when the main tooltip re-appears or moves
  if GameTooltip and not GameTooltip.__dwd_anchor_hooked then
    GameTooltip:HookScript("OnShow", AnchorComparesTowardCenter)
    GameTooltip:HookScript("OnUpdate", AnchorComparesTowardCenter)
    GameTooltip.__dwd_anchor_hooked = true
  end
  if ItemRefTooltip and not ItemRefTooltip.__dwd_anchor_hooked then
    ItemRefTooltip:HookScript("OnShow", AnchorComparesTowardCenter)
    ItemRefTooltip:HookScript("OnUpdate", AnchorComparesTowardCenter)
    ItemRefTooltip.__dwd_anchor_hooked = true
  end
end

-- Attempt to initialize immediately (most cases). If compare frames are not yet created,
-- retry on PLAYER_LOGIN (paranoid fallback for unusual load orders).
local c1, c2 = GetCompareFrames()
if c1 or c2 then
  Initialize()
else
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LOGIN")
  f:SetScript("OnEvent", function()
    Initialize()
    f:UnregisterEvent("PLAYER_LOGIN")
  end)
end