local addon, ns = ...

local state = Senkoh.state
local BOSS_UNIT_COUNT = 5

function Senkoh:IsBossUnit(unit)
    return type(unit) == "string" and unit:match("^boss[1-5]$") ~= nil
end

function Senkoh:RefreshBossUnitStates()
    for index = 1, BOSS_UNIT_COUNT do
        local unit = "boss" .. index
        self:RefreshUnitState(unit)
        self:RefreshUnitRangeState(unit)
    end
end

function Senkoh:RefreshBossReactionAndRangeStates()
    for index = 1, BOSS_UNIT_COUNT do
        local unit = "boss" .. index
        self:RefreshUnitReactionState(unit)
        self:RefreshUnitRangeState(unit)
    end
end

function Senkoh:RefreshBossCastStateBlocks(refreshSafely)
    for index = 1, BOSS_UNIT_COUNT do
        local unit = "boss" .. index
        if refreshSafely then
            refreshSafely(self, "RefreshUnitCastStateBlocks", unit)
        else
            self:RefreshUnitCastStateBlocks(unit)
        end
    end
end

function Senkoh:SetEncounterState(encounterID, difficultyID)
    state.encounterID = encounterID
    local bossIndex = self.bossID and self.bossID[encounterID] or 0
    state.bossID = bossIndex / 255
    self:UpdateStateBlock("状态", "首领战")

    state.difficultyID = difficultyID
    self:UpdateStateBlock("状态", "难度")
end
