---
name: deploy
description: Merge dev into main, copy dist, serve new version.
when: User says "deploy", "ship", "publish the site", "push to prod"
---

Preconditions: /site/prod is on branch `main`; /site/dev is on branch `dev`.

1. `cd /site/dev`
2. Stage and commit any pending changes on dev:
     git add -A
     git diff --cached --quiet || git commit -m "wip: pre-deploy"
3. SANITY-CHECK BUILD: `npm run build` in /site/dev.
   If it fails: STOP and report the error to the user. Do NOT touch main.
4. `cd /site/prod`
5. Merge dev → main: `git merge dev --no-edit --no-ff`
   (no-ff keeps each deploy as a distinct merge commit in history)
6. Copy the built dist from dev to prod:
     rsync -a --delete /site/dev/dist/ /site/prod/dist/
   (dev and prod share the same source tree after the merge, so dev's dist
   is byte-identical to what a prod rebuild would produce. We copy to save
   time; the merge commit on main still records the deploy in git history.)
7. Report: "Deployed. Commit: <prod HEAD sha>. <N> files in dist."

Safety:
- Do NOT skip the build in step 3. It is the gate.
- Do NOT delete /site/prod/dist before copy — rsync --delete handles it atomically.
