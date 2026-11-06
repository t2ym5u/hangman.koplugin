-- Family-friendly words: the game is also played at a family table, so the
-- secret word (shown once the round ends) must never be one of blocklist.lua's
-- vulgar, sexual, scatological, slur or drug-related words.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

local Blocklist = dofile(DIR .. "blocklist.lua")

-- Every word newGame() can draw: math.random is stubbed to walk the pool.
local function everyDrawable(Board, lang)
    local b = Board:new({ lang = lang })
    local real, n, out = math.random, nil, {}
    local i = 0
    math.random = function(m) n = m; return i == 0 and 1 or i end
    b:newGame()
    for k = 1, n do
        i = k
        b:newGame()
        out[#out + 1] = b.secret
    end
    math.random = real
    return out
end

describe("family-friendly secret words", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    it("the raw lists do carry blocklisted words (so the filter is exercised)", function()
        local seen = {}
        for _, w in ipairs(dofile(DIR .. "words_fr.lua")) do seen[w] = true end
        assert.is_true(seen.CACA)
        assert.is_true(seen.SUCEUR)
    end)

    for _, lang in ipairs({ "en", "fr" }) do
        it("never draws a blocklisted " .. lang .. " word", function()
            local all = everyDrawable(Board, lang)
            assert.is_true(#all > 1000)
            for _, w in ipairs(all) do
                assert.is_false(Blocklist.isBlocked(w, lang), w)
            end
        end)
    end
end)

-- "lynch" and its forms were missing from the shared blocklist: a game could
-- draw or reveal LYNCH (EN) or LYNCHAGE (FR). LYNCHPIN is another word.
describe("blocklist: lynch", function()
    it("blocks every English and French form, in any case", function()
        for _, w in ipairs({ "LYNCH", "lynched", "Lynches", "LYNCHING", "LYNCHER", "lynchers" }) do
            assert.is_true(Blocklist.isBlocked(w, "en"), w)
        end
        for _, w in ipairs({ "lyncher", "LYNCHAGE", "lynchee", "lyncheurs" }) do
            assert.is_true(Blocklist.isBlocked(w, "fr"), w)
        end
        assert.is_false(Blocklist.isBlocked("LYNCHPIN", "en"))
    end)
end)
