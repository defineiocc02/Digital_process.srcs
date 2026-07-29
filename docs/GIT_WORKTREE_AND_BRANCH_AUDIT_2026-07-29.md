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

## Unified branch topology

| Ref | Relationship to `origin/main` | Maintenance judgment |
|---|---:|---|
| local and remote `main` | Canonical release history | Active integration and delivery branch |
| retired `codex/huang-calibration-convergence` | Fast-forwarded into `main` | Safe to remove after remote verification |
| retired local/remote `master` | No unique commits; both refs were ancestors of unified `main` | Removed after default-branch verification |
| `origin/legacy-main` | 16 unique commits; query behind count live | Divergent historical branch; do not delete without archival |

The remote default branch is `origin/main`. The completed calibration/report
branch was a strict descendant and was integrated with `git merge --ff-only`,
so no merge commit or parallel main history was created.

## Completed convergence

1. Rebuilt and verified the report with the latest academic PDF Skill.
2. Pushed the completed topic branch as a recovery point.
3. Switched the only registered worktree to local `main`.
4. Fast-forwarded `main` to the completed release history.
5. Pushed `main` and verified the remote commit.
6. Removed the merged local and remote topic branch.
7. Verified that local/remote `master` contained no unique commits and removed
   both aliases after confirming GitHub's default branch is `main`.
8. Ran `git fetch --prune` and `git worktree prune --verbose`.

The remaining non-main branch is `legacy-main`. It is not a worktree and
requires a separate history-archival decision before deletion.

## Commands for a later approved cleanup

The commands below are intentionally not executed by this audit because they
delete branch references.

```powershell
# Inspect unique legacy history first.
git log --oneline origin/main..origin/legacy-main

# Example preservation operations.
git tag -a archive/legacy-main-20260729 origin/legacy-main `
  -m "Archive divergent legacy-main before branch cleanup"
git bundle create legacy-main-20260729.bundle origin/legacy-main

# Only after legacy review and explicit approval:
git push origin --delete legacy-main
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
