---
name: update-home
description: Edit the site home page content.
when: User says "update the home page", "change the intro"
---

The home page body lives at /site/dev/src/home.md (NOT /site/dev/src/content/home.md — home is
outside the content-collections tree because it belongs to no collection and is direct-imported
by src/pages/index.astro).

1. Read the current content.
2. Apply the user's requested edit. Preserve the `title` frontmatter field.
3. Commit on dev: `cd /site/dev && git add src/home.md && git commit -m "home: <short desc>"`.
