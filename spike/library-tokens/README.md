# Library token fixtures (FEAT-082)

`start-2/` is a byte-for-byte copy of the owner's Start 2.0 theme token sources
(`style.css` header, `package.json`, `theme.json`, `assets/src/css/*.css` and one
generated `assets/dist/css/main.css`), taken 2026-10-23 from
`~/_dev/wordpress/starttheme/app/public/wp-content/themes/start-2`. It exercises
the real CSS-variable + theme.json path. Synthetic edge cases (DTCG files, cycles,
excluded folders, symlinks) are generated at run time by
`scripts/LibraryTokenSyncCheck.swift`. Run `scripts/verify_library_token_sync.sh`
(optionally with a live library folder as the only argument).
