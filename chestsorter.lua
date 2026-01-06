-- crop_chest_sorter.lua
-- OpenComputers (drone + inventory_controller) chest sorter for crop-sticks metadata.
--
-- Exports: sorter.sortChest(side)
-- Usage:
--   local sorter = require("crop_chest_sorter")
--   sorter.config.bufferA = 1
--   sorter.config.bufferB = 2
--   local ok, err = sorter.sortChest(sides.front)
--   if not ok then print("Sort failed:", err) end

local component = require("component")
local inv = component.inventory_controller
local robot = require('robot')

local M = {}

-- Configure these in your main program if you want.
M.config = {
  -- Two INTERNAL drone inventory slots reserved as buffers.
  -- These MUST be empty before calling sortChest.
  bufferA = 1,
  bufferB = 2,

  -- If true, items that don't have stack.crop metadata are sorted after crop items.
  -- If false, they are still included, but tie-breakers might look odd.
  nonCropLast = true,
}

local function validateDroneBuffers(bufA, bufB)
  if type(bufA) ~= "number" or type(bufB) ~= "number" then
    return false, "bufferA/bufferB must be numbers"
  end
  if bufA ~= math.floor(bufA) or bufB ~= math.floor(bufB) then
    return false, "bufferA/bufferB must be integers"
  end
  if bufA == bufB then
    return false, "buffer slots must be different"
  end

  local invSize = robot.inventorySize()
  if bufA < 1 or bufA > invSize or bufB < 1 or bufB > invSize then
    return false, "buffer slot index out of range (drone inventory size is " .. tostring(invSize) .. ")"
  end

  if robot.count(bufA) ~= 0 then
    return false, "drone buffer slot " .. bufA .. " is not empty"
  end
  if robot.count(bufB) ~= 0 then
    return false, "drone buffer slot " .. bufB .. " is not empty"
  end

  return true
end

-- Crop ordering:
-- 1) score = gain + growth - resistance (DESC)
-- 2) resistance (ASC)
-- 3) crop name (ASC)
-- 4) deterministic fallback on item name / damage
-- Crop ordering (UPDATED):
-- 1) crop name (ASC)
-- 2) score = gain + growth - resistance (DESC)
-- 3) resistance (ASC)
-- 4) deterministic fallback on item name / damage
local function cropLess(a, b, nonCropLast)
  local ac, bc = a.crop, b.crop

  if ac == nil and bc == nil then
    -- both non-crop (or missing metadata): fall back deterministically
    local an = tostring(a.name or "")
    local bn = tostring(b.name or "")
    if an ~= bn then return an < bn end
    return (tonumber(a.damage) or 0) < (tonumber(b.damage) or 0)
  end

  if ac == nil then
    return not nonCropLast -- if nonCropLast=true, non-crops go after crops
  end
  if bc == nil then
    return nonCropLast
  end

  local aname  = tostring(ac.name or "")
  local bname  = tostring(bc.name or "")

  if aname ~= bname then
    return aname < bname -- name first
  end

  local again  = tonumber(ac.gain) or 0
  local agrow  = tonumber(ac.growth) or 0
  local ares   = tonumber(ac.resistance) or 0

  local bgain  = tonumber(bc.gain) or 0
  local bgrow  = tonumber(bc.growth) or 0
  local bres   = tonumber(bc.resistance) or 0

  local ascore = again + agrow - ares
  local bscore = bgain + bgrow - bres

  if ascore ~= bscore then return ascore > bscore end -- higher score first
  if ares   ~= bres   then return ares   < bres   end -- lower resistance first

  -- final deterministic fallback (so comparator is strict/consistent)
  local inA = tostring(a.name or "")
  local inB = tostring(b.name or "")
  if inA ~= inB then return inA < inB end
  return (tonumber(a.damage) or 0) < (tonumber(b.damage) or 0)
end


-- Move entire stack from chest slot `fromSlot` to chest slot `toSlot` using drone buffer `buf`.
-- Precondition: `toSlot` must be empty.
local function moveStack(side, fromSlot, toSlot, buf)
  local s = inv.getStackInSlot(side, fromSlot)
  if not s then return true end

  robot.select(buf)
  if robot.count(buf) ~= 0 then
    return false, "drone buffer " .. buf .. " not empty"
  end

  -- Pull whole stack into drone buffer
  if not inv.suckFromSlot(side, fromSlot, s.size) then
    return false, "failed to suckFromSlot(" .. tostring(fromSlot) .. ")"
  end

  -- Drop into empty destination slot
  local ok, err = inv.dropIntoSlot(side, toSlot, s.size)
  if not ok then
    -- try to put it back (best-effort)
    inv.dropIntoSlot(side, fromSlot, s.size)
    return false, err or ("failed to dropIntoSlot(" .. tostring(toSlot) .. ")")
  end

  return true
