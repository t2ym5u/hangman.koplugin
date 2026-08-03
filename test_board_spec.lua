local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("HangmanBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new / newGame", function()
        it("picks a non-empty secret and starts fresh", function()
            local b = Board:new()
            assert.is_true(#b.secret > 0)
            assert.are.equal(0, b.wrong)
            assert.is_false(b.won)
            assert.is_false(b.lost)
        end)

        it("maxWrong follows difficulty", function()
            assert.are.equal(8, Board:new({ difficulty = "easy" }):maxWrong())
            assert.are.equal(6, Board:new({ difficulty = "medium" }):maxWrong())
            assert.are.equal(4, Board:new({ difficulty = "hard" }):maxWrong())
        end)
    end)

    describe("guess", function()
        it("returns correct for a letter in the secret and reveals it", function()
            local b = Board:new()
            local letter = b.secret:sub(1, 1)
            local result = b:guess(letter)
            assert.is_true(result == "correct" or result == "win")
            assert.is_true(b.guessed[letter:upper()])
        end)

        it("returns wrong and increments the wrong counter for an absent letter", function()
            local b = Board:new()
            -- Find a letter that's definitely not in the secret.
            local absent
            for i = 65, 90 do
                local ch = string.char(i)
                if not b.secret:upper():find(ch, 1, true) then absent = ch; break end
            end
            assert.is_not_nil(absent)
            assert.are.equal("wrong", b:guess(absent))
            assert.are.equal(1, b.wrong)
        end)

        it("returns already for a letter guessed twice", function()
            local b = Board:new()
            local letter = b.secret:sub(1, 1)
            b:guess(letter)
            assert.are.equal("already", b:guess(letter))
        end)

        it("loses once wrong guesses reach maxWrong", function()
            local b = Board:new({ difficulty = "hard" })  -- maxWrong = 4
            local wrong_letters = {}
            for i = 65, 90 do
                local ch = string.char(i)
                if not b.secret:upper():find(ch, 1, true) then
                    wrong_letters[#wrong_letters + 1] = ch
                end
                if #wrong_letters == 4 then break end
            end
            local result
            for _, ch in ipairs(wrong_letters) do
                result = b:guess(ch)
            end
            assert.are.equal("lose", result)
            assert.is_true(b.lost)
            assert.are.equal(1, b.losses)
        end)

        it("wins once every letter of the secret is revealed", function()
            local b = Board:new()
            local seen = {}
            local result
            for i = 1, #b.secret do
                local ch = b.secret:sub(i, i)
                if ch ~= " " and not seen[ch] then
                    seen[ch] = true
                    result = b:guess(ch)
                end
            end
            assert.are.equal("win", result)
            assert.is_true(b.won)
            assert.are.equal(1, b.wins)
        end)

        it("returns done once the game has ended", function()
            local b = Board:new()
            b.won = true
            assert.are.equal("done", b:guess("A"))
        end)
    end)

    describe("getDisplay", function()
        it("hides unguessed letters behind underscores", function()
            local b = Board:new()
            local display = b:getDisplay()
            assert.is_true(display:find("_") ~= nil or #b.secret:gsub("[^A-Z]", "") == 0)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips secret, guesses and score", function()
            local b = Board:new()
            b:guess(b.secret:sub(1, 1))
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.secret, b2.secret)
            assert.are.equal(b.wrong, b2.wrong)
            for k in pairs(b.guessed) do
                assert.is_true(b2.guessed[k])
            end
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
