local shell = require('shell')
local args = {...}
local branch
local repo
local scripts = {
    'action.lua ',
    'autoSpread.lua',
    'autoSpreadImpl.lua',
    'autoStat.lua',
    'autoStatImpl.lua',
    'autoTier.lua',
    'autoTierImpl.lua',
    'chestsorter.lua',
    'config.lua',
    'cunt.lua',
    'database.lua',
    'events.lua',
    'gps.lua',
    'scanner.lua',
    'transfer.lua',
    'uninstall.lua'
}

-- BRANCH
if #args >= 1 then
    branch = args[1]
else
    branch = 'main'
end

-- REPO
if #args >= 2 then
    repo = args[2]
else
    repo = 'https://raw.githubusercontent.com/tweelix/GTNH-CropAutomation/'
end

-- INSTALL
for i=1, #scripts do
    shell.execute(string.format('wget -f %s%s/%s', repo, branch, scripts[i]))
end
