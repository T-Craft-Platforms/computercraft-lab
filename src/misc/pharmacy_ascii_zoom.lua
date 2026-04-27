-- pharmacy_ascii_zoom.lua
-- Multi-animation ASCII screensaver for CC:Tweaked.
-- Keeps legacy animations and adds:
-- - Bowling (pseudo 3D)
-- - Vista rays (multicolor)
-- - Mouse-driven animation selection menu
-- - Multi-color rendering (not only green)

-- === CONFIGURATION ===
local frameDelay = 0.06
local morphInterval = 12
local backgroundColor = colors.black
local fallbackColor = colors.white
local topBarColor = colors.gray
local topBarTextColor = colors.white

-- === SETUP ===
term.setCursorBlink(false)
term.setBackgroundColor(backgroundColor)
term.clear()

local w, h = term.getSize()
local colorEnabled = term.isColor()
local contentTop = 2
local intensityChars = {".", ":", "*", "#", "@"}

if os.epoch then
    math.randomseed(os.epoch("utc"))
else
    math.randomseed(os.time())
end
math.random()
math.random()
math.random()

local palette = {
    colors.red,
    colors.orange,
    colors.yellow,
    colors.lime,
    colors.green,
    colors.cyan,
    colors.lightBlue,
    colors.blue,
    colors.purple,
    colors.pink,
    colors.white,
}

-- === HELPERS ===
local function clamp(v, minV, maxV)
    if v < minV then
        return minV
    elseif v > maxV then
        return maxV
    end
    return v
end

local function round(v)
    return math.floor(v + 0.5)
end

