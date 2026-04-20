---
name: new-page
description: Create a standalone page (about, essay, landing).
when: User says "create a new page for X", "add a page about Y"
---

Standalone pages live at /site/dev/src/content/pages/<slug>.md and serve at /<slug>.

1. Determine the slug. Ask the user if not clear.
2. REFUSE reserved slugs: "timeline" (collides with /timeline), "index" (collides with /).
   Ask for a different name.
3. Create the file with frontmatter:
     title: <user's title>
     status: draft
4. Write the body from vault content (once vault exists in 1c) or from a user-supplied prompt.
5. Commit on dev: `git add -A && git commit -m "new page: <slug>"`.
