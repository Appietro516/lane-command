# Roadmap

## First playable match

The proposed order is 1. Show the fixed map, starting ownership, and bases in a working Web export. 2. Add shared income, barracks purchases, player HUD controls, and purchase tests. 3. Add autonomous CPU purchases and symmetric automatic spawning. 4. Add fixed-corridor combat, with checks for attack timing and cleanup. 5. Add victory, defeat, and full restart, then tune for a short, winnable match and verify both Windows and Web builds.

Sources: S1389629da9a3, S95c42ca9286d

## Expansion and deployment verification

Ticket 6 is the optional follow-on for player-only adjacent neutral claims, including resource deduction, ownership display, invalid-claim rejection, and ownership reset. Ticket 7 uses the existing GitHub Actions and Pages infrastructure to verify live browser startup, one deterministic gameplay interaction, and a meaningful failure case. Retain Windows ZIP artifacts and capture useful screenshots and console errors on failure. Screenshots serve as diagnostics without an art or visual-regression gate.

Sources: S1389629da9a3, S8f6e375bbe16, S95c42ca9286d

## Open questions

- What exact region shapes and arrangement should the authored map use? [S95c42ca9286d, Se50c19e91616]
- Which balance values and CPU purchase priorities should change after playtesting match length and winner tendencies? [S95c42ca9286d, Se50c19e91616]
- Should future territory ownership affect income, building sites, or unit routing, and should the CPU eventually claim regions? [S95c42ca9286d]
