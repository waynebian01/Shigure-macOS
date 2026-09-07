local addon, ns = ...

local EnumPowerType = Senkoh.EnumPowerType
local curveCache = {}
local powerCurves = {}

function Senkoh:CreateColorCurve(point, b)
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    curve:AddPoint(0, CreateColor(0, 0, 0, 1))
    curve:AddPoint(point, CreateColor(0, 0, b / 255, 1))
    return curve
end

function Senkoh:CreateColorCurveScaling(b)
    if curveCache[b] then
        return curveCache[b]
    end
    local curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    if b > 100 then
        curve:AddPoint(0, CreateColor(0, 0, (b - 100) / 255, 1))
        curve:AddPoint(1, CreateColor(0, 0, b / 255, 1))
    else
        local z = (100 - b) / 100
        curve:AddPoint(0, CreateColor(0, 0, 0, 1))
        curve:AddPoint(z, CreateColor(0, 0, 1 / 255, 1))
        curve:AddPoint(1, CreateColor(0, 0, b / 255, 1))
    end
    curveCache[b] = curve
    return curve
end

function Senkoh:CreatePowerCurve(powerType)
    if powerCurves[powerType] then return end
    local powerMax = UnitPowerMax("player", EnumPowerType[powerType])
    if powerMax >= 250 then
        powerCurves[powerType] = self:CreateColorCurve(1, 100)
    else
        powerCurves[powerType] = self:CreateColorCurve(1, powerMax)
    end
end

Senkoh.powerCurves = powerCurves

-- 队伍生命曲线必须在进入战斗前创建。战斗中只选择既有曲线，
-- 避免首次施放对应治疗法术时临时调用 C_CurveUtil.CreateColorCurve。
Senkoh.curve100 = Senkoh:CreateColorCurveScaling(100)
Senkoh.groupHealthCurves = {
    default = Senkoh.curve100,
    incoming15 = Senkoh:CreateColorCurveScaling(115),
    incoming40 = Senkoh:CreateColorCurveScaling(140),
}
Senkoh.curve255 = Senkoh:CreateColorCurve(255, 255)
Senkoh.castCurve = Senkoh:CreateColorCurve(25.5, 255)
Senkoh.curveMs = Senkoh:CreateColorCurve(2.55, 255)
