---
name: rollback
description: Undo the last deploy by reverting main; do not rewrite history.
when: User says "roll back", "undo last deploy", "revert"
---

1. `cd /site/prod`
2. Show the last 5 commits: `git log -n 5 --oneline main`
3. Revert HEAD: `git revert --no-edit HEAD`
   (creates a NEW commit that undoes the last one; audit-friendly, safe)
4. Rebuild prod's dist from the current prod source (which is now the pre-revert tree):
     cd /site/prod && npm run build
5. Report: "Reverted commit <sha>. New HEAD: <new sha>."

For multi-deploy rollback: `git revert --no-edit HEAD~N..HEAD` and rebuild. Ask the user first.

Note: this does NOT touch /site/dev. If the user also wants dev reset, suggest the `discard-dev` skill.
