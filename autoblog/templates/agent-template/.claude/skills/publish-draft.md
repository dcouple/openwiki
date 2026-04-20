---
name: publish-draft
description: Flip a timeline entry or page from draft to published on dev.
when: User says "publish <slug>", "mark <post> as published"
---

1. Locate the file: ask the user if unclear; otherwise grep /site/dev/src/content/ for the slug.
2. Edit the frontmatter: change `status: draft` to `status: published`.
3. Commit on dev: `cd /site/dev && git add -A && git commit -m "publish: <slug>"`.
4. Recommend running the `deploy` skill next.
