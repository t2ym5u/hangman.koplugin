# Changelog

All notable changes to this project will be documented in this file.

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
