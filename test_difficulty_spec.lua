-- Difficulty guarantees (docs/dev/TESTING.md, "Difficulty specs").
--
-- Hangman's level only changes the misses allowed (Easy 8, Medium 6, Hard 4),
-- never the words: both languages draw from the same list at every level.
-- This checks the level table, that each level ends the game at exactly its
-- miss count, that a good player wins less often as the level goes up (on a
-- sample of both word lists), the party points that follow from it, and that
-- a seed draws the same word whatever the level.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

package.loaded["i18n"] = package.loaded["i18n"] or function(s) return s end
package.loaded["ffi/util"] = package.loaded["ffi/util"] or { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }

local LEVELS = { "easy", "medium", "hard" }

-- A good player who knows the word list: always guesses the letter found in
-- the most words still consistent with what is shown, and returns how many
-- misses it took to complete `secret`. Bounded by the 26 letters.
local function goodPlayerMisses(list, secret)
    local cands = {}
    for _, w in ipairs(list) do
        if #w == #secret then cands[#cands + 1] = w end
    end
    local guessed, miss = {}, 0
    local function complete()
        for i = 1, #secret do
            if not guessed[secret:sub(i, i)] then return false end
        end
        return true
    end
    for _ = 1, 26 do
        if complete() then break end
        local count = {}
        for _, w in ipairs(cands) do
            local seen = {}
            for i = 1, #w do
                local c = w:sub(i, i)
                if not guessed[c] and not seen[c] then
                    seen[c] = true
                    count[c] = (count[c] or 0) + 1
                end
            end
        end
        local best, best_n
        for c, n in pairs(count) do
            if not best_n or n > best_n or (n == best_n and c < best) then best, best_n = c, n end
        end
        guessed[best] = true
        if not secret:find(best, 1, true) then miss = miss + 1 end
        local keep = {}
        for _, w in ipairs(cands) do
            local ok = true
            for i = 1, #w do
                local wc, sc = w:sub(i, i), secret:sub(i, i)
                if guessed[sc] then
                    if wc ~= sc then ok = false; break end
                elseif guessed[wc] then
                    ok = false; break
                end
            end
            if ok then keep[#keep + 1] = w end
        end
        cands = keep
    end
    return miss
end

describe("Hangman difficulty", function()
    local Board, HangmanParty

    setup(function()
        Board = dofile(DIR .. "board.lua")
        HangmanParty = dofile(DIR .. "party_game.lua")
    end)

    teardown(function()
        Board.release()
    end)

    it("orders the level table: more misses allowed on easier levels", function()
        assert.are.same({ easy = 8, medium = 6, hard = 4 }, Board.MAX_WRONG)
        for i = 2, #LEVELS do
            assert.is_true(Board.MAX_WRONG[LEVELS[i - 1]] > Board.MAX_WRONG[LEVELS[i]])
        end
    end)

    -- moved from test_board_spec.lua
    it("maxWrong follows difficulty", function()
        assert.are.equal(8, Board:new({ difficulty = "easy" }):maxWrong())
        assert.are.equal(6, Board:new({ difficulty = "medium" }):maxWrong())
        assert.are.equal(4, Board:new({ difficulty = "hard" }):maxWrong())
    end)

    -- moved from test_board_spec.lua (was Hard only), now every level
    it("loses once wrong guesses reach maxWrong, not one before", function()
        for _, level in ipairs(LEVELS) do
            local b = Board:new({ difficulty = level })
            local wrong_letters = {}
            for i = 65, 90 do
                local ch = string.char(i)
                if not b.secret:upper():find(ch, 1, true) then
                    wrong_letters[#wrong_letters + 1] = ch
                end
                if #wrong_letters == b:maxWrong() then break end
            end
            assert.are.equal(b:maxWrong(), #wrong_letters)
            local result
            for k, ch in ipairs(wrong_letters) do
                result = b:guess(ch)
                if k < #wrong_letters then assert.are.equal("wrong", result, level) end
            end
            assert.are.equal("lose", result, level)
            assert.is_true(b.lost)
            assert.are.equal(1, b.losses)
        end
    end)

    -- A good player's win rate on every 40th word of each list (~200 words
    -- per language). Measured 2026-11: en 0.98 / 0.92 / 0.69, fr 1.00 / 0.95 /
    -- 0.77. Easy must be nearly always winnable, Hard still mostly winnable,
    -- and the levels strictly ordered.
    for _, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": a good player wins less often as the level goes up", function()
            local list = Board.getWordList(lang)
            local wins, n = { easy = 0, medium = 0, hard = 0 }, 0
            for i = 1, #list, 40 do
                local m = goodPlayerMisses(list, list[i])
                n = n + 1
                for _, level in ipairs(LEVELS) do
                    if m < Board.MAX_WRONG[level] then wins[level] = wins[level] + 1 end
                end
            end
            local rate = {}
            for _, level in ipairs(LEVELS) do rate[level] = wins[level] / n end
            local where = ("%s: easy %.2f medium %.2f hard %.2f over %d words"):format(
                lang, rate.easy, rate.medium, rate.hard, n)
            assert.is_true(n >= 150, where)
            assert.is_true(rate.easy >= 0.9, where)
            assert.is_true(rate.easy > rate.medium and rate.medium > rate.hard, where)
            assert.is_true(rate.hard >= 0.5, where)
        end)
    end

    it("the word lists are the same at every level, 4 to 7 letters", function()
        for _, lang in ipairs({ "en", "fr" }) do
            local by_len = {}
            for _, w in ipairs(Board.getWordList(lang)) do
                assert.is_true(#w >= 4 and #w <= 7, lang .. " " .. w)
                by_len[#w] = (by_len[#w] or 0) + 1
            end
            for len = 4, 7 do
                assert.is_true((by_len[len] or 0) > 500, lang .. " length " .. len)
            end
        end
    end)

    it("a seed draws the same word, whatever the level", function()
        for _, lang in ipairs({ "en", "fr" }) do
            for seed = 1, 5 do
                local words = {}
                for _, level in ipairs(LEVELS) do
                    math.randomseed(seed)
                    words[#words + 1] = Board:new({ lang = lang, difficulty = level }).secret
                end
                math.randomseed(seed)
                assert.are.equal(words[1], Board:new({ lang = lang, difficulty = "easy" }).secret)
                assert.are.equal(words[1], words[2])
                assert.are.equal(words[1], words[3])
            end
        end
    end)

    it("never reads the clock to draw a word", function()
        local src = assert(io.open(DIR .. "board.lua")):read("*a")
        assert.is_nil(src:find("os%.time"))
        assert.is_nil(src:find("os%.clock"))
        assert.is_nil(src:find("ui/time", 1, true))
    end)

    it("party: the points for a word follow the misses allowed (easy 9, medium 7, hard 5)", function()
        local pts = {}
        for _, level in ipairs(LEVELS) do
            local m = HangmanParty.new{ names = { "A", "B" }, rounds = 1, difficulty = level }
            pts[level] = m:pointsNow()
        end
        assert.are.same({ easy = 9, medium = 7, hard = 5 }, pts)
    end)
end)
