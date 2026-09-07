local addon, ns = ...

local fuDelayEndTimer = nil

function Senkoh:GetCharConfig()
    return self.db and self.db.char
end

function Senkoh:NormalizeCharConfig()
    local c = self:GetCharConfig()
    if not c then return end
    c.aoeMode = c.aoeMode or 0
    c.cooldowns = c.cooldowns or 0
    c.dpsMode = c.dpsMode or 0
    c.delay = c.delay or 0
    c.potion = c.potion or 0
end

--- 通用角色开关：规范化、同步像素、刷新快捷按钮
function Senkoh:SwitchCharFlag(key, offMsg, onMsg, blockName)
    local c = self:GetCharConfig()
    if not c then return end
    if c[key] == 0 then
        print(offMsg)
    else
        print(onMsg)
    end
    if blockName and self.UpdateBareStateBlock then
        self:UpdateBareStateBlock(blockName, { "配置开关", "状态" })
    end
    self:NormalizeCharConfig()
    if self.RefreshQuickToggleAppearance then
        self:RefreshQuickToggleAppearance()
    end
end

function Senkoh:SwitchCooldown()
    self:SwitchCharFlag(
        "cooldowns",
        "|cff00ff00[Senkoh]|r 爆发已|cffff0000关闭|r",
        "|cff00ff00[Senkoh]|r 爆发已|cff00ff00开启|r",
        "爆发开关"
    )
end

function Senkoh:SwitchAoeMode()
    self:SwitchCharFlag(
        "aoeMode",
        "|cff00ff00[Senkoh]|r 已切换|cff00ff00自动|r模式！",
        "|cff00ff00[Senkoh]|r 已切换|cff00ff00单体|r模式！",
        "AOE开关"
    )
end

function Senkoh:SwitchPotion()
    self:SwitchCharFlag(
        "potion",
        "|cff00ff00[Senkoh]|r 药水已|cffff0000关闭|r",
        "|cff00ff00[Senkoh]|r 药水已|cff00ff00开启|r",
        "爆发药水开关"
    )
end

function Senkoh:SwitchDelay()
    local c = self:GetCharConfig()
    if not c then return end
    if self.UpdateBareStateBlock then
        self:UpdateBareStateBlock("延迟", { "配置开关", "状态" })
    end
    self:NormalizeCharConfig()
end

local fuTimerTicker = nil
local fuTimerElapsed = 0

function Senkoh:IsTimerRunning()
    return fuTimerTicker ~= nil
end

function Senkoh:GetTimerElapsed()
    return fuTimerElapsed
end

local function SyncTimerPixel()
    if Senkoh.UpdateStateBlock then
        Senkoh:UpdateStateBlock("特殊", "计时器")
    end
    if Senkoh.RefreshTimerAppearance then
        Senkoh:RefreshTimerAppearance()
    end
end

--- 开始（或重新开始）秒表：立即显示 0，之后每秒 +1；超过 255 秒自动关闭
function Senkoh:StartTimer()
    if fuTimerTicker then
        fuTimerTicker:Cancel()
        fuTimerTicker = nil
    end
    fuTimerElapsed = 0
    self.state.timer = 0
    SyncTimerPixel()
    print("|cff00ff00[Senkoh]|r 计时器已开启")
    fuTimerTicker = C_Timer.NewTicker(1, function()
        fuTimerElapsed = fuTimerElapsed + 1
        if fuTimerElapsed > 255 then
            Senkoh:StopTimer("overflow")
            return
        end
        Senkoh.state.timer = fuTimerElapsed / 255
        SyncTimerPixel()
    end)
end

--- reason == "overflow" 时使用超时文案；右击 / /se timer off 走默认关闭文案
function Senkoh:StopTimer(reason)
    if fuTimerTicker then
        fuTimerTicker:Cancel()
        fuTimerTicker = nil
    end
    fuTimerElapsed = 0
    self.state.timer = 0
    SyncTimerPixel()
    if reason == "overflow" then
        print("|cff00ff00[Senkoh]|r 计时器已超过 255 秒，已关闭")
    else
        print("|cff00ff00[Senkoh]|r 计时器已关闭")
    end
