-- Spec for party_game.lua (Hangman in teams).
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

package.loaded["i18n"] = package.loaded["i18n"] or function(s) return s end
package.loaded["ffi/util"] = package.loaded["ffi/util"] or { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }

local HangmanParty = dofile(DIR .. "party_game.lua")

local function newMatch(opts)
    opts = opts or {}
    local m = HangmanParty.new{
        names       = opts.names or { "Red", "Blue", "Green" },
        rounds      = opts.rounds or 3,
        difficulty  = "medium",
        word_source = opts.word_source,
    }
    if m.phase == "play" then
        m.board.secret = "TABLE"
    end
    return m
end

describe("HangmanParty.normalizeWord", function()
    it("folds accents and capitalises", function()
        assert.are.equal("ELEPHANT", HangmanParty.normalizeWord("éléphant"))
        assert.are.equal("COEUR", HangmanParty.normalizeWord(" Cœur "))
        assert.are.equal("GARCON", HangmanParty.normalizeWord("garçon"))
    end)
    it("keeps single spaces, hyphens become spaces", function()
        assert.are.equal("ARC EN CIEL", HangmanParty.normalizeWord("arc-en-ciel"))
        assert.are.equal("TOUR EIFFEL", HangmanParty.normalizeWord("tour   Eiffel"))
    end)
    it("refuses digits, too short, too long", function()
        local w, err = HangmanParty.normalizeWord("R2D2")
        assert.is_nil(w); assert.are.equal("letters", err)
        w, err = HangmanParty.normalizeWord("ab")
        assert.is_nil(w); assert.are.equal("short", err)
        w, err = HangmanParty.normalizeWord(string.rep("a", 21))
        assert.is_nil(w); assert.are.equal("long", err)
    end)
end)

describe("HangmanParty", function()
    it("keeps the turn on a right letter, passes it on a wrong one", function()
        local m = newMatch()
        assert.are.equal(1, m.turn)
        assert.are.equal("correct", m:guessLetter("T"))
        assert.are.equal(1, m.turn)
        assert.are.equal("wrong", m:guessLetter("Z"))
        assert.are.equal(2, m.turn)
        assert.are.equal(1, m.board.wrong)
        assert.are.equal("already", m:guessLetter("Z"))
        assert.are.equal(2, m.turn)
    end)

    it("scores the team completing the word, more for fewer misses", function()
        local m = newMatch()
        m:guessLetter("Z")                       -- Red misses
        for _, c in ipairs({ "T", "A", "B", "L" }) do m:guessLetter(c) end
        assert.are.equal("win", m:guessLetter("E"))   -- Blue completes
        assert.are.same({ 0, 6, 0 }, m.scores.points)  -- 6 allowed - 1 + 1
        assert.is_true(m:isRoundOver())
        assert.is_false(m:isMatchOver())
    end)

    it("a right whole word wins at once", function()
        local m = newMatch()
        assert.are.equal("win", m:guessWord("table"))
        assert.are.same({ 7, 0, 0 }, m.scores.points)
        assert.is_true(m.board.won)
    end)

    it("a wrong whole word costs a point, a miss and the turn", function()
        local m = newMatch()
        assert.are.equal("wrong_word", m:guessWord("chair"))
        assert.are.same({ -1, 0, 0 }, m.scores.points)
        assert.are.equal(1, m.board.wrong)
        assert.are.equal(2, m.turn)
        assert.are.equal("invalid", m:guessWord("42"))
        assert.are.equal(2, m.turn)
    end)

    it("nobody scores when the drawing is finished", function()
        local m = newMatch()
        local res
        for _, c in ipairs({ "Q", "W", "X", "Z", "V", "K" }) do res = m:guessLetter(c) end
        assert.are.equal("lose", res)
        assert.are.same({ 0, 0, 0 }, m.scores.points)
        assert.is_true(m:isRoundOver())
    end)

    it("typed words: the setter's team sits out and setters rotate", function()
        local m = newMatch{ word_source = "typed" }
        assert.is_true(m:needsSecret())
        assert.are.equal(1, m.setter)
        assert.are.equal(2, m.turn)
        assert.is_false(m:isRoundOver())
        assert.is_false(m:setSecret("x1"))
        assert.is_true(m:setSecret("Château"))
        assert.are.equal("CHATEAU", m.board.secret)
        assert.is_false(m:needsSecret())
        m:guessLetter("Z")      -- team 2 misses -> team 3
        assert.are.equal(3, m.turn)
        m:guessLetter("Q")      -- team 3 misses -> team 2, skipping the setter
        assert.are.equal(2, m.turn)
        m:guessWord("chateau")
        assert.are.same({ 0, 5, 0 }, m.scores.points)
        m:startRound()
        assert.are.equal(2, m.setter)
        assert.are.equal(3, m.turn)
        assert.is_true(m:needsSecret())
    end)

    it("plays the set number of rounds", function()
        local m = newMatch{ rounds = 2 }
        m:guessWord("table")
        m:startRound()
        assert.are.equal(2, m.turn)
        m.board.secret = "TABLE"
        m:guessWord("table")
        assert.is_true(m:isMatchOver())
        assert.are.same({ 7, 7, 0 }, m.scores.points)
    end)

    it("restores a match in progress and one waiting for its word", function()
        local m = newMatch()
        m:guessLetter("T"); m:guessLetter("Z")
        local r = HangmanParty.load(m:serialize())
        assert.is_truthy(r)
        assert.are.equal("TABLE", r.board.secret)
        assert.is_true(r.board.guessed["T"])
        assert.are.equal(1, r.board.wrong)
        assert.are.equal(2, r.turn)
        assert.are.equal(1, r:round())

        local t = newMatch{ word_source = "typed" }
        local rt = HangmanParty.load(t:serialize())
        assert.is_true(rt:needsSecret())
        assert.are.equal(1, rt.setter)
        assert.are.equal(2, rt.turn)
    end)

    it("restores a finished match as finished", function()
        local m = newMatch{ rounds = 1 }
        m:guessWord("table")
        local r = HangmanParty.load(m:serialize())
        assert.is_true(r:isMatchOver())
        assert.are.equal("win", r.last.result)
    end)

    it("rejects unusable saves", function()
        assert.is_nil(HangmanParty.load(nil))
        assert.is_nil(HangmanParty.load({ scores = { names = { "A", "B" }, points = { 0 } } }))
    end)
end)
