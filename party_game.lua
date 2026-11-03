-- party_game.lua — Hangman's "· multiplayer" mode, in teams (no UI here, so
-- busted can test it).
--
-- The word comes from the word list, or a player types it (word_source =
-- "typed"): round k's word is set by team k, which sits the round out. The
-- other teams take turns: a right letter keeps the turn, a wrong one adds a
-- miss to the drawing and passes the turn. On its turn a team may try the
-- whole word: right, it completes the word; wrong, it loses a point, the
-- drawing gets a miss and the turn passes. The team that completes the word
-- scores (allowed misses - misses + 1) points: 7 with no miss on Medium, down
-- to 2 with five. A finished drawing reveals the word; nobody scores.
-- A match is `rounds` words. List words never come back within a match, and
-- with opts.plugin they are drawn through the solo game's word history
-- (board.lua), so a word seen before waits until the list is used up.

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Party        = require("party")
local HangmanBoard = lrequire("board")

local HangmanParty = {}
HangmanParty.__index = HangmanParty

HangmanParty.MIN_TEAMS      = 2
HangmanParty.MAX_TEAMS      = 4
HangmanParty.ROUND_CHOICES  = { 3, 5, 7, 10 }
HangmanParty.DEFAULT_ROUNDS = 5
HangmanParty.MIN_LETTERS    = 3
HangmanParty.MAX_CHARS      = 20
HangmanParty.WRONG_WORD_PENALTY = 1

-- ---------------------------------------------------------------------------
-- A typed secret word
-- ---------------------------------------------------------------------------

-- The keyboard only has A-Z: accents are folded the way the word lists are.
local FOLD = {
    ["à"]="A", ["â"]="A", ["ä"]="A", ["á"]="A", ["ã"]="A", ["å"]="A",
    ["À"]="A", ["Â"]="A", ["Ä"]="A", ["Á"]="A", ["Ã"]="A", ["Å"]="A",
    ["ç"]="C", ["Ç"]="C",
    ["é"]="E", ["è"]="E", ["ê"]="E", ["ë"]="E",
    ["É"]="E", ["È"]="E", ["Ê"]="E", ["Ë"]="E",
    ["î"]="I", ["ï"]="I", ["í"]="I", ["ì"]="I",
    ["Î"]="I", ["Ï"]="I", ["Í"]="I", ["Ì"]="I",
    ["ñ"]="N", ["Ñ"]="N",
    ["ô"]="O", ["ö"]="O", ["ó"]="O", ["ò"]="O", ["õ"]="O",
    ["Ô"]="O", ["Ö"]="O", ["Ó"]="O", ["Ò"]="O", ["Õ"]="O",
    ["ù"]="U", ["û"]="U", ["ü"]="U", ["ú"]="U",
    ["Ù"]="U", ["Û"]="U", ["Ü"]="U", ["Ú"]="U",
    ["ÿ"]="Y", ["Ÿ"]="Y", ["ý"]="Y", ["Ý"]="Y",
    ["œ"]="OE", ["Œ"]="OE", ["æ"]="AE", ["Æ"]="AE", ["ß"]="SS",
}