end

function Senkoh:ToggleTimer()
    if self:IsTimerRunning() then
        self:StopTimer()
    else
        self:StartTimer()
    end
end

local fuLoopTicker = nil
local fuLoopValue = 0
local fuLoopPeriod = 0

function Senkoh:IsLoopTimerRunning()
    return fuLoopTicker ~= nil
end

local function SyncLoopTimerPixel()
    if Senkoh.UpdateStateBlock then
        Senkoh:UpdateStateBlock("特殊", "循环计时器")
    end
end

--- 从 1 计到 period 再回到 1；period 钳在 1..255
function Senkoh:StartLoopTimer(period)
    period = math.floor(tonumber(period) or 0)
    if period < 1 then
        self:StopLoopTimer()
        return
    end
    if period > 255 then
        period = 255
    end
    if fuLoopTicker then
        fuLoopTicker:Cancel()
        fuLoopTicker = nil
    end
    fuLoopPeriod = period
    fuLoopValue = 1
    self.state.loopTimer = fuLoopValue / 255
    SyncLoopTimerPixel()
    print("|cff00ff00[Senkoh]|r 循环计时器已开启（1-" .. period .. " 秒）")
    fuLoopTicker = C_Timer.NewTicker(1, function()
        fuLoopValue = fuLoopValue + 1
        if fuLoopValue > fuLoopPeriod then
            fuLoopValue = 1
        end
        Senkoh.state.loopTimer = fuLoopValue / 255
        SyncLoopTimerPixel()
    end)
end

function Senkoh:StopLoopTimer()
    if fuLoopTicker then
        fuLoopTicker:Cancel()
        fuLoopTicker = nil
    end
    fuLoopValue = 0
    fuLoopPeriod = 0
    self.state.loopTimer = 0
    SyncLoopTimerPixel()
    print("|cff00ff00[Senkoh]|r 循环计时器已关闭")
end

function Senkoh:ToggleLoopTimer()
    if self:IsLoopTimerRunning() then
        self:StopLoopTimer()
    else
        self:StartLoopTimer(255)
    end
end

local function FindSpellListByName(spellName)
    local list = Senkoh.spellsList
    if not list then return nil end
    for spellId, info in pairs(list) do
        if type(info) == "table" and info.name == spellName and info.index then
            return info.index, spellId, info.name
        end
    end
    return nil
end

local function FindSpellListById(spellId)
    local list = Senkoh.spellsList
    if not list then return nil end
    local info = list[spellId]
    if type(info) == "table" and info.index and info.name then
        return info.index, spellId, info.name
    end
    return nil
end

local function FindItemListByName(itemName)
    local list = Senkoh.itemsList
    if not list then return nil end
    for itemId, info in pairs(list) do
        if type(info) == "table" and info.name == itemName and info.index then
            return info.index, itemId, info.name
        end
    end
    return nil
end

local function FindItemListById(itemId)
    local list = Senkoh.itemsList
    if not list then return nil end
    local info = list[itemId]
    if type(info) == "table" and info.index and info.name then
        return info.index, itemId, info.name
    end
    return nil
end

function Senkoh:InsertSpellCommand(rest)
    rest = strtrim(rest or "")
    if rest == "" then
        print("|cff00ff00[Senkoh]|r 用法: /se i 技能名称或spellId")
        return
    end

    local spellInput = rest

    local index, spellId, spellName
    if spellInput:match("^%d+$") then
        local requestedSpellId = tonumber(spellInput)
        if requestedSpellId and requestedSpellId > 0 then
            index, spellId, spellName = FindSpellListById(requestedSpellId)
        end
    else
        index, spellId, spellName = FindSpellListByName(spellInput)
    end

    if not index then
        print("|cff00ff00[Senkoh]|r 未在 spellsList 中找到技能: " .. spellInput)
        return
    end

    self:SetInsertSpell(index, spellName, spellId)
end

