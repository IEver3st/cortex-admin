# es_admin

## Browser UI preview

Edit `ui/` (and regenerate menu data after `shared/actions.lua` changes):

1. `node tools/export-preview-state.mjs` — writes `ui/preview-state.json` from `shared/actions.lua`
2. From repo root: `npx --yes serve ui -l 4173` (or any static server for the `ui` folder)
3. Open `http://127.0.0.1:4173/index.html?preview=1&debug=1`

Without step 1, preview uses a small built-in fallback action list.
