local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase         = require("screen_base")
local MenuHelper         = require("menu_helper")
local KeyboardWidget     = lrequire("common/keyboard_widget")
local HangmanBoard       = lrequire("board")
local HangmanBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- HangmanScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Hangman — Rules

Guess the hidden word one letter at a time before the stick figure is complete.

Each wrong letter guess adds a body part to the hangman drawing.
You have a limited number of wrong guesses (usually 6–7).
Tap a letter on the keyboard to guess it.
Correctly guessed letters are revealed in the word.
The game ends when you complete the word or the hangman is fully drawn.
]])

local GAME_RULES_FR = [[
Pendu — Règles

Devinez le mot caché lettre par lettre avant que le pendu ne soit complet.

Chaque lettre incorrecte ajoute une partie du corps au dessin du pendu.
Vous avez un nombre limité d'erreurs (généralement 6 à 7).
Appuyez sur une lettre du clavier pour la proposer.
Les lettres correctement devinées s'affichent dans le mot.
La partie se termine quand vous complétez le mot ou quand le pendu est entièrement dessiné.
]]

local HangmanScreen = ScreenBase:extend{}

function HangmanScreen:init()
    local state = self.plugin:loadState()
    local lang  = self.plugin:getSetting("lang",       "en")
    local diff  = self.plugin:getSetting("difficulty", "medium")
    self.board  = HangmanBoard:new{ lang = lang, difficulty = diff }
    if not self.board:load(state) then
        -- fresh game already created
    end
    ScreenBase.init(self)
end

function HangmanScreen:isRoundOver()
    return self.board.won or self.board.lost
end

function HangmanScreen:serializeState()
    return self.board:serialize()
end

function HangmanScreen:buildLayout()
    local is_landscape = self:isLandscape()

    -- Top bar
    local title_bar = self:buildTitleBar(_("Hangman"), function()
        return {
            { text = _("New game"),     callback = function() self:onNewGame() end },
            { text = self:_diffLabel(), callback = function() self:openDiffMenu() end },
            { text = self:_langLabel(), callback = function() self:openLangMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    -- Letter keyboard: the same shared widget as Wordle, Word Ladder and
    -- Cryptogram, laid out like the player's own keyboard. Guessed letters are
    -- shaded -- dark for a miss, light for a hit -- so what is left to try
    -- reads at a glance.
    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    self.keyboard_widget = KeyboardWidget.build{
        width      = controls_w,
        key_height = DeviceScreen:scaleBySize(52),
        onKey      = function(k) self:onLetterTap(k) end,
        keyColor   = function(k)
            if not self.board.guessed[k] then return nil end
            return self.board.secret:find(k, 1, true)
                and Blitbuffer.COLOR_GRAY_D or Blitbuffer.COLOR_GRAY_9
        end,
    }
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self.keyboard_widget,
    }

    -- No bottom actions while playing (the keyboard is the control); once
    -- the round is over, "New game" appears under it.
    self.action_bar = nil
    if self:isRoundOver() then
        table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_default })
        table.insert(controls, self:buildActionBar({}))
    end

    -- Board widget: the whole budget's width, a little wider than tall.
    local frame_pad   = Size.padding.default
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    local bw = math.max(budget_w - frame_extra, 100)
    local bh = math.max(math.min(budget_h - frame_extra, math.floor(bw * 0.8)), 80)

    self.board_widget = HangmanBoardWidget:new{
        board  = self.board,
        width  = bw,
        height = bh,
    }

    local board_frame = FrameContainer:new{
        padding = frame_pad,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function HangmanScreen:onLetterTap(letter)
    local result = self.board:guess(letter)
    if result == "already" or result == "done" then return end
    self.plugin:saveState(self.board:serialize())
    -- Rebuild so the keyboard picks up the new key shading.
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function HangmanScreen:onNewGame()
    self.board:newGame()
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function HangmanScreen:openLangMenu()
    local items = {
        { id = "en", text = _("English") },
        { id = "fr", text = _("Français") },
    }
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = items,
        current_id = self.plugin:getSetting("lang", "en"),
        parent     = self,
        on_select  = function(lang)
            self.board.lang = lang
            self.plugin:saveSetting("lang", lang)
            if self.lang_btn then
                self.lang_btn:setText(self:_langLabel(), self.lang_btn.width)
            end
            self:onNewGame()
        end,
    }
end

function HangmanScreen:openDiffMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        parent    = self,
        on_select = function(diff)
            self.board.difficulty = diff
            self.plugin:saveSetting("difficulty", diff)
            if self.diff_btn then
                self.diff_btn:setText(self:_diffLabel(), self.diff_btn.width)
            end
            self:onNewGame()
        end,
    }
end

function HangmanScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    else
        -- The running score only shows between games: mid-game the line
        -- has to fit the narrow landscape side panel.
        local score = self:joinStatus(
            T(_("Wins: %1"),   self.board.wins),
            T(_("Losses: %1"), self.board.losses))
        if self.board.won then
            status = self:joinStatus(_("You won!"), score)
        elseif self.board.lost then
            status = self:joinStatus(T(_("The word was %1."), self.board.secret), score)
        else
            status = self:joinStatus(
                self:_diffLabel(),
                T(_("Wrong: %1/%2"), self.board.wrong, self.board:maxWrong()))
        end
    end
    ScreenBase.updateStatus(self, status)
end

function HangmanScreen:_langLabel()
    local lang = self.plugin:getSetting("lang", "en")
    return T(_("Language: %1"), lang == "fr" and "FR" or "EN")
end

function HangmanScreen:_diffLabel()
    local diff = self.plugin:getSetting("difficulty", "medium")
    local labels = { easy = _("Easy"), medium = _("Medium"), hard = _("Hard") }
    return T(_("Difficulty: %1"), labels[diff] or diff)
end

return HangmanScreen
