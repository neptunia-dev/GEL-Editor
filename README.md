# PR Changes

This directory contains the files changed for the Editor work in this session.

## Included Changes

- Remove Node Map SVG dependencies and use text button fallbacks.
- Fix `EditorExplorerEntry` type loading without relying on the global class cache.
- Connect Explorer to the live `NodeMapDocument` through an adapter.
- Add in-memory History display and history navigation.
- Add the first Inspector UI for Node state, layout, and parameters.
- Add the `resize_nodes` editor command used by Inspector layout editing.
- Update Explorer display tests for the live Node Map projection.
- Record the current modification-items documentation.

## Source Files

The files are copied with their original relative paths under this directory. Copy or apply
only these files when preparing the commit. Do not include `history.md`, `.godot/`, Engine
dependencies, or Engine build output.

## Suggested Commit

```text
完善 Editor Explorer Inspector 与 History
```

## Verification

```text
Node Map Model: 425 checks
Node Map Compiler: 146 checks
Node Map Editor: 733 checks
Explorer Model: 27 checks
Explorer Display: 20 checks
Engine typecheck: passed
```