local function pickColor(i)
    if not colorEnabled then
        return fallbackColor
    end
    local idx = ((i - 1) % #palette) + 1
    return palette[idx]
end

local function randColor()
    return pickColor(math.random(1, #palette))
end

local function refreshSize()
    w, h = term.getSize()
    contentTop = 2
end

local function clearScreen()
    term.setBackgroundColor(backgroundColor)
    term.clear()
end

local function drawChar(x, y, ch, color)
    if x < 1 or x > w or y < 1 or y > h then
        return
    end
    term.setCursorPos(x, y)
    term.setTextColor(color or fallbackColor)
    term.write(ch)
end

local function drawText(x, y, text, color)
    if y < 1 or y > h or text == "" then
        return
    end

    if x < 1 then
        text = text:sub(2 - x)
        x = 1
    end
    if x > w or text == "" then
        return
    end

    if x + #text - 1 > w then
        text = text:sub(1, w - x + 1)
    end
    if text == "" then
        return
    end

    term.setCursorPos(x, y)
    term.setTextColor(color or fallbackColor)
    term.write(text)
end

local function drawCentered(y, text, color)
    local x = math.floor((w - #text) / 2) + 1
    drawText(x, y, text, color)
end

local function drawHLine(y, x1, x2, ch, color)
    if y < 1 or y > h then
        return
    end
    local sx = clamp(math.min(x1, x2), 1, w)
    local ex = clamp(math.max(x1, x2), 1, w)
    if ex < sx then
        return
    end
    term.setCursorPos(sx, y)
    term.setTextColor(color or fallbackColor)
    term.write(string.rep(ch, ex - sx + 1))
end

local function drawButton(x, y, width, text, fg, bg)
    if width < 3 or y < 1 or y > h then
        return
    end
    if x > w or x + width - 1 < 1 then
        return
    end
    if x < 1 then
        width = width + (x - 1)
        x = 1
    end
    if x + width - 1 > w then
        width = w - x + 1
    end
    if width < 3 then
        return
    end

    local label = " " .. text .. " "
    if #label > width then
        label = label:sub(1, width)
    end
    if #label < width then
        label = label .. string.rep(" ", width - #label)
    end

    term.setCursorPos(x, y)
    if colorEnabled then
        term.setBackgroundColor(bg or colors.lightGray)
    else
        term.setBackgroundColor(backgroundColor)
    end
    term.setTextColor(fg or fallbackColor)
    term.write(label)
    term.setBackgroundColor(backgroundColor)
end

local function drawTopBar(title)
    local barBg = colorEnabled and topBarColor or backgroundColor
    local barFg = colorEnabled and topBarTextColor or fallbackColor

    term.setBackgroundColor(barBg)
    term.setTextColor(barFg)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", w))

    drawText(2, 1, "[MENU]", barFg)
    local quitLabel = "[Q]"
    drawText(w - #quitLabel, 1, quitLabel, barFg)
    drawCentered(1, title, barFg)

    term.setBackgroundColor(backgroundColor)
end

local function project3D(z, xNorm)
    z = clamp(z, 0, 1)
    local depth = math.max(4, h - contentTop - 1)
    local nearWidth = math.max(10, math.floor(w * 0.86))
    local farWidth = math.max(4, math.floor(w * 0.24))

    local laneWidth = nearWidth + (farWidth - nearWidth) * z
    local y = h - math.floor(z * depth)
    y = clamp(y, contentTop, h)
    local x = math.floor((w / 2) + xNorm * laneWidth * 0.5)

    return x, y, laneWidth
end

-- === LEGACY PATTERNS (kept) ===
local function initEmpty()
    return {}
end

local function updateNoop(_state, _t)
end

local function renderSpiral(_state, t)
    local cx = w / 2
    local cy = (contentTop + h) / 2

    for y = contentTop, h do
        for x = 1, w do
            local dx = x - cx
            local dy = (y - cy) * 1.55
            local dist = math.sqrt(dx * dx + dy * dy)
            local wave = math.sin(dist / 2.8 - t * 0.18)
            if wave > 0.48 then
                local idx = (math.floor(dist + t) % #intensityChars) + 1
                drawChar(x, y, intensityChars[idx], pickColor(idx + math.floor(dist) + t))
            end
        end
    end
end

local function renderPulse(_state, t)
    local span = clamp(2 + math.floor(math.abs(math.sin(t * 0.08)) * 5), 2, 9)
    local offset = math.floor(t / 2)
    for y = contentTop, h do
        for x = 1, w do
            if ((x + y + offset) % span) == 0 then
                local v = math.abs(math.sin((x + y + t) * 0.07))
                local idx = clamp(math.floor(v * #intensityChars) + 1, 1, #intensityChars)
                drawChar(x, y, intensityChars[idx], pickColor(x + y + t))
            end
        end
    end
end

local function renderCross(_state, t)
    local cx = math.floor(w / 2)
    local cy = math.floor((contentTop + h) / 2)
    local size = math.max(2, math.floor(math.min(w, h - contentTop + 1) * 0.32))
    local thick = math.max(1, math.floor(size / 4))

    for y = cy - size, cy + size do
        for x = cx - size, cx + size do
            if math.abs(x - cx) <= thick or math.abs(y - cy) <= thick then
                local idx = ((x + y + t) % #intensityChars) + 1
                drawChar(x, y, intensityChars[idx], pickColor(t + x + y))
            end
        end
    end
end

local function renderRipple(_state, t)
    local cx = w / 2
    local cy = (contentTop + h) / 2
    for y = contentTop, h do
        for x = 1, w do
            local dx = x - cx
            local dy = (y - cy) * 1.45
            local dist = math.sqrt(dx * dx + dy * dy)
            local wave = math.sin(dist / 2.7 - t * 0.21)
            if math.abs(wave) < 0.24 then
                local idx = ((math.floor(dist) + t) % #intensityChars) + 1
                drawChar(x, y, intensityChars[idx], pickColor(math.floor(dist) + t))
            end
        end
    end
end

local function renderChecker(_state, t)
    local block = 2 + (t % 4)
    local shift = math.floor(t / 5)
    for y = contentTop, h do
        for x = 1, w do
            local gx = math.floor(x / block)
            local gy = math.floor((y - contentTop + shift) / block)
            if ((gx + gy) % 2) == 0 then
                local idx = ((x * 2 + y + t) % #intensityChars) + 1
                drawChar(x, y, intensityChars[idx], pickColor(gx + gy + t))
            end
        end
    end
end

local function renderColumns(_state, t)
    local maxHeight = math.max(3, h - contentTop)
    for x = 1, w do
        local height = math.floor((math.sin((x + t) * 0.17) + 1) * 0.5 * maxHeight)
        for y = h - height, h do
            local idx = ((x + y + t) % #intensityChars) + 1
            drawChar(x, y, intensityChars[idx], pickColor(x + t + idx))
        end
    end
end

-- === MODE: DVD BOUNCE ===
local function initDVD()
    return {
        logo = "[DVD]",
        x = math.max(1, math.floor(w / 2) - 2),
        y = math.max(contentTop, math.floor((contentTop + h) / 2)),
        vx = (math.random(0, 1) == 0) and -1 or 1,
        vy = (math.random(0, 1) == 0) and -1 or 1,
        color = randColor(),
        spark = 0,
    }
end

local function updateDVD(state, _t)
    local logoW = #state.logo
    state.x = state.x + state.vx
    state.y = state.y + state.vy

    local bounced = false
    if state.x <= 1 then
        state.x = 1
        state.vx = math.abs(state.vx)
        bounced = true
    elseif state.x + logoW - 1 >= w then
        state.x = math.max(1, w - logoW + 1)
        state.vx = -math.abs(state.vx)
        bounced = true
    end

    if state.y <= contentTop then
        state.y = contentTop
        state.vy = math.abs(state.vy)
        bounced = true
    elseif state.y >= h then
        state.y = h
        state.vy = -math.abs(state.vy)
        bounced = true
    end

    if bounced then
        state.color = randColor()
        state.spark = 5
    else
        state.spark = math.max(0, state.spark - 1)
    end
end

local function renderDVD(state, t)
    if state.spark > 0 then
        drawChar(state.x - 1, state.y, "*", pickColor(t + state.spark))
        drawChar(state.x + #state.logo, state.y, "*", pickColor(t + state.spark + 2))
    end
    drawText(state.x, state.y, state.logo, state.color)
end

-- === MODE: PONG ===
local function initPong()
    local centerY = math.max(contentTop + 1, math.floor((contentTop + h) / 2))
    return {
        ballX = math.floor(w / 2),
        ballY = centerY,
        vx = (math.random(0, 1) == 0) and -1 or 1,
        vy = (math.random() * 1.2) - 0.6,
        leftY = centerY,
        rightY = centerY,
        paddleSize = math.max(3, math.floor((h - contentTop) / 4)),
        leftScore = 0,
        rightScore = 0,
        flash = 0,
    }
end

local function resetPongBall(state, towardLeft)
    state.ballX = math.floor(w / 2)
    state.ballY = math.floor((contentTop + h) / 2)
    state.vx = towardLeft and -1 or 1
    state.vy = (math.random() * 1.4) - 0.7
    state.flash = 5
end

local function updatePong(state, _t)
    if w < 12 or h < 8 then
        return
    end

    local topLimit = contentTop
    local bottomLimit = h
    local paddleHalf = math.floor(state.paddleSize / 2)

    local leftTarget = clamp(state.ballY, topLimit + paddleHalf, bottomLimit - paddleHalf)
    local rightTarget = clamp(state.ballY, topLimit + paddleHalf, bottomLimit - paddleHalf)
    state.leftY = state.leftY + clamp(leftTarget - state.leftY, -1, 1)
    state.rightY = state.rightY + clamp(rightTarget - state.rightY, -1, 1)

    state.ballX = state.ballX + state.vx
    state.ballY = state.ballY + state.vy

    if state.ballY <= topLimit then
        state.ballY = topLimit
        state.vy = math.abs(state.vy)
    elseif state.ballY >= bottomLimit then
        state.ballY = bottomLimit
        state.vy = -math.abs(state.vy)
    end

    local leftX = 2
    local rightX = w - 1

    if state.ballX <= leftX + 1 then
        local d = state.ballY - state.leftY
        if math.abs(d) <= paddleHalf + 0.5 then
            state.ballX = leftX + 1
            state.vx = math.abs(state.vx)
            state.vy = clamp(state.vy + d * 0.08, -1.3, 1.3)
            state.flash = 3
        else
            state.rightScore = state.rightScore + 1
            resetPongBall(state, true)
        end
    elseif state.ballX >= rightX - 1 then
        local d = state.ballY - state.rightY
        if math.abs(d) <= paddleHalf + 0.5 then
            state.ballX = rightX - 1
            state.vx = -math.abs(state.vx)
            state.vy = clamp(state.vy + d * 0.08, -1.3, 1.3)
            state.flash = 3
        else
            state.leftScore = state.leftScore + 1
            resetPongBall(state, false)
        end
    end

    state.flash = math.max(0, state.flash - 1)
end

local function renderPong(state, t)
    if w < 12 or h < 8 then
        drawCentered(math.floor((contentTop + h) / 2), "Screen too small for Pong", pickColor(t))
        return
    end

    drawCentered(contentTop, tostring(state.leftScore) .. " : " .. tostring(state.rightScore), pickColor(t))

    local centerX = math.floor(w / 2)
    for y = contentTop, h do
        if y % 2 == 0 then
            drawChar(centerX, y, "|", pickColor(t + y))
        end
    end

    local paddleHalf = math.floor(state.paddleSize / 2)
    for dy = -paddleHalf, paddleHalf do
        drawChar(2, round(state.leftY + dy), "#", pickColor(2 + dy + t))
        drawChar(w - 1, round(state.rightY + dy), "#", pickColor(7 + dy + t))
    end

    local ballColor = (state.flash > 0) and pickColor(t * 2 + 1) or pickColor(t + 9)
    drawChar(round(state.ballX), round(state.ballY), "O", ballColor)
end

-- === MODE: BOWLING (PSEUDO 3D) ===
local function createPins3D(rows)
    local pins = {}
    for row = 1, rows do
        local count = row
        local z = 0.80 + (row - 1) * 0.045
        for col = 1, count do
            local xNorm
            if count == 1 then
                xNorm = 0
            else
                xNorm = ((col - 1) / (count - 1) - 0.5) * 0.62 * (row / rows)
            end
            pins[#pins + 1] = {
                xNorm = xNorm,
                z = z,
                standing = true,
                vx = 0,
                vz = 0,
                spin = 0,
            }
        end
    end
    return pins
end

local function initBowling3D()
    local rows = (w >= 28 and h >= 16) and 4 or 3
    return {
        phase = "roll",
        timer = 0,
        frame = 0,
        ballZ = 0.00,
        ballX = 0.00,
        ballCurve = ((math.random() * 2) - 1) * 0.24,
        ballPhase = math.random() * math.pi * 2,
        pins = createPins3D(rows),
        knocked = 0,
        resultText = "",
        resultColor = colors.white,
    }
end

local function startImpact3D(state)
    state.phase = "impact"
    state.timer = 0
    local hits = 0

    for _, pin in ipairs(state.pins) do
        if pin.standing then
            local d = math.abs(pin.xNorm - state.ballX) * 1.9 + math.abs(pin.z - state.ballZ) * 7
            local chance = clamp(0.98 - d * 0.30, 0.05, 0.98)
            if math.random() < chance then
                pin.standing = false
                pin.vx = (pin.xNorm - state.ballX) * 0.18 + ((math.random() * 2) - 1) * 0.05
                pin.vz = -(0.018 + math.random() * 0.03)
                pin.spin = math.random() * 3
                hits = hits + 1
            end
        end
    end

    if hits == 0 and #state.pins > 0 then
        local best = 1
        local bestD = math.huge
        for i, pin in ipairs(state.pins) do
            local d = math.abs(pin.xNorm - state.ballX) + math.abs(pin.z - state.ballZ)
            if d < bestD then
                bestD = d
                best = i
            end
        end
        local pin = state.pins[best]
        pin.standing = false
        pin.vx = 0.05
        pin.vz = -0.03
        pin.spin = 1
        hits = 1
    end

    state.knocked = hits
    local total = #state.pins
    if hits == total then
        state.resultText = "STRIKE!"
        state.resultColor = colors.yellow
    elseif hits >= math.floor(total * 0.7) then
        state.resultText = "Great roll: " .. tostring(hits) .. " pins down"
        state.resultColor = pickColor(3 + hits)
    else
        state.resultText = tostring(hits) .. " pins down"
        state.resultColor = pickColor(1 + hits)
    end
end

local function updateBowling3D(state, _t)
    state.frame = state.frame + 1

    if state.phase == "roll" then
        state.ballZ = state.ballZ + 0.030
        state.ballX = math.sin(state.frame * 0.11 + state.ballPhase) * state.ballCurve * (1 - state.ballZ * 0.65)
        if state.ballZ >= 0.82 then
            startImpact3D(state)
        end
    elseif state.phase == "impact" then
        state.timer = state.timer + 1
        state.ballZ = math.min(1, state.ballZ + 0.018)
        state.ballX = state.ballX * 0.93

        for _, pin in ipairs(state.pins) do
            if not pin.standing then
                pin.xNorm = pin.xNorm + pin.vx
                pin.z = pin.z + pin.vz
                pin.vx = pin.vx * 0.96
                pin.vz = pin.vz * 0.94 + 0.001
                pin.spin = pin.spin + 0.35
            end
        end

        if state.timer > 34 then
            state.phase = "result"
            state.timer = 0
        end
    elseif state.phase == "result" then
        state.timer = state.timer + 1
        if state.timer > 26 then
            local fresh = initBowling3D()
            for k, v in pairs(fresh) do
                state[k] = v
            end
        end
    end
end

local function renderBowling3D(state, t)
    if w < 18 or h < 10 then
        drawCentered(math.floor((contentTop + h) / 2), "Screen too small for Bowling 3D", pickColor(t))
        return
    end

    local steps = math.max(24, (h - contentTop) * 2)
    for i = 0, steps do
        local z = i / steps
        local xL, y = project3D(z, -1)
        local xR = select(1, project3D(z, 1))
        local laneColor = pickColor(i + t + 4)
        drawChar(xL, y, "/", laneColor)
        drawChar(xR, y, "\\", laneColor)

        if i % 4 == 0 then
            local stripe = ((i + t) % 8 < 4) and "." or ":"
            drawHLine(y, xL + 1, xR - 1, stripe, pickColor(i + t))
        end
    end

    local orderedPins = {}
    for i = 1, #state.pins do
        orderedPins[i] = state.pins[i]
    end
    table.sort(orderedPins, function(a, b) return a.z > b.z end)

    for _, pin in ipairs(orderedPins) do
        local px, py = project3D(pin.z, pin.xNorm)
        if pin.standing then
            drawChar(px, py, "A", colors.white)
            drawChar(px, py + 1, "|", colors.lightGray)
        else
            local s = (math.floor(pin.spin + t) % 3)
            local glyph = (s == 0 and "/") or (s == 1 and "-") or "\\"
            drawChar(px, py, glyph, pickColor(px + py + t))
        end
    end

    local bx, by = project3D(state.ballZ, state.ballX)
    local ballColor = pickColor(1 + t * 2)
    if state.ballZ < 0.25 then
        drawText(bx - 1, by, "OO", ballColor)
    elseif state.ballZ < 0.55 then
        drawText(bx, by, "Oo", ballColor)
    else
        drawChar(bx, by, "o", ballColor)
    end
    drawChar(bx, by + 1, ".", colors.gray)

    if state.phase == "result" then
        drawCentered(contentTop + 1, state.resultText, state.resultColor)
    end
end

-- === MODE: VISTA RAYS (MULTICOLOR) ===
local function initVistaRays()
    return {
        spin = 0,
        pulse = 0,
    }
end

local function updateVistaRays(state, _t)
    state.spin = state.spin + 0.055
    state.pulse = state.pulse + 0.18
end

local function renderVistaRays(state, t)
    local cx = w / 2
    local cy = (contentTop + h) / 2
    local rayCount = math.max(14, math.floor(w / 2))
    local maxLen = math.max(w, h) + 6

    for i = 1, rayCount do
        local angle = ((i / rayCount) * math.pi * 2) + state.spin + math.sin((t + i) * 0.04) * 0.25
        local jitter = math.sin((i * 0.39) + t * 0.08) * 0.10
        local rayColor = pickColor(i + t)

        for d = 1, maxLen do
            local px = round(cx + math.cos(angle + jitter) * d * 1.2)
            local py = round(cy + math.sin(angle - jitter) * d * 0.58)
            local wave = math.sin(d * 0.33 - t * 0.22 + i * 0.41)
            if wave > -0.2 then
                local idx = clamp(math.floor(((wave + 1) * 0.5) * (#intensityChars - 1)) + 1, 1, #intensityChars)
                drawChar(px, py, intensityChars[idx], rayColor)
            end
        end
    end

    local glow = 1 + math.floor(math.abs(math.sin(state.pulse)) * 2)
    for i = 1, glow do
        drawChar(round(cx), round(cy), "@", pickColor(t + i * 2))
    end
end

-- === MODE REGISTRY ===
local modes = {
    { name = "Spiral", init = initEmpty, update = updateNoop, render = renderSpiral },
    { name = "Pulse", init = initEmpty, update = updateNoop, render = renderPulse },
    { name = "Cross", init = initEmpty, update = updateNoop, render = renderCross },
    { name = "Ripple", init = initEmpty, update = updateNoop, render = renderRipple },
    { name = "Columns", init = initEmpty, update = updateNoop, render = renderColumns },
    { name = "Checker", init = initEmpty, update = updateNoop, render = renderChecker },
    { name = "DVD Bounce", init = initDVD, update = updateDVD, render = renderDVD },
    { name = "Pong", init = initPong, update = updatePong, render = renderPong },
    { name = "Bowling 3D", init = initBowling3D, update = updateBowling3D, render = renderBowling3D },
    { name = "Vista Rays", init = initVistaRays, update = updateVistaRays, render = renderVistaRays },
}

local function initMode(index)
    local mode = modes[index]
    mode.state = mode.init()
end

local function drawMenu()
    clearScreen()

    drawCentered(1, "ASCII Screensaver Menu", pickColor(6))
    drawCentered(2, "Click an animation (mouse) or press key", pickColor(8))
    drawCentered(3, "A=Auto Cycle   Q=Quit", pickColor(10))

    local entries = {}
    for i, mode in ipairs(modes) do
        entries[#entries + 1] = {
            text = string.format("%2d. %s", i, mode.name),
            action = { kind = "mode", index = i },
            color = pickColor(i + 2),
        }
    end

    entries[#entries + 1] = {
        text = "A. Auto Cycle (all animations)",
        action = { kind = "auto" },
        color = pickColor(3),
    }
    entries[#entries + 1] = {
        text = "Q. Quit",
        action = { kind = "quit" },
        color = colors.red,
    }

    local clickTargets = {}
    local startY = 5
    local itemsPerColumn = math.max(1, h - startY - 1)
    local columns = math.ceil(#entries / itemsPerColumn)
    local colWidth = math.max(12, math.floor(w / columns))

    for i, entry in ipairs(entries) do
        local col = math.floor((i - 1) / itemsPerColumn)
        local row = (i - 1) % itemsPerColumn
        local x = 2 + col * colWidth
        local y = startY + row
        local width = math.max(10, colWidth - 3)
        drawButton(x, y, width, entry.text, colors.white, colorEnabled and colors.gray or backgroundColor)
        drawText(x + 1, y, string.sub(entry.text, 1, 1), entry.color)

        if y >= 1 and y <= h and x <= w and (x + width - 1) >= 1 then
            clickTargets[#clickTargets + 1] = {
                x1 = clamp(x, 1, w),
                x2 = clamp(x + width - 1, 1, w),
                y = y,
                action = entry.action,
            }
        end
    end

    return clickTargets
end

local function showMenu()
    while true do
        refreshSize()
        local targets = drawMenu()
        local event, p1, p2, p3 = os.pullEvent()

        if event == "mouse_click" then
            local mx, my = p2, p3
            for _, target in ipairs(targets) do
                if my == target.y and mx >= target.x1 and mx <= target.x2 then
                    return target.action
                end
            end
        elseif event == "char" then
            local c = string.lower(p1)
            if c == "q" then
                return { kind = "quit" }
            elseif c == "a" then
                return { kind = "auto" }
            else
                local n = tonumber(c)
                if n then
                    if n == 0 then
                        n = 10
                    end
                    if n >= 1 and n <= #modes then
                        return { kind = "mode", index = n }
                    end
                end
            end
        elseif event == "key" then
            if p1 == keys.q then
                return { kind = "quit" }
            elseif p1 == keys.a then
                return { kind = "auto" }
            end
        elseif event == "term_resize" then
            -- redraw on next loop
        end
    end
end

local function runAnimations(startIndex, autoCycle)
    local current = clamp(startIndex or 1, 1, #modes)
    initMode(current)

    local t = 0
    local modeClock = 0

    while true do
        local mode = modes[current]
        clearScreen()
        drawTopBar((autoCycle and "AUTO: " or "") .. mode.name)

        mode.update(mode.state, t)
        mode.render(mode.state, t)

        local timerId = os.startTimer(frameDelay)
        while true do
            local event, p1, p2, p3 = os.pullEvent()
            if event == "timer" and p1 == timerId then
                break
            elseif event == "mouse_click" then
                local mx, my = p2, p3
                if my == 1 and mx >= 2 and mx <= 7 then
                    return "menu"
                end
            elseif event == "char" then
                local c = string.lower(p1)
                if c == "m" then
                    return "menu"
                elseif c == "q" then
                    return "quit"
                end
            elseif event == "key" then
                if p1 == keys.m then
                    return "menu"
                elseif p1 == keys.q then
                    return "quit"
                elseif not autoCycle and p1 == keys.left then
                    current = (current - 2 + #modes) % #modes + 1
                    initMode(current)
                    modeClock = 0
                elseif not autoCycle and p1 == keys.right then
                    current = (current % #modes) + 1
                    initMode(current)
                    modeClock = 0
                end
            elseif event == "term_resize" then
                refreshSize()
                initMode(current)
                clearScreen()
                drawTopBar((autoCycle and "AUTO: " or "") .. mode.name)
            end
        end

        t = t + 1
        modeClock = modeClock + frameDelay
        if autoCycle and modeClock >= morphInterval then
            modeClock = 0
            current = (current % #modes) + 1
            initMode(current)
        end
    end
end

-- === MAIN ===
refreshSize()
while true do
    local action = showMenu()
    if action.kind == "quit" then
        break
    elseif action.kind == "auto" then
        local result = runAnimations(1, true)
        if result == "quit" then
            break
        end
    elseif action.kind == "mode" then
        local result = runAnimations(action.index, false)
        if result == "quit" then
            break
        end
    end
end

term.setBackgroundColor(backgroundColor)
term.setTextColor(fallbackColor)
term.clear()
term.setCursorPos(1, 1)
