# Git Worktree and Branch Audit

Date: 2026-07-29  
Repository: `defineiocc02/Digital_process.srcs`  
Active workspace: `D:\ReedZhao\Document\ADC_Digital_PROCESS\proc_vivado\sar_adc_v3`

## Executive conclusion

The repository does not currently have excessive Git worktrees. After pruning,
`git worktree list` contains exactly one registered worktree: the active
workspace above.

The apparent proliferation came from two different sources:

1. a stale Codex temporary directory that was not registered as a Git worktree;
2. several local and remote branches with overlapping or divergent histories.

These must be managed separately. A directory cleanup does not simplify branch
history, and a branch deletion does not reclaim a stale worktree directory.

## Actions completed

- Ran `git worktree prune --verbose`.
- Verified that only the active repository remains registered.
- Moved the unregistered Codex temporary directory out of the active worktree
  area instead of deleting it.

Recoverable archive:

`C:\Users\Administrator\.codex\worktrees_archive\20260515_197f_nf10_nf1_reports`

The archive contains 20 files totaling 271,845 bytes. It was not a Git
worktree and contained NF10/NF1 report material.

## Current branch topology

| Ref | Relationship to `origin/main` | Maintenance judgment |
|---|---:|---|
| `codex/huang-calibration-convergence` | Strict descendant, 0 behind; query ahead count live | Active delivery branch; retain until merged |
| local `main` | tracks `origin/main` | Canonical integration branch |
| local `master` | 1 commit ahead, 0 behind | Redundant local branch after its unique commit is preserved |
| `origin/master` | identical to `origin/main` | Redundant remote alias |
| `origin/legacy-main` | 16 commits unique, 29 commits behind | Divergent historical branch; do not delete without archival |

The remote default branch is `origin/main`. The active calibration branch is a
strict descendant of `origin/main`, so it can be reviewed and merged without
discarding current `main` history.

## Safe convergence sequence

1. Finish and push the current report update on
   `codex/huang-calibration-convergence`.
2. Review and merge that branch into `main`.
3. Verify the merged commit and required release artifacts on `main`.
4. Create an annotated tag and a Git bundle for the unique `legacy-main`
   history before considering remote branch removal.
5. Preserve the one unique local `master` commit by tag, merge, or patch before
   deleting the local branch.
6. Delete `origin/master` only after confirming GitHub's default branch remains
   `main` and no external automation still targets `master`.
7. Run `git fetch --prune` and `git worktree prune` after the branch cleanup.

## Commands for a later approved cleanup

The commands below are intentionally not executed by this audit because they
delete branch references.

```powershell
# Inspect unique history first.
git log --oneline origin/main..origin/legacy-main
git log --oneline origin/main..master

# Example preservation operations.
git tag -a archive/legacy-main-20260729 origin/legacy-main `
  -m "Archive divergent legacy-main before branch cleanup"
git bundle create legacy-main-20260729.bundle origin/legacy-main

# Only after review and explicit approval:
git branch -d master
git push origin --delete master
git fetch --prune
git worktree prune --verbose
```

## Maintenance policy

- Use `main` as the only long-lived integration branch.
- Use `codex/<topic>` for bounded implementation and report work.
- Merge or archive completed topic branches promptly.
- Never delete a divergent branch until its unique commits are captured in a
  tag or bundle and the archive hash is recorded.
- Treat `C:\Users\Administrator\.codex\worktrees` as temporary execution
  storage, not as the authoritative project archive.
- Keep project releases in Git, the delivery package, and the 16-bit project
  zone backup. Do not use a temporary worktree as the only copy.
