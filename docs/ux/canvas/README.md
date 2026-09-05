# Design canvas · working files

The visual mockups for the redesign. Live, editable canvas: https://claude.ai/code/artifact/8f796352-9afe-4479-a9f5-23203a2a393e

- `lib.mjs` — tokens (from `../06-design-system.md`) and the components every screen is built from: ring arcs, sparklines, line charts, hypnogram, state chips, vital tiles, the ring status shelf and the tab bar.
- `build.mjs` — one function per screen; writes every `*.dc.html` artboard and `canvas.json`.
- `heights.json` — measured content height per screen so tall frames show the whole scroll.
- `*.dc.html`, `canvas.json` — generated. Edit `build.mjs`, not these.
- `../screens/*.png` — rendered previews of every artboard.

Regenerate:

```bash
node build.mjs            # artboards + canvas.json
```

The seeded canvas file (`careplix-ring-experience.html`) is not committed; it is assembled from the files above when the canvas is updated.
