# Changelog

All notable changes to this project will be documented in this file.

## [1.5.1] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.5.0] - 2026-11-04

### Changed
- Bigger keys in landscape: the keyboard panel beside the drawing takes
  half the screen instead of 36 %, so each key is about 40 % wider and the
  status fits on one line. Portrait is unchanged.
- Needs game-common 1.13.0.
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.
- Uses less memory: the word lists load when the game opens, only for the
  language played, and are freed when it closes.

### Added
- 139 everyday modern English words that the dictionary filter of 1.4.0 had
  dropped because the Scrabble dictionary predates them: EMAIL, ONLINE,
  OFFLINE, LOGIN, LOGOUT, WEBSITE, INBOX, PODCAST, SELFIE, EMOJI, HASHTAG,
  EBOOK, EREADER, plus foods (BAGEL, LATTE, QUINOA, FALAFEL…) and the like.
  Hand-picked, family-friendly, no brands, names or abbreviations. The
  English list now has 8,152 words (8,085 drawn after the family filter).

## [1.4.0] - 2026-11-03

### Changed
- No more repeated words: the game remembers the words already played, per
  language, and draws a new one each time; a word only comes back once
  about 3,000 others have been played. Solo games and multiplayer matches
  share this memory, and a match never uses the same list word twice
  (typed words are not affected).
- English word list cleaned: only words found in the ENABLE Scrabble
  dictionary are kept, so first names, places, brands and abbreviations
  (AARON, ALASKA, ACLU, ASAP…) are no longer drawn. 7,946 words are drawn.

### Fixed
- README listed features the game never had (word length, categories,
  ASCII drawing, statistics).

## [1.3.0] - 2026-11-02

### Added
- Multiplayer mode for 2 to 4 teams ("Hangman · multiplayer" under Tools →
  Games → Party & quiz, or Mode: Multiplayer in the game menu): the word comes
  from the word list, or a player of each team in turn types a secret one
  (hand-over screen; that team sits the round out). A right letter keeps the
  turn, a wrong one passes it; a team may try the whole word (wrong: −1
  point, one miss, turn passes). The team completing the word scores the
  misses left + 1. Matches of 3/5/7/10 words, team names remembered, final
  scoreboard, match saved and restored apart from the solo game.

### Changed
- Family-friendly words: the secret word is never a vulgar, sexual,
  scatological, slur or drug-related word any more (`blocklist.lua`, applied
  when the word lists load) -- 69 English and 113 French words.

## [1.2.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.2.0] - 2026-10-30

### Added
- "New game" appears under the keyboard once the word is found or the
  hangman is complete, so the next round no longer needs the menu.

### Changed
- Redesigned play screen, in line with the other games: the board fills the
  available room and the status line wraps in landscape instead of being cut
  off. While playing it shows the difficulty and wrong guesses; the
  win/loss score only appears between rounds.
- The letter keyboard is the shared one used by Wordle, Word Ladder and
  Cryptogram, laid out like your own keyboard: it follows KOReader's
  language (AZERTY in French, QWERTZ in German), not the word list's.
  Guessed letters are shaded -- dark for a miss, light for a hit -- instead
  of being replaced by a dot, so you can still see which letters you tried.
- Title-bar menu in the same order as every other game, with the current
  values shown: "Difficulty: Medium" and "Language: EN" instead of bare
  "Medium" and "EN".
- New README screenshot.

### Fixed
- Long words no longer run past the edges of the board: the word and the
  wrong-letters line are sized to fit, whatever letters get revealed.
- The gallows and figure lines were twice as thick as intended on a wide
  board, filling in the head and merging the arms.

## [1.1.15] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.

## [1.1.14] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.1.8] - 2026-07-29

### Fixed
- The English word list was a hand-picked table of only ~100 words, and
  the French word list contained many tokens that were not real French
  words at all — conjugated fragments and garbled/truncated strings
  rather than actual dictionary entries, so players could be asked to
  guess unguessable gibberish. Both lists are now loaded from new
  shared, vetted word files (`words_en.lua`, `words_fr.lua`, also used
  by anagram.koplugin): 9283 English words (Google Books frequency list
  intersected with a proper dictionary to drop proper nouns/typos) and
  9000 French words (OpenSubtitles frequency list intersected with the
  project's Scrabble-valid FR dictionary), both filtered to a
  consistent 4-7 letters.