function Senkoh:InsertItemCommand(rest)
    rest = strtrim(rest or "")
    if rest == "" then
        print("|cff00ff00[Senkoh]|r 用法: /se t 物品名称或itemId")
        return
    end

    local itemInput = rest

    local index, itemId, itemName
    if itemInput:match("^%d+$") then
        local requestedItemId = tonumber(itemInput)
        if requestedItemId and requestedItemId > 0 then
            index, itemId, itemName = FindItemListById(requestedItemId)
        end
    else
        index, itemId, itemName = FindItemListByName(itemInput)
    end

    if not index then
        print("|cff00ff00[Senkoh]|r 未在 itemsList 中找到物品: " .. itemInput)
        return
    end

    self:SetInsertItem(index, itemName, itemId)
end

--- /se cd 系列命令统一动作：写 Senkoh.BurstTime 唯一真相 + 镜像 c.cooldowns + 打印
--- 含时长文案 + 刷新 stateblock「爆发开关」像素 + 刷新快捷按钮显示态（不调用 SwitchCooldown）
local function SetBurstTime(c, seconds, cooldown, text)
    Senkoh.BurstTime = GetTime() + seconds
    c.cooldowns = cooldown
    print(text)
    if Senkoh.UpdateBareStateBlock then
        Senkoh:UpdateBareStateBlock("爆发开关", { "配置开关", "状态" })
    end
    if Senkoh.RefreshQuickToggleAppearance then
        Senkoh:RefreshQuickToggleAppearance()
    end
end

