local action = require('action')
local gps = require('gps')
local scanner = require('scanner')
local config = require('config')
local events = require('events')
local transfer = require('transfer')
local csort = require('chestsorter')
local sides = require('sides')

-- ===================== FUNCTIONS ======================


-- ====================== THE LOOP ======================

local function checkHarvest()
    local crop = scanner.scan()
    if crop.size >= crop.max - 1 then
        return true
    else
        print("Not fully Grown")
        os.sleep(0)
    end
end


local function cuntOnce()
    for slot=1, config.storageFarmArea, 1 do
        print(slot)

        -- Terminal Condition
        if events.needExit() then
            print('autoSpread: Received Exit Command!')
            return false
        end

        os.sleep(0)

        -- clean farm
        gps.go(gps.storageSlotToPos(slot))
        local tries = 0
        local crop = scanner.scan()
        if not crop.isCrop or crop.name == 'air' then
            print("Not a crop")
            os.sleep(0)
            goto continue
        end
        while not checkHarvest() do
            if tries >= config.maxHarvestTries then
                print('cunt: Plant is not Growing!')
                return false
            end
            tries = tries + 1
            gps.save()
            action.charge()
            os.sleep(config.harvestSleep)
            gps.resume()
            local cr = scanner.scan()
            if not cr.isCrop or cr.name == 'air' then
                print("Not a crop")
                os.sleep(0)
                goto continue
            end
        end
        action.harvestcunt()
        ::continue::
        if action.needCharge() then
            action.charge()
        end
    end
    action.dumpInventoryCunt()
    gps.go(config.tempSeedPos)
    csort.sortChest(sides.down)
    transfer.transferFirst(config.seedsToKeep, config.tempSeedPos, config.finalSeedPos)
    transfer.transferAll(config.tempSeedPos, config.finalSeedBin)
    return true
end

-- ======================== MAIN ========================

local function main()
    action.initWork()
    print('cunt: Scanning Farm')

    -- First Run
    local result = cuntOnce()
    if not result then
        print("Bad Result")
        action.restockAll()
        return false
    end
    action.restockAll()
    events.unhookEvents()
    print('cunt: Complete!')
end

main()