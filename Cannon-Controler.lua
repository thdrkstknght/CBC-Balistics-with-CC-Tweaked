-- ===== CONFIG =====
local SEPARATOR = ";"
-- ==================

rednet.open("back") --side of the wireless modem
local Gearshift = peripheral.wrap("back") --side of the sequenced gearshift
local angle, direction

while true do
    local senderId, message = rednet.receive()

    local a, d = message:match("^(-?[%d%.]+)" .. SEPARATOR .. "(-?1)$")
    if a and d then
        angle = tonumber(a)
        direction = tonumber(d)
        print("Angle: " .. angle .. "  Direction: " .. direction)
        -- ===== Example code =====
        Gearshift.rotate(angle, direction)


    end
end
