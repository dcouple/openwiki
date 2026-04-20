---
name: discard-dev
description: Throw away uncommitted and committed changes on dev; reset to main.
when: User says "throw away dev changes", "reset dev", "start over on dev"
---

Dev and prod are linked worktrees of the shared bare repo at /site/repo.git. `main` is prod's
checked-out branch, so we resolve the target commit via prod's HEAD (unambiguous for linked worktrees).

1. `cd /site/dev`
2. `git fetch --all`   # no-op with a local bare repo, safe to keep for symmetry
3. `git reset --hard "$(git -C /site/prod rev-parse main)"`
4. `git clean -ffd`    # remove untracked files + dirs

Report:
- Commits discarded (list from old HEAD to new HEAD)
- Untracked files removed
