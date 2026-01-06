local component = require("component")
local robot = require("robot")
local sides = require("sides")
local gps = require("gps")
local action = require("action")

local ic = component.inventory_controller

local function transferFirst(n, from, to)
  if type(n) ~= "number" or n < 0 then
    error("n must be a non-negative number")
  end
  if n == 0 then return 0 end

  local moved = 0

  gps.go(from)
  local invSize = ic.getInventorySize(sides.down)
  if not invSize then error("No inventory below the robot at source position") end

  local srcSlot = 1
  local usedRobotSlots = 0 -- == number of distinct source slots we pulled from this batch

  while moved < n and srcSlot <= invSize do
    os.sleep(0)

    local stack = ic.getStackInSlot(sides.down, srcSlot)
    if not stack or stack.size <= 0 then
      srcSlot = srcSlot + 1
    else
      -- If we've already used 8 robot slots in this batch, ferry now.
      if usedRobotSlots >= 8 then
        gps.save()
        action.dumpInventorypos(to)
        gps.resume()
        usedRobotSlots = 0
      end

      -- Pull from this source slot.
      -- We'll try to take as many as possible towards the remaining item count.
      local remaining = n - moved
      local take = stack.size
      if take > remaining then take = remaining end

      -- select a "batch slot" (1..8); your rule says each source slot maps to one robot slot
      robot.select(usedRobotSlots + 1)

      local ok = ic.suckFromSlot(sides.down, srcSlot, take)
      if ok then
        moved = moved + take
        usedRobotSlots = usedRobotSlots + 1
        -- keep srcSlot the same: it might still have items, but under your rule
        -- we don't want to use a 9th robot slot for the same source slot,
        -- so we only ever count/take from a given source slot once per batch.
        srcSlot = srcSlot + 1
      else
        -- couldn't pull from this slot; skip it
        srcSlot = srcSlot + 1
      end
    end
  end

  -- Dump any remainder we carried
  if usedRobotSlots > 0 then
    action.dumpInventorypos(to)
  end

  return moved
end

local function transferAll(from, to)
  while true do
    gps.go(from)

    local invSize = ic.getInventorySize(sides.down)
    if not invSize then error("No inventory below the robot at source position") end

    local used = 0
    local pulledAnything = false

    -- Pull from up to 8 source slots per trip
    for srcSlot = 1, invSize do
      os.sleep(0)
      if used >= 8 then break end

      local stack = ic.getStackInSlot(sides.down, srcSlot)
      if stack and stack.size and stack.size > 0 then
        used = used + 1
        robot.select(used) -- 1..8

        -- take the whole stack from this source slot
        local ok = ic.suckFromSlot(sides.down, srcSlot, stack.size)
        if ok then
          pulledAnything = true
        end
      end
    end

    -- If we couldn't pull anything this pass, source is empty (or inaccessible)
    if not pulledAnything then
      return
    end

    -- Dump and repeat
    action.dumpInventorypos(to)
  end
end

return { transferFirst = transferFirst,
transferAll = transferAll}
