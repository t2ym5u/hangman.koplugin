-- Word lists (4-7 letters, frequency-filtered, shared with anagram.koplugin)
-- See words_en.lua / words_fr.lua for sourcing details.
local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local WORDS = {
    en = nil,  -- loaded lazily
    fr = nil,  -- loaded lazily
}

-- Never drawn: the words of the family-friendly blocklist (blocklist.lua).
local Blocklist = lrequire("blocklist")

local function getWordList(lang)
    if lang == "fr" then
        if not WORDS.fr then WORDS.fr = Blocklist.filter(lrequire("words_fr"), "fr") end
        return WORDS.fr
    end
    if not WORDS.en then WORDS.en = Blocklist.filter(lrequire("words_en"), "en") end
    return WORDS.en
end

-- Words already played, remembered in the plugin settings (game-common
-- seen_history.lua), one history per language (the difficulty only changes
-- the number of misses allowed, not the words): a new word is one not seen
-- yet, and a word only comes back once its whole list has been played --
-- about 3,000 games here, since the oldest are forgotten past SEEN_MAX.
local SeenHistory = require("seen_history")
local SEEN_MAX = 3000

local MAX_WRONG  = { easy = 8, medium = 6, hard = 4 }
local LANG_ORDER = { "en", "fr" }

-- ---------------------------------------------------------------------------
-- HangmanBoard
-- ---------------------------------------------------------------------------

local HangmanBoard = {}
HangmanBoard.__index = HangmanBoard

-- opts.plugin : settings holder for the word history (none: plain random,
--               as in the specs); opts.data : a saved game to restore instead
--               of drawing a word (obj.loaded tells whether it worked);
--               opts.exclude : set of words this board must not draw (a
--               party match's earlier words).
function HangmanBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        plugin      = opts.plugin,
        exclude     = opts.exclude,
        lang        = opts.lang       or "en",
        difficulty  = opts.difficulty or "medium",
        secret      = "",
        guessed     = {},   -- set of uppercase letter chars
        wrong       = 0,
        won         = false,
        lost        = false,
        wins        = 0,
        losses      = 0,
    }, self)
    obj.loaded = opts.data ~= nil and obj:load(opts.data) or false
    if not obj.loaded then obj:newGame() end
    return obj
end

function HangmanBoard:maxWrong()
    return MAX_WRONG[self.difficulty] or 6
end

function HangmanBoard:newGame()
    local list = getWordList(self.lang)
    if self.exclude then
        local left = {}
        for _i, w in ipairs(list) do
            if not self.exclude[w] then left[#left + 1] = w end
        end
        if #left > 0 then list = left end
    end
    if self.plugin then
        self.secret = SeenHistory.open(self.plugin, "words_" .. self.lang, { max = SEEN_MAX }):pick(list)
    else
        self.secret = list[math.random(#list)]
    end
    self.guessed = {}
    self.wrong   = 0
    self.won     = false
    self.lost    = false
end

-- Returns "win", "lose", "wrong", "correct", "already"
function HangmanBoard:guess(letter)
    letter = letter:upper()
    if self.won or self.lost then return "done" end
    if self.guessed[letter] then return "already" end
    self.guessed[letter] = true
    if self.secret:find(letter, 1, true) then
        if self:_allRevealed() then
            self.won  = true
            self.wins = self.wins + 1
            return "win"
        end
        return "correct"
    else
        self.wrong = self.wrong + 1
        if self.wrong >= self:maxWrong() then
            self.lost   = true
            self.losses = self.losses + 1
            return "lose"
        end
        return "wrong"
    end
end

function HangmanBoard:_allRevealed()
    for i = 1, #self.secret do
        local ch = self.secret:sub(i, i)
        if ch ~= " " and not self.guessed[ch] then return false end
    end
    return true
end

-- Returns display string: "_ A _ _ L E" etc.
function HangmanBoard:getDisplay()
    local parts = {}
    for i = 1, #self.secret do
        local ch = self.secret:sub(i, i)
        if ch == " " then
            parts[#parts + 1] = "  "
        elseif self.guessed[ch] or self.lost then
            parts[#parts + 1] = ch
        else
            parts[#parts + 1] = "_"
        end
    end
    return table.concat(parts, " ")
end

-- Returns sorted list of wrong letters
function HangmanBoard:getWrongLetters()
    local result = {}
    for k, _ in pairs(self.guessed) do
        if not self.secret:find(k, 1, true) then
            result[#result + 1] = k
        end
    end
    table.sort(result)
    return result
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function HangmanBoard:serialize()
    local guessed_list = {}
    for k, _ in pairs(self.guessed) do guessed_list[#guessed_list + 1] = k end
    return {
        lang       = self.lang,
        difficulty = self.difficulty,
        secret     = self.secret,
        guessed    = guessed_list,
        wrong      = self.wrong,
        won        = self.won,
        lost       = self.lost,
        wins       = self.wins,
        losses     = self.losses,
    }
end

function HangmanBoard:load(data)
    if type(data) ~= "table" or not data.secret then return false end
    self.lang       = data.lang       or "en"
    self.difficulty = data.difficulty or "medium"
    self.secret     = data.secret     or ""
    self.wrong      = data.wrong      or 0
    self.won        = data.won        or false
    self.lost       = data.lost       or false
    self.wins       = data.wins       or 0
    self.losses     = data.losses     or 0
    self.guessed    = {}
    for _, ch in ipairs(data.guessed or {}) do
        self.guessed[ch] = true
    end
    return true
end

HangmanBoard.LANG_ORDER    = LANG_ORDER
HangmanBoard.MAX_WRONG     = MAX_WRONG
HangmanBoard.getWordList   = getWordList

return HangmanBoard