end

-- Swap chest slots a and b using TWO empty drone buffer slots (no empty chest slot needed).
local function swapChestSlots2(side, a, b, bufA, bufB)
  if a == b then return true end

  local sa = inv.getStackInSlot(side, a)
  local sb = inv.getStackInSlot(side, b)

  if not sa and not sb then return true end
  if not sa then return moveStack(side, b, a, bufA) end
  if not sb then return moveStack(side, a, b, bufA) end

  -- A -> bufA
  robot.select(bufA)
  if robot.count(bufA) ~= 0 then return false, "bufferA not empty" end
  if not inv.suckFromSlot(side, a, sa.size) then
    return false, "failed to suck slot " .. tostring(a)
  end

  -- B -> bufB
  robot.select(bufB)
  if robot.count(bufB) ~= 0 then
    -- rollback: put A back
    robot.select(bufA)
    inv.dropIntoSlot(side, a, sa.size)
    return false, "bufferB not empty"
  end
  if not inv.suckFromSlot(side, b, sb.size) then
    -- rollback: put A back
    robot.select(bufA)
    inv.dropIntoSlot(side, a, sa.size)
    return false, "failed to suck slot " .. tostring(b)
  end

  -- bufA -> B (B is empty now)
  robot.select(bufA)
  local ok1, err1 = inv.dropIntoSlot(side, b, sa.size)
  if not ok1 then
    -- rollback attempt
    robot.select(bufA); inv.dropIntoSlot(side, a, sa.size)
    robot.select(bufB); inv.dropIntoSlot(side, b, sb.size)
    return false, err1 or "failed to drop A into B"
  end

  -- bufB -> A (A is empty now)
  robot.select(bufB)
  local ok2, err2 = inv.dropIntoSlot(side, a, sb.size)
  if not ok2 then
    -- rollback attempt
    robot.select(bufB); inv.dropIntoSlot(side, b, sb.size)
    return false, err2 or "failed to drop B into A"
  end

  return true
end

-- Public: sortChest(side)
-- Sorts ALL non-empty slots in the inventory on `side` by crop metadata ordering.
-- Result: best crops end up packed into slots 1..m; empties will be after.
function M.sortChest(side)
  local chestSize, reason = inv.getInventorySize(side)
  if not chestSize then
    return false, reason or "no inventory found on that side"
  end

  local bufA = M.config.bufferA
  local bufB = M.config.bufferB
  local ok, err = validateDroneBuffers(bufA, bufB)
  if not ok then return false, "startup buffer check failed: " .. err end

  -- Snapshot current chest contents
  local items = {}     -- { id, slot, stack }
  local slotToId = {}  -- slot -> id or 0

  for slot = 1, chestSize do
    local st = inv.getStackInSlot(side, slot)
    if st then
      local id = #items + 1
      items[id] = { id = id, slot = slot, stack = st }
      slotToId[slot] = id
    else
      slotToId[slot] = 0
    end
  end

  -- Sort by crop rules
  table.sort(items, function(x, y)
    return cropLess(x.stack, y.stack, M.config.nonCropLast)
  end)

  -- desiredId[targetSlot] says which item-id we want in that slot
  local m = #items
  local desiredId = {}
  for i = 1, m do desiredId[i] = items[i].id end

  -- idToSlot[id] = current chest slot of that item-id
  local idToSlot = {}
  for _, it in ipairs(items) do idToSlot[it.id] = it.slot end

  -- Place items into slots 1..m via swaps
  for targetSlot = 1, m do
    local want = desiredId[targetSlot]
    local cur = idToSlot[want]
    if cur ~= targetSlot then
      local okSwap, errSwap = swapChestSlots2(side, targetSlot, cur, bufA, bufB)
      if not okSwap then return false, errSwap end

      -- Update mappings (we swapped the CONTENTS of targetSlot and cur)
      local idA = slotToId[targetSlot]
      local idB = slotToId[cur]
      slotToId[targetSlot], slotToId[cur] = idB, idA

      if slotToId[targetSlot] ~= 0 then idToSlot[slotToId[targetSlot]] = targetSlot end
      if slotToId[cur] ~= 0 then idToSlot[slotToId[cur]] = cur end

      -- Optional safety: ensure buffers stayed empty after swap
      if robot.count(bufA) ~= 0 or robot.count(bufB) ~= 0 then
        return false, "buffer slots not empty after swap (check for partial transfers)"
      end
    end
  end

  return true
end

return M
