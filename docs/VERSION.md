# Version

## Current

- Version: `v3.2.0-core`
- Date: 2026-05-15
- Branch: `master`
- Purpose: keep only the core Vivado/RTL/verification project files.

## Archive Tag

The pre-prune organized snapshot is tagged as:

```bash
git checkout archive/full-project-before-core-prune
```

Use this tag only when old docs, MATLAB scripts, binary snapshot references, or legacy Vivado projects are needed.

## Version Policy

- `core`: current lean working tree, suitable for active RTL development.
- `archive/*`: Git tags used for historical recovery.
- Vivado generated files are never part of versioned source.
