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

local CenterContainer = require("ui/widget/container/centercontainer")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local InputDialog     = require("ui/widget/inputdialog")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local Party           = require("party")
local HangmanParty    = lrequire("party_game")

local DeviceScreen = Device.screen

-- Party seats are teams here, 2 to 4.
local TEAMS = { teams = true, max = 4 }

local function joinLines(...)
    return table.concat({ ... }, "\n")
end

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

local PARTY_RULES_EN = _([[
Hangman · multiplayer — Rules

For 2 to 4 teams around one reader laid in the middle of the table. Everyone sees the same word and drawing; the team to play taps the letters.

Setup (game menu)
• Teams: 2, 3 or 4. Team names: tap a team to rename it (names are remembered).
• Rounds: 3, 5, 7 or 10 words per match.
• Word: from the word list, or typed by a player.
• Difficulty: misses allowed before the drawing is complete (Easy 8, Medium 6, Hard 4). Language: the word list (EN or FR).

Typed words
Each round one team in turn picks the word. The reader shows "<team> picks the word": one of its players takes the reader and types the word (hidden as it is typed) while everyone else looks away, then lays it back on the table. That team sits the round out. "Word from the list" skips typing for that round.

A round
• The team written in big type taps a letter. Right: the letter appears and the same team plays again. Wrong: the drawing gets a miss and the turn passes to the next team.
• Guess the word: on its turn a team may try the whole word. Right, it completes the word. Wrong, the team loses 1 point, the drawing gets a miss and the turn passes.
• Each round, another team starts.

Scoring
• The team that completes the word scores the misses it had left, plus one. On Medium (6 misses): 7 points with no miss, 6 with one, … 2 with five. Easy: up to 9; Hard: up to 5.
• If the drawing is complete, the word is revealed and nobody scores.
• Scores can go below zero after wrong whole-word guesses.

End of the match
After the last round the final scoreboard shows the winner: the team with the most points. Teams with the same total share their place; if several teams are first, it's a tie. "New game" starts a new match.
]])

local PARTY_RULES_FR = [[
Pendu · à plusieurs — Règles

Pour 2 à 4 équipes autour d'une liseuse posée au milieu de la table. Tout le monde voit le même mot et le même dessin ; l'équipe qui joue touche les lettres.

Réglages (menu du jeu)
• Équipes : 2, 3 ou 4. Noms des équipes : touchez une équipe pour la renommer (les noms sont mémorisés).
• Manches : 3, 5, 7 ou 10 mots par partie.
• Mot : tiré de la liste, ou tapé par un joueur.
• Difficulté : erreurs permises avant que le pendu soit complet (Facile 8, Moyen 6, Difficile 4). Langue : la liste de mots (EN ou FR).

Mots tapés
À chaque manche, une équipe à tour de rôle choisit le mot. La liseuse affiche « <équipe> choisit le mot » : un de ses joueurs prend la liseuse et tape le mot (masqué pendant la saisie) pendant que les autres détournent les yeux, puis la repose sur la table. Cette équipe ne joue pas la manche. « Mot de la liste » évite de taper pour cette manche.

Une manche
• L'équipe écrite en gros touche une lettre. Bonne : la lettre apparaît et la même équipe rejoue. Mauvaise : le dessin prend une erreur et la main passe à l'équipe suivante.
• Deviner le mot : à son tour, une équipe peut proposer le mot entier. Juste, elle complète le mot. Faux, l'équipe perd 1 point, le dessin prend une erreur et la main passe.
• À chaque manche, une autre équipe commence.

Points
• L'équipe qui complète le mot marque les erreurs qu'il lui restait, plus une. En Moyen (6 erreurs) : 7 points sans erreur, 6 avec une, … 2 avec cinq. Facile : jusqu'à 9 ; Difficile : jusqu'à 5.
• Si le pendu est complet, le mot est révélé et personne ne marque.
• Un score peut passer sous zéro après de mauvaises propositions de mot.

Fin de partie
Après la dernière manche, le tableau final affiche la gagnante : l'équipe qui a le plus de points. Des équipes à égalité partagent leur place ; si plusieurs sont premières, c'est une égalité. « Nouvelle partie » relance une partie.
]]

local RULES = {
    solo  = { GAME_RULES_EN, GAME_RULES_FR },
    party = { PARTY_RULES_EN, PARTY_RULES_FR },
}

