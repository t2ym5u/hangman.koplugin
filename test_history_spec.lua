-- Words are not repeated: solo games and party matches draw through one word
-- history per language kept in the plugin settings (game-common
-- seen_history.lua); a party match never repeats a word. Also checks the
-- word lists themselves.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. DIR .. "common/?.lua;" .. package.path

package.loaded["i18n"] = package.loaded["i18n"] or function(s) return s end
package.loaded["ffi/util"] = package.loaded["ffi/util"] or { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }

local Blocklist = dofile(DIR .. "blocklist.lua")

local function fakePlugin(store)
    store = store or {}
    return {
        store = store,
        getSetting  = function(_self, k, d) local v = store[k]; if v == nil then return d end; return v end,
        saveSetting = function(_self, k, v) store[k] = v end,
    }
end

describe("word history", function()
    local Board, HangmanParty
    setup(function()
        Board = require("board")
        HangmanParty = dofile(DIR .. "party_game.lua")
    end)

    it("does not repeat a word across two sessions", function()
        local store, seen = {}, {}
        for _session = 1, 2 do
            local b = Board:new{ lang = "en", difficulty = "hard", plugin = fakePlugin(store) }
            seen[b.secret] = (seen[b.secret] or 0) + 1
            for _g = 1, 499 do
                b:newGame()
                seen[b.secret] = (seen[b.secret] or 0) + 1
            end
        end
        local n = 0
        for w, c in pairs(seen) do n = n + 1; assert.are.equal(1, c, w) end
        assert.are.equal(1000, n)
        assert.are.equal(1000, #store.seen_words_en)
    end)

    it("restores a saved game without drawing a word", function()
        local plugin = fakePlugin()
        local b = Board:new{ lang = "fr", plugin = plugin }
        local again = Board:new{ lang = "fr", plugin = plugin, data = b:serialize() }
        assert.is_true(again.loaded)
        assert.are.equal(b.secret, again.secret)
        assert.are.equal(1, #plugin.store.seen_words_fr)
    end)

    it("party: no repeat within a match", function()
        local plugin = fakePlugin()
        local m = HangmanParty.new{ names = { "A", "B" }, rounds = 10, lang = "en", plugin = plugin }
        local words = { [m.board.secret] = true }
        for _r = 2, 10 do
            m = HangmanParty.load(m:serialize(), plugin)
            m:startRound()
            assert.is_nil(words[m.board.secret], m.board.secret)
            words[m.board.secret] = true
        end
        -- The match's own words are left out even when the history would
        -- allow them: all words but three used, the next three are those.
        local all, left = Board.getWordList("en"), {}
        m.used = {}
        for k = 4, #all do m.used[#m.used + 1] = all[k] end
        for _r = 1, 3 do
            m:startRound()
            left[m.board.secret] = true
        end
        assert.is_true(left[all[1]] and left[all[2]] and left[all[3]])
    end)

    it("party: shares the history with solo games; typed words are not remembered", function()
        local plugin = fakePlugin()
        local b = Board:new{ lang = "en", plugin = plugin }
        local m = HangmanParty.new{ names = { "A", "B" }, rounds = 3, lang = "en", plugin = plugin }
        assert.are_not.equal(b.secret, m.board.secret)
        assert.are.equal(2, #plugin.store.seen_words_en)
        HangmanParty.new{ names = { "A", "B" }, rounds = 3, lang = "en", plugin = plugin,
                          word_source = "typed" }
        assert.are.equal(2, #plugin.store.seen_words_en)
    end)
end)

describe("word lists", function()
    for _i, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": A-Z, no duplicates, family-friendly", function()
            local list, set = require("board").getWordList(lang), {}
            for _j, w in ipairs(list) do
                assert.is_truthy(w:match("^[A-Z]+$"), w)
                assert.is_nil(set[w], w)
                set[w] = true
                assert.is_false(Blocklist.isBlocked(w, lang), w)
            end
            assert.is_true(#list > 7500, tostring(#list))
        end)
    end
end)
