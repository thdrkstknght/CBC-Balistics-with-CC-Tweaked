-- ===== CONFIG =====
local SEPARATOR = ";"
-- ==================

rednet.open("back")

local angle, direction

while true do
    local senderId, message = rednet.receive()

    local a, d = message:match("^(-?[%d%.]+)" .. SEPARATOR .. "(-?1)$")
    if a and d then
        angle = tonumber(a)
        direction = tonumber(d)
        print("Angle: " .. angle .. "  Direction: " .. direction)


    end
end
