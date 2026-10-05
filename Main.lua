-- Main computer
-- Receivers keep using the same "angle;direction" decoder as before.

-- ===== CONFIG =====
local YAW_ID,   YAW_SIDE   = 2, "left"    -- Yaw controller computers ID and the side of the wireless modem
local PITCH_ID, PITCH_SIDE = 3, "right"   -- "" but pitch
local SEPARATOR = ";"                      -- must match the receivers

local CANNON = { x = 0, y = 64, z = 0 }   -- cannon block held by the mount
local POWER  = 4                           -- powder charges
local FACING = "east"                      -- cannon direction: east/north/west/south
local LENGTH = 5                           -- mount to tip length
local ARC    = 1                           -- 1 = low arc, 2 = high arc
local MIN_PITCH, MAX_PITCH = -30, 90       -- pitch limits of your cannon

local currentYaw, currentPitch = 0, 0      -- where the cannon points right now
-- ==================

rednet.open(YAW_SIDE)
rednet.open(PITCH_SIDE)

local function send(id, angle, direction)
    rednet.send(id, string.format("%.2f", angle) .. SEPARATOR .. direction)
end

-- ===== Ballistics =====

local function yield()  -- avoid "too long without yielding"
    os.queueEvent("yield")
    os.pullEvent("yield")
end

local function linspace(start, stop, num)
    local answer = { start }
    local delta = (stop - start) / num
    for _ = 1, num - 1 do
        answer[#answer + 1] = answer[#answer] + delta
    end
    answer[#answer + 1] = stop
    return answer
end

-- Returns airtime in ticks (tBelow, tAbove), or -1, -1 if it can't hit
local function timeInAir(y0, y, Vy)
    local t = 0
    local tBelow = 999999999

    if y0 <= y then
        while t < 100000 do
            y0 = y0 + Vy
            Vy = 0.99 * Vy - 0.05
            t = t + 1
            if y0 > y then
                tBelow = t - 1
                break
            end
            if Vy < 0 then return -1, -1 end
        end
    end

    while t < 100000 do
        y0 = y0 + Vy
        Vy = 0.99 * Vy - 0.05
        t = t + 1
        if y0 <= y then return tBelow, t end
    end
    return -1, -1
end

local function getRoot(tab, sens)
    if sens == 1 then
        for i = 2, #tab do
            if tab[i - 1][1] < tab[i][1] then return tab[i - 1] end
        end
        return tab[#tab]
    else
        for i = #tab - 1, 1, -1 do
            if tab[i][1] > tab[i + 1][1] then return tab[i + 1] end
        end
        return tab[1]
    end
end

local function trunc(x) return x >= 0 and math.floor(x) or math.ceil(x) end

-- Returns two solutions (low arc, high arc), or nil, errorMessage
local function ballistics(cannon, target, power, facing, length)
    local Dx, Dz = cannon.x - target.x, cannon.z - target.z
    local distance = math.sqrt(Dx * Dx + Dz * Dz)
    local initialSpeed = power * 2

    local yaw
    if Dx ~= 0 then yaw = math.atan(Dz / Dx) * 57.2957795131 else yaw = 90 end
    if Dx >= 0 then yaw = yaw + 180 end

    -- {deltaT, pitch, airtime} for one pitch, or nil if impossible
    local function evaluate(pitchDeg)
        local rad = math.rad(pitchDeg)
        local Vw = math.cos(rad) * initialSpeed
        local Vy = math.sin(rad) * initialSpeed
        local xCoord2d = length * math.cos(rad)

        local arg = 1 - (distance - xCoord2d) / (100 * Vw)
        if arg ~= arg or arg <= 0 then return nil end
        local timeToTarget = math.abs(math.log(arg) / (-0.010050335853501))

        local yEnd = cannon.y + math.sin(rad) * length
        local tBelow, tAbove = timeInAir(yEnd, target.y, Vy)
        if tBelow < 0 then return nil end

        local deltaT = math.min(math.abs(timeToTarget - tBelow),
                                math.abs(timeToTarget - tAbove))
        return { deltaT, pitchDeg, deltaT + timeToTarget }
    end

    local function scan(low, high, n)
        local list = {}
        for _, p in ipairs(linspace(low, high, n)) do
            local r = evaluate(p)
            if r then list[#list + 1] = r end
            yield()
        end
        if #list == 0 then
            error("The target is unreachable with your current cannon configuration!", 0)
        end
        return list
    end

    local function scanUnique(low, high, n)
        local best
        for _, r in ipairs(scan(low, high, n)) do
            if not best or r[1] < best[1] then best = r end
        end
        return best
    end

    local list = scan(MIN_PITCH, MAX_PITCH, MAX_PITCH - MIN_PITCH + 1)
    local s1, s2 = getRoot(list, 1), getRoot(list, -1)

    for i = 0, 4 do
        local w = 10 ^ (-i)
        s1 = scanUnique(s1[2] - w, s1[2] + w, 21)
        s2 = scanUnique(s2[2] - w, s2[2] + w, 21)
    end

    if facing == "north" then yaw = yaw + 90
    elseif facing == "west" then yaw = yaw + 180
    elseif facing == "south" then yaw = yaw + 270
    elseif facing ~= "east" then return nil, "Invalid direction" end
    yaw = yaw % 360

    local function pack(s)
        return {
            yaw = yaw,
            pitch = s[2],
            airtime = s[3],
            seconds = s[3] / 20,
            fuze = trunc(s[3] + s[1] / 2 - 10),
            precision = math.floor((1 - s[1] / s[3]) * 100 + 0.5),
            valid = s[1] <= 1 and s[2] >= MIN_PITCH - 0.5 and s[2] <= MAX_PITCH + 0.5,
        }
    end

    local low, high = pack(s1), pack(s2)
    -- if both searches landed on the same pitch there is only one arc
    if math.abs(low.pitch - high.pitch) < 0.5 then high.valid = false end
    return { low, high }
end

-- ===== Aiming =====

-- Signed shortest rotation -> angle to send + direction (1 or -1)
local function rotation(from, to, wrap)
    local d = to - from
    if wrap then d = (d + 540) % 360 - 180 end
    return math.abs(d), (d >= 0) and 1 or -1
end

local function aim(tx, ty, tz)
    local ok, sols, err = pcall(ballistics, CANNON, { x = tx, y = ty, z = tz }, POWER, FACING, LENGTH)
    if not ok then print(sols) return end
    if not sols then print(err) return end

    local s = sols[ARC]
    if not s.valid then
        local names = { "low", "high" }
        print("No " .. names[ARC] .. " arc for this target.")
        local other = sols[3 - ARC]
        if other.valid then
            print(string.format("The %s arc works: pitch %.2f", names[3 - ARC], other.pitch))
        end
        return
    end

    local yawAngle, yawDir = rotation(currentYaw, s.yaw, true)
    local pitchAngle, pitchDir = rotation(currentPitch, s.pitch, false)

    send(YAW_ID, yawAngle, yawDir)
    send(PITCH_ID, pitchAngle, pitchDir)
    currentYaw, currentPitch = s.yaw, s.pitch

    print(string.format("yaw %.2f  pitch %.2f  air %.2fs  fuze %d  precision %d%%",
        s.yaw, s.pitch, s.seconds, s.fuze, s.precision))
end

while true do
    write("Target x y z (blank to quit): ")
    local line = read()
    if not line or line == "" then break end
    local x, y, z = line:match("^%s*(-?[%d%.]+)%s+(-?[%d%.]+)%s+(-?[%d%.]+)%s*$")
    if x then aim(tonumber(x), tonumber(y), tonumber(z)) else print("Enter three numbers") end
end
