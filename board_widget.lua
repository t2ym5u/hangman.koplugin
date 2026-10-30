local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")

local gwb      = require("grid_widget_base")
local drawLine = gwb.drawLine

local C_BG    = Blitbuffer.COLOR_WHITE
local C_FG    = Blitbuffer.COLOR_BLACK
local C_GRAY  = Blitbuffer.COLOR_GRAY_9

local Screen = Device.screen

-- Largest face whose ink for `sample` fits max_w x max_h. Measured unbounded
-- (a max_width limit cuts the text, so the width test could never fail), ink
-- height is y_top + y_bottom, and Font:getFace scales its size by the DPI, so
-- the pixel bound is converted back first.
local function fitFace(name, sample, max_w, max_h)
    local lo = 6
    local hi = math.max(lo, math.floor(max_h * 1000 / Screen:scaleBySize(1000)) * 2)
    local best = lo
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), Font:getFace(name, mid), sample, true, false)
        if m.x <= max_w and m.y_top + m.y_bottom <= max_h then
            best, lo = mid, mid + 1
        else
            hi = mid - 1
        end
    end
    return Font:getFace(name, best)
end

-- ---------------------------------------------------------------------------
-- HangmanBoardWidget — draws the gallows, figure, word, and wrong letters
-- ---------------------------------------------------------------------------

local HangmanBoardWidget = InputContainer:extend{
    board      = nil,
    width      = 200,
    height     = 200,
}

function HangmanBoardWidget:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }

    -- Sized against the widest the line can get (every letter a W), so
    -- revealing letters never pushes the word past the edges. Wrong letters
    -- are capped at the full alphabet's worth of misses (max_wrong of them).
    local sample = string.rep("W", #self.board.secret, " ")
    self.word_face = fitFace("cfont", sample,
        math.floor(self.width * 0.92), math.floor(self.height * 0.16))
    local wrong_sample = "(" .. string.rep("W", self.board:maxWrong(), " ") .. ")"
    self.info_face = fitFace("smallinfofont", wrong_sample,
        math.floor(self.width * 0.92), math.floor(self.height * 0.08))
    self.paint_rect  = nil
end

function HangmanBoardWidget:refresh()
    local UIManager = require("ui/uimanager")
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

function HangmanBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    bb:paintRect(x, y, self.width, self.height, C_BG)

    local w, h = self.width, self.height
    local board = self.board
    local wrong = board.wrong
    local max_w = board:maxWrong()

    -- Gallows area: top 55% of height
    local gall_h = math.floor(h * 0.55)
    self:_drawGallows(bb, x, y, w, gall_h, wrong, max_w)

    -- Word display: below gallows
    local word_y = y + gall_h + math.floor(h * 0.03)
    local display = board:getDisplay()
    local m = RenderText:sizeUtf8Text(0, w, self.word_face, display, true, false)
    local tx = x + math.floor((w - m.x) / 2)
    RenderText:renderUtf8Text(bb, tx, word_y + m.y_top, self.word_face, display, true, false, C_FG)

    -- Wrong letters label — anchored to the word's *actual* measured
    -- bottom (not a guessed fraction of h), so it never collides with
    -- descenders/underscores regardless of font metrics or word length.
    local word_bottom = word_y + m.y_top + m.y_bottom
    local wrong_letters = board:getWrongLetters()
    if #wrong_letters > 0 then
        local wrong_str = "(" .. table.concat(wrong_letters, " ") .. ")"
        local wy = word_bottom + math.max(6, math.floor(h * 0.05))
        local wm = RenderText:sizeUtf8Text(0, w, self.info_face, wrong_str, true, false)
        local wx = x + math.floor((w - wm.x) / 2)
        RenderText:renderUtf8Text(bb, wx, wy + wm.y_top, self.info_face, wrong_str, true, false, C_GRAY)
    end
end

function HangmanBoardWidget:_drawGallows(bb, x, y, w, h, wrong, max_w)
    -- Line width follows the gallows height, like every other part of the
    -- figure: tied to the width it came out twice as thick as the head on
    -- a wide board, filling the head in and blotting the arms together.
    local lw = math.max(2, math.floor(h * 0.025))   -- line width
    local px = x + math.floor(w * 0.15)             -- gallows left edge
    local py = y + math.floor(h * 0.05)             -- gallows top

    -- Base
    drawLine(bb, px, y + h - lw, math.floor(w * 0.5), lw, C_FG)
    -- Vertical pole
    local pole_h = math.floor(h * 0.85)
    drawLine(bb, px, y + h - lw - pole_h, lw, pole_h, C_FG)
    -- Horizontal beam
    local beam_w = math.floor(w * 0.35)
    drawLine(bb, px, py, beam_w, lw, C_FG)
    -- Rope
    local rope_x = px + beam_w - lw
    local rope_h = math.floor(h * 0.12)
    drawLine(bb, rope_x, py + lw, lw, rope_h, C_FG)

    -- Figure parts drawn based on wrong count
    -- Scale figure relative to how many wrong steps we have (max 6 or 8)
    local steps_per_part = max_w <= 6 and 1 or math.floor(max_w / 6)
    local parts = math.floor(wrong / steps_per_part + 0.5)
    parts = math.min(parts, 6)

    local head_cy = py + lw + rope_h
    local head_r  = math.max(4, math.floor(h * 0.09))
    local body_top = head_cy + head_r
    local body_len = math.floor(h * 0.2)
    local body_cx  = rope_x + math.floor(lw / 2)
    local arm_len  = math.floor(h * 0.12)
    local leg_len  = math.floor(h * 0.15)

    if parts >= 1 then -- head
        -- paintCircle's 5th arg is a ring width, not a "filled" boolean;
        -- omitting it defaults the width to the radius (i.e. filled).
        bb:paintCircle(body_cx, head_cy, head_r, C_FG)
        bb:paintCircle(body_cx, head_cy, head_r - lw, C_BG)
    end
    if parts >= 2 then -- body
        drawLine(bb, body_cx - math.floor(lw/2), body_top, lw, body_len, C_FG)
    end
    if parts >= 3 then -- left arm
        local ax = body_cx - math.floor(lw/2)
        local ay = body_top + math.floor(body_len * 0.25)
        local len = arm_len
        for step = 0, len do
            local px2 = ax - step
            local py2 = ay + step
            bb:paintRect(px2, py2, lw, lw, C_FG)
        end
    end
    if parts >= 4 then -- right arm
        local ax = body_cx + math.floor(lw/2)
        local ay = body_top + math.floor(body_len * 0.25)
        local len = arm_len
        for step = 0, len do
            local px2 = ax + step
            local py2 = ay + step
            bb:paintRect(px2, py2, lw, lw, C_FG)
        end
    end
    if parts >= 5 then -- left leg
        local lx = body_cx - math.floor(lw/2)
        local ly = body_top + body_len
        local len = leg_len
        for step = 0, len do
            local px2 = lx - step
            local py2 = ly + step
            bb:paintRect(px2, py2, lw, lw, C_FG)
        end
    end
    if parts >= 6 then -- right leg
        local lx = body_cx + math.floor(lw/2)
        local ly = body_top + body_len
        local len = leg_len
        for step = 0, len do
            local px2 = lx + step
            local py2 = ly + step
            bb:paintRect(px2, py2, lw, lw, C_FG)
        end
    end
end

return HangmanBoardWidget