function Senkoh:SlashCommand(input, editbox)
    input = strtrim(input or "")
    local command = string.lower(input)

    local c = self:GetCharConfig()
    if command == "cd" then
        if not c then return end
        SetBurstTime(c, 15, 1, "|cff00ff00[Senkoh]|r 爆发已开启（15 秒）")
    elseif command == "cd on" then
        if not c then return end
        SetBurstTime(c, 3600, 1, "|cff00ff00[Senkoh]|r 爆发已开启（3600 秒）")
    elseif command == "cd off" then
        if not c then return end
        SetBurstTime(c, -1, 0, "|cff00ff00[Senkoh]|r 爆发已关闭")
    elseif command:match("^cd%s+") then
        if not c then return end
        local secStr = command:match("^cd%s+(.+)$")
        local sec = tonumber(strtrim(secStr or ""))
        if not sec then
            print("|cff00ff00[Senkoh]|r 无效秒数；请输入数字（例如 /se cd 30），或使用 /se cd on / /se cd off。")
        elseif sec > 0 then
            SetBurstTime(c, sec, 1, "|cff00ff00[Senkoh]|r 爆发已开启（" .. sec .. " 秒）")
        else
            SetBurstTime(c, -1, 0, "|cff00ff00[Senkoh]|r 爆发已关闭")
        end
    elseif command == "aoemode" then
        if not c then return end
        c.aoeMode = (c.aoeMode == 0) and 1 or 0
        self:SwitchAoeMode()
    elseif command == "aoemode auto" then
        if not c then return end
        c.aoeMode = 0
        self:SwitchAoeMode()
    elseif command == "aoemode aoe" then
        if not c then return end
        c.aoeMode = 1
        self:SwitchAoeMode()
    elseif command == "potion" then
        if not c then return end
        c.potion = (c.potion == 0) and 1 or 0
        self:SwitchPotion()
    elseif command == "potion on" then
        if not c then return end
        c.potion = 1
        self:SwitchPotion()
    elseif command == "potion off" then
        if not c then return end
        c.potion = 0
        self:SwitchPotion()
    elseif command == "timer" then
        self:ToggleTimer()
    elseif command == "timer on" then
        self:StartTimer()
    elseif command == "timer off" then
        self:StopTimer()
    elseif command:match("^timer") then
        print("|cff00ff00[Senkoh]|r 用法: /se timer [on|off]")
    elseif command == "loop" then
        self:ToggleLoopTimer()
    elseif command == "loop on" then
        self:StartLoopTimer(255)
    elseif command == "loop off" then
        self:StopLoopTimer()
    elseif command:match("^loop%s+") then
        local secStr = command:match("^loop%s+(.+)$")
        local sec = tonumber(strtrim(secStr or ""))
        if not sec then
            print("|cff00ff00[Senkoh]|r 无效秒数；请输入 1-255（例如 /se loop 5），或使用 /se loop on / /se loop off。")
        elseif sec > 0 then
            self:StartLoopTimer(sec)
        else
            self:StopLoopTimer()
        end
    elseif command:match("^loop") then
        print("|cff00ff00[Senkoh]|r 用法: /se loop [on|off|秒数]")
    elseif command == "hide" then
        self:HideQuickToggleButton()
    elseif command == "show" then
        self:ShowQuickToggleButton()
    elseif command:match("^delay") then
        if not c then return end
        local secStr = command:match("^delay%s+(.+)$")
        local sec = 1
        if secStr then
            local trimmed = strtrim(secStr)
            if trimmed ~= "" then
                local parsed = tonumber(trimmed)
                if parsed and parsed > 0 then
                    sec = parsed
                else
                    print("|cff00ff00[Senkoh]|r 无效秒数；请输入正数（例如 /se delay 5），或不写秒数使用默认 1 秒。")
                    return
                end
            end
        end
        local delayAlreadyActive = fuDelayEndTimer ~= nil
        if fuDelayEndTimer then
            fuDelayEndTimer:Cancel()
            fuDelayEndTimer = nil
        end
        c.delay = 1
        self:SwitchDelay()
        fuDelayEndTimer = C_Timer.NewTimer(sec, function()
            fuDelayEndTimer = nil
            local cc = Senkoh:GetCharConfig()
            if cc then
                cc.delay = 0
                print("延迟已恢复。")
                Senkoh:SwitchDelay()
            end
        end)
        if not delayAlreadyActive then
            print("延迟已生效，" .. sec .. " 秒后恢复。")
        end
    elseif command == "i" or command:match("^i%s+") then
        -- 从原始 input 解析技能名或 spellId（保留中文技能名）
        local rest = input:match("^[iI]%s+(.*)$") or ""
        self:InsertSpellCommand(rest)
    elseif command == "t" or command:match("^t%s+") then
        -- 从原始 input 解析物品名或 itemId（保留中文物品名）
        local rest = input:match("^[tT]%s+(.*)$") or ""
        self:InsertItemCommand(rest)
    elseif command == "help" or command == "" then
        print("|cff00ff00Senkoh|r 命令列表:")
        print("爆发开关（开启 15 秒）: /se cd")
        print("|cff00ff00开启|r爆发（长计时 3600 秒）: /se cd on")
        print("|cffff0000关闭|r爆发: /se cd off")
        print("按秒开启爆发: /se cd xx（xx 为秒数，<=0 等同关闭）")
        print("切换AOE模式: /se aoemode")    
        print("切换AOE为|cff00ff00自动|r: /se aoemode auto")
        print("切换AOE为|cff00ff00单体|r: /se aoemode aoe")
        print("爆发药水开关: /se potion")
        print("|cff00ff00开启|r药水: /se potion on")
        print("|cffff0000关闭|r药水: /se potion off")
        print("切换计时器: /se timer")
        print("|cff00ff00开启|r计时器: /se timer on")
        print("|cffff0000关闭|r计时器: /se timer off")
        print("切换循环计时器（1-255 秒）: /se loop")
        print("|cff00ff00开启|r循环计时器（1-255 秒）: /se loop on")
        print("|cffff0000关闭|r循环计时器: /se loop off")
        print("按秒开启循环计时器: /se loop xx（xx 为 1-255，<=0 等同关闭）")
        print("隐藏快捷控件: /se hide")
        print("显示快捷控件: /se show")
        print("临时 delay 标志（db.char.delay 置 1 持续 x 秒后归零）: /se delay [秒]，省略秒数则为 1 秒")
        print("插入法术: /se i 技能名称或spellId")
        print("插入物品: /se t 物品名称或itemId")
        print("帮助: /se help")
    else
        print("输入 /se help 查看命令。")
    end
end