local HangmanScreen = ScreenBase:extend{}

function HangmanScreen:init()
    -- Party matches are saved under their own key: the solo game in
    -- progress (and its wins/losses) is left as it was.
    self.party = self.plugin.launch_mode == "party"
    if self.party then
        self.match = HangmanParty.load(self.plugin:loadState("party_state"))
                     or self:_newMatch()
        self.board = self.match.board
    else
        local state = self.plugin:loadState()
        local lang  = self.plugin:getSetting("lang",       "en")
        local diff  = self.plugin:getSetting("difficulty", "medium")
        self.board  = HangmanBoard:new{ lang = lang, difficulty = diff }
        if not self.board:load(state) then
            -- fresh game already created
        end
    end
    ScreenBase.init(self)
end

function HangmanScreen:isRoundOver()
    if self.party then return self.match:isRoundOver() end
    return self.board.won or self.board.lost
end

function HangmanScreen:getRoundOverButtons()
    if self.party and not self.match:isMatchOver() then
        return { { text = _("Next round"), callback = function() self:onNextRound() end } }
    end
    return ScreenBase.getRoundOverButtons(self)
end

function HangmanScreen:serializeState()
    return self.board:serialize()
end

function HangmanScreen:_save()
    if self.party then
        self.plugin:saveState(self.match:serialize(), "party_state")
    else
        self.plugin:saveState(self.board:serialize())
    end
end

-- ScreenBase's version saves serializeState() as the solo game; a party
-- match goes to its own key instead.
function HangmanScreen:closeScreen()
    self:_save()
    self.plugin:onScreenClosed()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
end

function HangmanScreen:_redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Party mode (teams)
-- ---------------------------------------------------------------------------

function HangmanScreen:_teamCount()
    return Party.loadCount(self.plugin, TEAMS)
end

function HangmanScreen:_newMatch()
    return HangmanParty.new{
        names       = Party.loadPlayers(self.plugin, self:_teamCount(), TEAMS),
        rounds      = self.plugin:getSetting("party_rounds", HangmanParty.DEFAULT_ROUNDS),
        lang        = self.plugin:getSetting("lang", "en"),
        difficulty  = self.plugin:getSetting("difficulty", "medium"),
        word_source = self.plugin:getSetting("party_word_source", "list"),
    }
end

function HangmanScreen:onNextRound()
    self.match:startRound()
    self.board = self.match.board
    self:_save()
    self:_redraw()
end

function HangmanScreen:openTeamCountMenu()
    Party.pickCount(self.plugin, function() self:onNewGame() end, self, TEAMS)
end

-- Renaming keeps the match going.
function HangmanScreen:openTeamNames()
    local names = self.match.scores.names
    Party.editPlayers(self.plugin, names, function()
        self:_save()
        self:_redraw()
    end, self, TEAMS)
end

