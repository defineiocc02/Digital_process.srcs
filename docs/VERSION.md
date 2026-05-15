# Version

## Current

- Version: `v3.3.1-archive`
- Date: 2026-05-15
- Purpose: minimal active source tree, with all removed files preserved under `archive/`.

## Recovery Points

- Full organized snapshot: `archive/full-project-before-core-prune`
- Physical archive of files removed by `039c478`: `archive/deleted-in-039c478/`
- Physical archive of files removed by `110ef75`: `archive/deleted-in-110ef75/`
- Previous core source commit: `039c478`

## Policy

The active Vivado project should stay small. Do not add duplicated helper modules
unless they are required by the two kept RTL cores or their testbenches. Files
removed from active use should be placed under `archive/` before being dropped
from the main project structure.