-- Returns the word in A-Z capitals (single spaces kept between words; a
-- hyphen or an apostrophe counts as a space), or nil and "short" / "long" /
-- "letters".
function HangmanParty.normalizeWord(s)
    s = tostring(s or "")
    s = s:gsub("[\194-\244][\128-\191]*", function(ch) return FOLD[ch] or ch end)
    s = s:upper():gsub("[%-'’]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if s:find("[^A-Z ]") then return nil, "letters" end
    local letters = #s:gsub(" ", "")
    if letters < HangmanParty.MIN_LETTERS then return nil, "short" end
    if #s > HangmanParty.MAX_CHARS then return nil, "long" end
    return s
end

-- ---------------------------------------------------------------------------
-- Match
-- ---------------------------------------------------------------------------

-- The list words this match has used so far, as a set.
local function usedSet(list)
    local set = {}
    for _i, w in ipairs(list) do set[w] = true end
    return set
end

-- opts: names (team names), rounds, lang, difficulty, word_source
-- ("list" or "typed"), plugin (settings holder for the word history; none in
-- the specs).
function HangmanParty.new(opts)
    local self = setmetatable({
        plugin      = opts.plugin,
        used        = {},
        scores      = Party.newScores(opts.names),
        rounds      = opts.rounds or HangmanParty.DEFAULT_ROUNDS,
        lang        = opts.lang or "en",
        difficulty  = opts.difficulty or "medium",
        word_source = opts.word_source == "typed" and "typed" or "list",
        turn        = 1,
        setter      = nil,
        phase       = "play",
        last        = nil,
    }, HangmanParty)
    self:startRound()
    return self
end

function HangmanParty:teamCount()
    return #self.scores.names
end

function HangmanParty:teamName(i)
    return self.scores.names[i or self.turn]
end

function HangmanParty:round()
    return self.scores.round
end

-- The team after `i`, skipping the setter (who sits the round out).
function HangmanParty:_nextTeam(i)
    local n = self:teamCount()
    repeat i = i % n + 1 until i ~= self.setter
    return i
end

-- The next word. Typed words: round k's word is set by team k (cycling) and
-- the team after it starts; list words: team k starts.
function HangmanParty:startRound()
    Party.nextRound(self.scores)
    local k = (self.scores.round - 1) % self:teamCount() + 1
    self.last  = nil
    if self.word_source == "typed" then
        -- The setter's word replaces this one: nothing to remember.
        self.board = HangmanBoard:new{ lang = self.lang, difficulty = self.difficulty }
    else
        self.board = HangmanBoard:new{ lang = self.lang, difficulty = self.difficulty,
                                       plugin = self.plugin, exclude = usedSet(self.used) }
        self.used[#self.used + 1] = self.board.secret
    end
    if self.word_source == "typed" then
        self.setter = k
        self.turn   = self:_nextTeam(k)
        self.phase  = "setup"
    else
        self.setter = nil
        self.turn   = k
        self.phase  = "play"
    end
end

-- The setter's word. Returns true, or false and the reason (see
-- normalizeWord).
function HangmanParty:setSecret(word)
    local w, err = HangmanParty.normalizeWord(word)
    if not w then return false, err end
    self.board.secret  = w
    self.board.guessed = {}
    self.board.wrong   = 0
    self.board.won     = false
    self.board.lost    = false
    self.phase = "play"
    return true
end

function HangmanParty:needsSecret()
    return self.phase == "setup"
end

function HangmanParty:isRoundOver()
    return self.phase == "play" and (self.board.won or self.board.lost)
end

function HangmanParty:isMatchOver()
    return self:isRoundOver() and self.scores.round >= self.rounds
end

-- Points for completing the word now.
function HangmanParty:pointsNow()
    return math.max(1, self.board:maxWrong() - self.board.wrong + 1)
end

function HangmanParty:_scoreWin(team)
    local pts = self:pointsNow()
    Party.award(self.scores, team, pts)
    self.last = { result = "win", team = team, points = pts }
end

-- The current team guesses a letter. Returns the board's result ("correct",
-- "wrong", "win", "lose", "already", "done").
function HangmanParty:guessLetter(letter)
    if self.phase ~= "play" or self:isRoundOver() then return "done" end
    local team = self.turn
    local res  = self.board:guess(letter)
    if res == "wrong" then
        self:passTurn()
        self.last = { result = "wrong", team = team, letter = letter:upper() }
    elseif res == "correct" then
        self.last = { result = "correct", team = team, letter = letter:upper() }
    elseif res == "win" then
        self:_scoreWin(team)
    elseif res == "lose" then
        self.last = { result = "lose", team = team }
    end
    return res
end

-- The current team tries the whole word. Returns "win", "wrong_word",
-- "lose" (that miss finished the drawing), "invalid" (not a word: nothing
-- happens) or "done".
function HangmanParty:guessWord(word)
    if self.phase ~= "play" or self:isRoundOver() then return "done" end
    local w = HangmanParty.normalizeWord(word)
    if not w then return "invalid" end
    local team  = self.turn
    local board = self.board
    if w == board.secret then
        for i = 1, #w do
            local ch = w:sub(i, i)
            if ch ~= " " then board.guessed[ch] = true end
        end
        board.won = true
        self:_scoreWin(team)
        return "win"
    end
    Party.award(self.scores, team, -HangmanParty.WRONG_WORD_PENALTY)
    board.wrong = board.wrong + 1
    if board.wrong >= board:maxWrong() then
        board.lost = true
        self.last = { result = "lose", team = team, word = w }
        return "lose"
    end
    self:passTurn()
    self.last = { result = "wrong_word", team = team, word = w }
    return "wrong_word"
end

function HangmanParty:passTurn()
    self.turn = self:_nextTeam(self.turn)
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function HangmanParty:serialize()
    return {
        scores      = Party.copyScores(self.scores),
        rounds      = self.rounds,
        lang        = self.lang,
        difficulty  = self.difficulty,
        word_source = self.word_source,
        turn        = self.turn,
        setter      = self.setter,
        phase       = self.phase,
        last        = self.last,
        used        = self.used,
        board       = self.board:serialize(),
    }
end

-- A saved match, or nil when the table is unusable.
function HangmanParty.load(data, plugin)
    if type(data) ~= "table" then return nil end
    local scores = Party.restoreScores(data.scores)
    if not scores or #scores.names < HangmanParty.MIN_TEAMS then return nil end
    local n = #scores.names
    local used = {}
    if type(data.used) == "table" then
        for _i, w in ipairs(data.used) do
            if type(w) == "string" then used[#used + 1] = w end
        end
    end
    local self = setmetatable({
        plugin      = plugin,
        used        = used,
        scores      = scores,
        rounds      = tonumber(data.rounds) or HangmanParty.DEFAULT_ROUNDS,
        lang        = data.lang or "en",
        difficulty  = data.difficulty or "medium",
        word_source = data.word_source == "typed" and "typed" or "list",
        turn        = tonumber(data.turn) or 1,
        setter      = tonumber(data.setter),
        phase       = data.phase == "setup" and "setup" or "play",
        last        = type(data.last) == "table" and data.last or nil,
    }, HangmanParty)
    if self.setter and (self.setter < 1 or self.setter > n) then self.setter = nil end
    if self.turn < 1 or self.turn > n or self.turn == self.setter then
        self.turn = self:_nextTeam(self.setter or n)
    end
    self.board = HangmanBoard:new{ lang = self.lang, difficulty = self.difficulty,
                                   data = data.board }
    if not self.board.loaded then return nil end
    self.board.plugin = plugin
    return self
end

return HangmanParty