function HangmanScreen:openRoundsMenu()
    local items = {}
    for _i, n in ipairs(HangmanParty.ROUND_CHOICES) do
        items[#items + 1] = { id = n, text = tostring(n) }
    end
    MenuHelper.openPickerMenu{
        title      = _("Rounds"),
        items      = items,
        current_id = self.match.rounds,
        parent     = self,
        on_select  = function(n)
            self.plugin:saveSetting("party_rounds", n)
            self:onNewGame()
        end,
    }
end

local function sourceLabel(src)
    return src == "typed" and _("Typed by a player") or _("Word list")
end

function HangmanScreen:openWordSourceMenu()
    MenuHelper.openPickerMenu{
        title      = _("Word"),
        items      = { { id = "list",  text = sourceLabel("list") },
                       { id = "typed", text = sourceLabel("typed") } },
        current_id = self.match.word_source,
        parent     = self,
        on_select  = function(src)
            self.plugin:saveSetting("party_word_source", src)
            self:onNewGame()
        end,
    }
end

function HangmanScreen:openModeMenu()
    MenuHelper.openPickerMenu{
        title      = _("Mode"),
        items      = { { id = "solo",  text = _("Solo") },
                       { id = "party", text = _("Multiplayer") } },
        current_id = self.party and "party" or "solo",
        parent     = self,
        on_select  = function(mode) self:setMode(mode) end,
    }
end

-- Switches between solo and party, then starts a new game in that mode.
function HangmanScreen:setMode(mode)
    if (mode == "party") == self.party then return end
    self:_save()
    self.plugin.launch_mode = mode
    self.party = mode == "party"
    if self.party then
        self.match = self:_newMatch()
        self.board = self.match.board
    else
        self.match = nil
        self.board = HangmanBoard:new{
            lang       = self.plugin:getSetting("lang", "en"),
            difficulty = self.plugin:getSetting("difficulty", "medium"),
        }
        self.board:load(self.plugin:loadState())
        self.board:newGame()
    end
    self:_save()
    self:_redraw()
end

function HangmanScreen:_modeLabel()
    return T(_("Mode: %1"), self.party and _("Multiplayer") or _("Solo"))
end

-- The setter's team types the word; the InputDialog hides it as it is typed.
function HangmanScreen:askSecretWord()
    local dialog
    dialog = InputDialog:new{
        title       = T(_("Secret word — %1"), self.match:teamName(self.match.setter)),
        description = _("Letters only. The other teams must not see it."),
        text_type   = "password",
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function()
                UIManager:close(dialog)
            end },
            { text = _("OK"), is_enter_default = true, callback = function()
                local ok, err = self.match:setSecret(dialog:getInputText())
                if not ok then
                    self:showMessage(err == "short"
                        and T(_("At least %1 letters."), HangmanParty.MIN_LETTERS)
                        or  err == "long"
                        and T(_("At most %1 characters."), HangmanParty.MAX_CHARS)
                        or  _("Letters only."))
                    return
                end
                UIManager:close(dialog)
                self:_save()
                self:_redraw()
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- This round's word comes from the list after all (the setter's team sits
-- out anyway).
function HangmanScreen:useListWord()
    self.match.phase = "play"
    self:_save()
    self:_redraw()
end

function HangmanScreen:askWholeWord()
    local dialog
    dialog = InputDialog:new{
        title       = T(_("%1 tries the word"), self.match:teamName()),
        description = T(_("Wrong: %1 loses %2 point and the turn."),
            self.match:teamName(), HangmanParty.WRONG_WORD_PENALTY),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function()
                UIManager:close(dialog)
            end },
            { text = _("OK"), is_enter_default = true, callback = function()
                local team = self.match:teamName()
                local res  = self.match:guessWord(dialog:getInputText())
                if res == "invalid" then
                    self:showMessage(_("Letters only."))
                    return
                end
                UIManager:close(dialog)
                self:_afterPartyMove()
                if res == "wrong_word" then
                    self:updateStatus(T(_("Wrong word! %1 loses a point."), team))
                end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function HangmanScreen:_afterPartyMove()
    self:_save()
    self:_redraw()
    if self.match:isMatchOver() then
        Party.showScoreboard(self.match.scores, { final = true })
    end
end

-- Big bold line, shrunk until it fits `width` (the landscape side panel is
-- narrow).
function HangmanScreen:_buildBanner(text, width)
    local w
    for _i, size in ipairs({ 30, 26, 22, 18 }) do
        if w then w:free() end
        w = TextWidget:new{ text = text, face = Font:getFace("tfont", size), bold = true }
        if w:getSize().w <= width then return w end
    end
    w:free()
    return TextWidget:new{ text = text, face = Font:getFace("tfont", 18), bold = true,
        max_width = width }
end

-- Whose turn it is, then who scored.
function HangmanScreen:_bannerText()
    local m = self.match
    if m:isMatchOver() then
        local leaders = Party.leaders(m.scores)
        if #leaders == 1 then return T(_("%1 wins!"), m:teamName(leaders[1])) end
        return _("It's a tie!")
    end
    local last = m.last
    if last and last.result == "win" then
        return T(_("%1 scores %2!"), m:teamName(last.team), last.points)
    elseif self.board.lost then
        return _("Nobody scores")
    end
    return m:teamName()
end

function HangmanScreen:_partyMenu()
    return {
        { text = _("New game"), callback = function() self:onNewGame() end },
        { text = T(_("Teams: %1"), self.match:teamCount()),
          callback = function() self:openTeamCountMenu() end },
        { text = _("Team names"), callback = function() self:openTeamNames() end },
        { text = T(_("Rounds: %1"), self.match.rounds),
          callback = function() self:openRoundsMenu() end },
        { text = T(_("Word: %1"), sourceLabel(self.match.word_source)),
          callback = function() self:openWordSourceMenu() end },
        { text = self:_diffLabel(), callback = function() self:openDiffMenu() end },
        { text = self:_langLabel(), callback = function() self:openLangMenu() end },
        { text = self:_modeLabel(), callback = function() self:openModeMenu() end },
        { text = _("Scores"), callback = function() Party.showScoreboard(self.match.scores) end },
        self:makeModeRulesButtonConfig(RULES),
    }
end

-- Hand-over screen: a team picks this round's word. Nothing secret on it.
function HangmanScreen:_buildSetupLayout(title_bar)
    local w = math.min(self.dimen.w, self.dimen.h) - 2 * self:getGutter()
    local m = self.match
    local content = VerticalGroup:new{
        align = "center",
        self:_buildBanner(T(_("%1 picks the word"), m:teamName(m.setter)), w),
        VerticalSpan:new{ width = Size.span.vertical_large },
        TextBoxWidget:new{
            text      = _("One player of this team takes the reader and types a secret word. Everyone else looks away. This team sits the round out."),
            face      = Font:getFace("cfont", 22),
            width     = w,
            alignment = "center",
        },
        VerticalSpan:new{ width = Size.span.vertical_large },
        TextBoxWidget:new{
            text      = joinLines(T(_("Round %1/%2"), m:round(), m.rounds),
                                     Party.statusText(m.scores)),
            face      = Font:getFace("cfont", 18),
            width     = w,
            alignment = "center",
        },
        VerticalSpan:new{ width = Size.span.vertical_large * 2 },
        self:buildActionBar({
            { text = _("Type the word"), callback = function() self:askSecretWord() end },
            { text = _("Word from the list"), callback = function() self:useListWord() end },
        }, w),
    }
    local avail_h = self.dimen.h - title_bar:getSize().h
    self.layout = VerticalGroup:new{
        align = "center",
        title_bar,
        CenterContainer:new{
            dimen = Geom:new{ w = self.dimen.w, h = avail_h },
            content,
        },
    }
    self[1] = self.layout
end

function HangmanScreen:buildLayout()
    local is_landscape = self:isLandscape()

    -- Top bar
    local title_bar = self:buildTitleBar(_("Hangman"), function()
        if self.party then return self:_partyMenu() end
        return {
            { text = _("New game"),     callback = function() self:onNewGame() end },
            { text = self:_diffLabel(), callback = function() self:openDiffMenu() end },
            { text = self:_langLabel(), callback = function() self:openLangMenu() end },
            { text = self:_modeLabel(), callback = function() self:openModeMenu() end },
            self:makeModeRulesButtonConfig(RULES),
        }
    end)
    if self.party and self.match:needsSecret() then
        self:_buildSetupLayout(title_bar)
        return
    end

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
    if self.party then
        -- Readable from across the table: whose turn it is, then the scores.
        table.insert(controls, 1, self:_buildBanner(self:_bannerText(), controls_w))
        table.insert(controls, 2, TextBoxWidget:new{
            text      = Party.statusText(self.match.scores),
            face      = Font:getFace("cfont", 20),
            width     = controls_w,
            alignment = "center",
        })
        table.insert(controls, 3, VerticalSpan:new{ width = Size.span.vertical_default })
        -- Trying the whole word is the one action besides letters.
        table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_default })
        table.insert(controls, self:buildActionBar({
            { text = _("Guess the word"), callback = function() self:askWholeWord() end },
        }))
    elseif self:isRoundOver() then
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
    if self.party then
        local result = self.match:guessLetter(letter)
        if result == "already" or result == "done" then return end
        self:_afterPartyMove()
        if result == "wrong" then
            self:updateStatus(T(_("No %1! Turn passes."), letter:upper()))
        end
        return
    end
    local result = self.board:guess(letter)
    if result == "already" or result == "done" then return end
    self.plugin:saveState(self.board:serialize())
    -- Rebuild so the keyboard picks up the new key shading.
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function HangmanScreen:onNewGame()
    if self.party then
        self.match = self:_newMatch()
        self.board = self.match.board
        self:_save()
        self:_redraw()
        return
    end
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
        local round = self.party
            and T(_("Round %1/%2"), self.match:round(), self.match.rounds)
        if self.party and self:isRoundOver() then
            status = self:joinStatus(T(_("The word was %1."), self.board.secret), round)
        elseif self.party then
            status = self:joinStatus(round,
                T(_("Wrong: %1/%2"), self.board.wrong, self.board:maxWrong()))
        elseif self.board.won then
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
