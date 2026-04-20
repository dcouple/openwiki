---
date: 2026-04-19
topic: Karpathy LLM Wiki pattern, LLM-maintained Obsidian vault structures, PARA/Zettelkasten/LYT for LLM agents
tags: [llm-wiki, karpathy, obsidian, pkm, para, zettelkasten, lyt, claude-code, agentic-memory, second-brain]
status: draft
sources_count: 27
---

# LLM-Maintained Knowledge Bases: Karpathy's LLM Wiki Pattern and PKM Framework Adaptations (2024-2026)

## Research Question

How are personal knowledge bases being restructured for LLM-agent authorship and maintenance in 2024-2026? Specifically: what is Andrej Karpathy's "LLM Wiki" pattern, what folder/frontmatter conventions are emerging for LLM-maintained Obsidian vaults, and how do established PKM frameworks (PARA, Zettelkasten, LYT) map onto agent-driven workflows?

## Executive Summary

In early April 2026, Andrej Karpathy publicized a pattern — now widely called the **"LLM Wiki"** or **"LLM Knowledge Base"** — in which a long-context LLM (typically Claude via Claude Code) is given ownership of a plain-markdown vault that it *compiles, cross-links, and lints* rather than merely retrieves from. The original X post (Apr 3, 2026) plus a follow-up GitHub gist "idea file" went viral (16M+ views; 2,100+ stars in 12h) and spawned at least a dozen open-source implementations within two weeks [VentureBeat][MindStudio][gist].

The core thesis: for knowledge bases in the 50k-400k-word range, the bottleneck is **bookkeeping**, not retrieval. Modern long-context models can hold the index + relevant pages in context, so RAG's vector-DB complexity is unnecessary; instead the LLM acts as a "librarian" who writes summaries, creates `[[wikilinks]]`, and periodically lints for contradictions. The vault is a **persistent, compounding artifact** rather than an ephemeral retrieval target [gist][VentureBeat][Level Up Coding].

Across implementations, a three-layer architecture has stabilized: **raw/** (immutable sources) → **wiki/** (LLM-authored pages) → **CLAUDE.md / AGENTS.md** (schema + operating procedures). The four canonical agent operations are **ingest, query, lint, crystallize** (with some systems adding *compile* and *integrate* as separate skills).

Established PKM frameworks are being selectively grafted on:

- **PARA** (Forte): maps naturally to agent memory — `Projects/` `Areas/` `Resources/` `Archives/` with a `sessions/` log for append-only agent working memory. Transparent, git-diffable, portable [ArceApps].
- **Zettelkasten**: the theoretical template for **A-MEM** (Xu et al., arXiv:2502.12110) — an *agentic* memory system that generates keyword/tag/context fields per atomic note, links via cosine + LLM-filtered pairs, and evolves old notes when new links form. Reports 85-93% token reduction vs. baselines [A-MEM arXiv].
- **LYT / ACE** (Milo): *Atlas / Calendar / Efforts* head-spaces translate well to agent-facing "knowledge / time / action" partitions. Maps of Content (MOCs) function as human-authored navigation surfaces for agent context priming [LYT blog][Yu WenHao].

Main critiques: error-compounding from repeated summarization, loss of source traceability, hallucinations baked into pages as "facts," and a narrow useful-scale window (thousands of docs: RAG simpler; millions: vector DB required) [Medium/Gupta][HN]. Hybrid approaches (wiki + RAG fallback; confidence scores; supersession tracking) are emerging in "LLM Wiki v2" proposals [Gist v2].

## Detailed Findings

### 1. Karpathy's LLM Wiki Pattern (Apr 3-4, 2026)

**Origin**: Karpathy's X post — *"LLM Knowledge Bases. Something I'm finding very useful recently: using LLMs to build personal knowledge bases for various topics of research interest. In this way, a large fraction of my recent token throughput is going less into manipulating code, and more into manipulating knowledge stored as markdown and images."* [Karpathy X]. A follow-up gist (442a6bf555914893e9891c11519de94f) codifies the architecture [gist].

**Core principle**: *"The tedious part of maintaining a knowledge base is not reading or thinking — it's bookkeeping."* LLMs do the bookkeeping for near-zero marginal cost; humans curate sources and ask questions [gist].

**Three-layer architecture**:

| Layer | Role | Mutability |
|---|---|---|
| Raw sources | Articles, papers, PDFs, images, transcripts | Immutable — LLM reads, never writes |
| Wiki | Summaries, entity pages, concept pages, index | LLM-owned; created/updated on every ingest |
| Schema (CLAUDE.md) | Folder map, naming conventions, operation workflows | Human + LLM co-evolve |

**Canonical operations**:

- **Ingest**: drop source → LLM reads → summarizes → updates 10-15 related wiki pages → appends to log.
- **Query**: ask question → LLM reads index + relevant pages → cites answer → can file valuable answers back as new pages.
- **Lint**: periodic health-check → contradictions, stale claims, orphan pages, missing cross-refs, data gaps.

**Canonical files**:
- `index.md` — content-oriented catalog (one-line summary per page, by category) updated on every ingest.
- `log.md` — append-only chronology with consistent prefixes for parseability.

**Why not RAG (in Karpathy's framing)**: for 50k-100k words, the entire wiki fits in context. A query is a single inference call. No embeddings, no vector DB, no chunking-boundary bugs. The wiki *is* a pre-compiled retrieval result that accumulates instead of being rederived [gist][VentureBeat].

### 2. LLM-Maintained Obsidian Vault Implementations (2026)

At least ten public Claude Code / Codex plugins implement the pattern. Representative folder schemas:

**`NicholasSpisak/second-brain`** [GH]:
```
your-vault/
├── raw/              # inbox + assets/
├── wiki/
│   ├── sources/      # source summaries
│   ├── entities/     # people, orgs, products, tools
│   ├── concepts/     # ideas, frameworks, theories
│   ├── synthesis/    # comparisons, analyses
│   ├── index.md
│   └── log.md
├── output/
└── CLAUDE.md
```
Commands: `/second-brain`, `/second-brain-ingest`, `/second-brain-query`, `/second-brain-lint`. Generates configs for 40+ agents (Claude Code, Codex, Cursor, Gemini CLI, etc.) so multiple agents share one vault [second-brain GH].

**`Ar9av/obsidian-wiki`** [AGENTS.md]:
```
vault/
├── index.md, log.md, .manifest.json
├── _meta/taxonomy.md, _insights.md
├── _raw/
├── concepts/, entities/, skills/, references/
├── synthesis/, journal/, projects/
```
Required frontmatter on every page: `title, category, tags, sources, created, updated`. Skill routing matrix maps user intent → skill (`wiki-ingest`, `wiki-query`, `wiki-update`, `wiki-lint`, `cross-linker`, `wiki-export`, history-ingest skills per agent). Visibility tags (`public/internal/pii`) shape filtered output. Core rule: *"Compile, don't retrieve — update pages, don't duplicate."*

**`vanillaflava/llm-wiki-claude-skills`** — five skills: `wiki-ingest`, `wiki-query`, `wiki-lint`, `wiki-integrate` (weaves new pages into graph), `wiki-crystallize` (*distils a working session or accumulated conversation into a structured wiki page*). Introduces `changes:` frontmatter field tracing each page to its source in `ingested/` [GH].

**`ussumant/llm-wiki-compiler`** and **`rvk7895/llm-knowledge-bases`** — emphasize hierarchical reading strategy: `wiki/hot.md` (recent cache) → `wiki/index.md` → domain sub-indexes → specific pages. `/wiki` slash command bootstraps, `/ingest-url`, `/process-inbox`, `/lint-wiki` for day-to-day ops [GH][MindStudio].

**`kytmanov/obsidian-llm-wiki-local`** — 100% local via Ollama; privacy-focused variant [GH].

**Common conventions across implementations**:
- Plain markdown + Obsidian `[[wikilinks]]` (never proprietary formats).
- YAML frontmatter required; fields commonly include `type`, `status`, `tags`, `sources`, `created`, `updated`, `ai-generated`, `confidence`.
- CLAUDE.md (or AGENTS.md) holds: folder map, naming rules, schema hints, operation workflows, tool/skill routing.
- Log file is append-only with parseable prefixes.
- Everything is git-versioned so rollbacks are one command.

### 3. PARA for LLM Agent Memory

Tiago Forte's Projects/Areas/Resources/Archives maps cleanly to file-based agent memory [ArceApps]:

```
memory/
├── MEMORY.md              # agent constitution (human-maintained)
├── Projects/              # active work with defined endpoints
├── Areas/                 # ongoing responsibilities, no end date
├── Resources/             # reference material
├── Archives/              # completed items, organized by year
└── sessions/              # dated working logs (today + 2-3 prior)
```

Session protocol (encoded in MEMORY.md): agent reads `MEMORY.md` → today's log → relevant project file; writes: session summary → project updates → archival decisions.

**Transparency benefits** that file-based PARA provides over proprietary memory APIs:
- Auditability (open any file in a text editor)
- Correctability (edit files, no API)
- Portability (same markdown across VS Code, Obsidian, Logseq, Neovim)
- Version control (git)
- Grep-able search (no embeddings latency)

MCP tooling (Obsidian MCP server, Logseq MCP) exposes `read_file / write_file / search` primitives so the agent sees the vault as a structured API rather than a file tree [MorphLLM][ChatForest].

### 4. Zettelkasten for LLM Agents — A-MEM

A-MEM (Xu et al., Feb 2025, arXiv:2502.12110) is the most-cited academic adaptation [arXiv][DeepPaper][Alpha's Manifesto]. Each memory note contains:

1. Original content + timestamp
2. LLM-generated keywords
3. Categorical tags
4. Contextual description
5. Embedding over *all* fields concatenated
6. Initial link set (populated post-hoc)

**Link generation** is two-step: (a) cosine-similarity top-k candidates, (b) LLM filter to prevent surface-level keyword false positives.

**Memory evolution**: when new memories link to existing ones, the old notes are *rewritten* with the new context. E.g., "user owns a dog" → "user owns a young dog going through a teething phase." Ablation shows both steps matter: *"Linking alone more than doubles performance. Evolution adds another meaningful bump on top."*

**Cost**: 1,200-2,500 tokens per operation (85-93% reduction vs. baselines); ~$0.0003/op on GPT-4o-mini; 5.4s latency [A-MEM].

**Risk flagged**: three decision points per memory (construction, link evaluation, evolution) = three chances per memory for a hallucination to enter and then *propagate* through evolution [Alpha's Manifesto].

### 5. LYT / ACE for LLM Agents

Nick Milo's **ACE** framework [LYT Blog] — downloaded by 100k+ users through Ideaverse Lite/Pro:

- **Atlas** (knowledge) — "Where would you like to go?"
- **Calendar** (time) — "What's on your mind?"
- **Efforts** (action) — "What can you work on?"

Additional marker folders: `+` (inbox), `x` (extra/archive). Ideaverse Pro layer adds **Maps of Content (MOCs)** — human-authored index pages full of `[[wikilinks]]` that serve as navigation hubs rather than folders [LYT][Yu WenHao].

**Why this works for agents**:
- MOCs give the LLM curated entry points (much like `index.md` in Karpathy's schema).
- ACE's head-space framing maps to agent roles: Atlas = semantic memory; Calendar = episodic/session memory; Efforts = task/project memory.
- Milo explicitly frames ACE as *"flexible enough to grow with you (and your AI)"* [LYT landing page].

**Caveat**: LYT itself is *human-facing* — ACE does not ship an ingest/query/lint loop. Users integrating LYT with Karpathy-style agents typically layer skills on top of Atlas/Calendar/Efforts rather than replacing the framework.

### 6. Hybrid Systems: Johnny Decimal + Zettelkasten + AI Librarian

`jabez007/johnny-decimal-zettelkasten` [GH] combines:
- **Johnny Decimal** for deterministic structural addresses (`AC.ID` format, hex-based for density)
- **Zettelkasten** for emergent linking
- **AI librarian agents** operating under *"Proposal-First mandate"* — propose changes, never modify without explicit approval

This is a response to the agent-autonomy risk: structure + emergence + human-in-the-loop gatekeeping.

### 7. LLM Wiki v2 — Extensions and Corrections

`rohitg00`'s "LLM Wiki v2" gist [Gist v2] incorporates lessons from building `agentmemory`:

- **Confidence scoring** and **supersession** (old claims marked stale when contradicted).
- **Forgetting curves** (Ebbinghaus-style decay unless reinforced).
- **Four-tier consolidation**: working → episodic → semantic → procedural memory (mirrors cognitive psychology).
- **Typed entity graph**: replaces flat markdown with relationships like *"A caused B, confirmed by 3 sources, confidence 0.9."*
- **Hybrid search**: BM25 + embeddings + graph traversal with reciprocal rank fusion — acknowledges pure long-context wiki breaks past ~200 pages.
- **Event-driven automation**: auto-ingest on new sources, auto session-compress at end, periodic decay lint.

This is the most thoughtful critique of "pure" Karpathy — it keeps the markdown-first compounding artifact but restores RAG-adjacent machinery where long-context alone fails.

## Comparison Table: PKM Frameworks as Agent Substrates

| Framework | Primitive | Works for agents because… | Weakness as agent substrate |
|---|---|---|---|
| **Karpathy LLM Wiki** | Markdown page + `[[wikilinks]]` + index + log | Designed from the ground up for LLM-as-author | No confidence/supersession; scale ceiling ~200-400 pages |
| **PARA** (Forte) | 4 folders by actionability | Simple, transparent, maps to agent session/project/reference memory | No linking discipline; no lint loop; purely organizational |
| **Zettelkasten / A-MEM** | Atomic note + dense links | Emergent graph; proven to reduce tokens 85-93% in A-MEM | Three LLM decisions per note = hallucination propagation risk |
| **LYT / ACE** (Milo) | Atlas/Calendar/Efforts + MOCs | MOCs = human-curated entry points agents can prime on | Human-facing; no built-in agent operations |
| **Johnny Decimal** | Hex-coded addresses | Deterministic — agent can address any note by ID | Rigid; fights emergent reorganization |
| **Hybrid (jabez007)** | JD addresses + ZK links + proposal-first agent | Structure + emergence + human oversight | More moving parts |

## Best Practices (2026 Consensus)

1. **Three-layer discipline**: keep raw sources immutable; let the LLM own a wiki layer; put operating procedures in a single CLAUDE.md/AGENTS.md schema file [gist][second-brain][obsidian-wiki].

2. **Required frontmatter on every LLM-authored page**: `title, category, tags, sources, created, updated` at minimum; add `ai-generated: true`, `confidence`, `changes:` (link back to source) for traceability [obsidian-wiki][vanillaflava][Gist v2].

3. **Hierarchical read path**: hot cache → master index → domain sub-index → page body. Don't let the agent re-scan the whole vault every query [rvk7895][ussumant].

4. **Append-only log + manifest**: every ingest, query, and lint operation logged with parseable prefixes so the agent can self-audit and users can git-diff changes [gist][obsidian-wiki].

5. **Lint loop is non-optional**: run lint skill periodically to catch broken `[[wikilinks]]`, orphans, contradictions, stale claims. Without it, the wiki decays into noise [gist][second-brain][vanillaflava].

6. **Proposal-first agent mandate for destructive ops**: especially for bulk reorganization, have the agent propose changes and require explicit approval before write [jabez007].

7. **Use Obsidian `[[wikilinks]]` — never proprietary link formats**: preserves portability across editors and git [second-brain][obsidian-wiki][ArceApps].

8. **Separate fleeting/inbox from consolidated wiki**: `inbox/` or `raw/` stages material; only consolidated, de-duplicated knowledge lives in `wiki/` [second-brain][aimaker].

9. **MCP server or file-system access, not custom ingestion pipelines**: let Claude Code / Cursor / Codex read the vault directly; avoid bespoke servers [ArceApps][MorphLLM].

10. **Design for multi-agent compatibility**: ship AGENTS.md (neutral) alongside CLAUDE.md so different assistants share the same schema [obsidian-wiki][second-brain].

## Common Pitfalls

1. **Summarization compounding** — if the LLM re-summarizes its own summaries on repeated ingest, detail decays into vagueness. Mitigation: always link back to immutable raw source; require quote-level citations [Medium/Gupta][Alpha's Manifesto].

2. **Hallucinations as "facts"** — well-formatted markdown confers unwarranted authority. Mitigation: `ai-generated: true` flag; confidence scores; separate AI-written from human-written pages [Medium/Gupta][HN].

3. **Lost source traceability** — when answers come from generated synthesis pages, "where did this come from?" becomes hard. Mitigation: mandatory `sources:` frontmatter + inline citations [Medium/Gupta].

4. **Scale mismatch** — pattern breaks below ~100 pages (overkill) and above ~1000 pages (context ceiling). Mitigation: know which regime you're in; fall back to RAG above 1000 pages [HN][Gist v2].

5. **Error evolution in A-MEM-style systems** — evolving old notes means mistakes don't sit in one place, they propagate. Mitigation: immutable `original_content` field; evolution in separate field [Alpha's Manifesto].

6. **De-skilling / losing grunt-work insights** — several HN commenters argued that the organization work itself generates insight. Mitigation: keep a "quarantined" human-only note layer [HN].

7. **LYT / ACE doesn't ship agent skills** — importing the framework without adding ingest/query/lint gives you pretty folders and no automation [LYT landing page].

8. **Using vector DB when long-context would do** — under 100k words, RAG overhead often exceeds its benefit for this use case [gist][VentureBeat].

## Confidence Assessment

| Claim | Confidence | Basis |
|---|---|---|
| Karpathy posted LLM Wiki April 3, 2026 | High | Multiple sources confirm [Karpathy X][VentureBeat][MindStudio] |
| Three-layer architecture (raw/wiki/schema) is consensus | High | Independent repos converge on it [gist][second-brain][obsidian-wiki][vanillaflava] |
| Ingest/Query/Lint are canonical operations | High | Present in almost every implementation |
| PARA folder layout works well for agent memory | Medium-High | Widely advocated [ArceApps] but fewer formal evaluations |
| A-MEM achieves 85-93% token reduction | Medium | Reported in arXiv paper; not yet widely replicated |
| LYT/ACE is AI-compatible by Milo's intent | Medium | Landing page mentions "Linking Your AI" but product detail not yet public |
| Pattern has a narrow scale window (~100-1000 pages) | Medium-High | Consistent critique across HN + Medium pieces [HN][Medium/Gupta][Gist v2] |
| Hallucination compounding is a real risk | High | Raised across multiple critiques; supported by A-MEM's three-decision-points analysis |
| `[[wikilinks]]` are the de-facto link format | High | Universal across implementations |
| CLAUDE.md / AGENTS.md is the de-facto schema file | High | Universal across Claude Code, Codex, Cursor integrations |

## Sources

### Primary (Karpathy)
- [Andrej Karpathy on X: LLM Knowledge Bases post](https://x.com/karpathy/status/2039805659525644595) — original post
- [Karpathy's LLM Wiki gist (idea file)](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — architecture reference

### Coverage & Explainers
- [VentureBeat: Karpathy shares 'LLM Knowledge Base' architecture that bypasses RAG](https://venturebeat.com/data/karpathy-shares-llm-knowledge-base-architecture-that-bypasses-rag-with-an)
- [MindStudio: What Is Andrej Karpathy's LLM Wiki?](https://www.mindstudio.ai/blog/andrej-karpathy-llm-wiki-knowledge-base-claude-code)
- [MindStudio: Build an AI Second Brain with Claude Code and Obsidian](https://www.mindstudio.ai/blog/build-ai-second-brain-claude-code-obsidian)
- [Level Up Coding: Beyond RAG — How Karpathy's LLM Wiki Pattern Builds Compounding Knowledge](https://levelup.gitconnected.com/beyond-rag-how-andrej-karpathys-llm-wiki-pattern-builds-knowledge-that-actually-compounds-31a08528665e)
- [Analytics Vidhya: LLM Wiki Revolution](https://www.analyticsvidhya.com/blog/2026/04/llm-wiki-by-andrej-karpathy/)
- [Techstrong.ai: Karpathy's Instructions for Building an AI-Driven Second Brain](https://techstrong.ai/features/karpathys-instructions-for-building-an-ai-driven-second-brain/)

### Open-Source Implementations (Obsidian + Claude Code)
- [NicholasSpisak/second-brain](https://github.com/NicholasSpisak/second-brain)
- [Ar9av/obsidian-wiki — AGENTS.md](https://github.com/Ar9av/obsidian-wiki/blob/main/AGENTS.md)
- [vanillaflava/llm-wiki-claude-skills](https://github.com/vanillaflava/llm-wiki-claude-skills)
- [ussumant/llm-wiki-compiler](https://github.com/ussumant/llm-wiki-compiler)
- [rvk7895/llm-knowledge-bases](https://github.com/rvk7895/llm-knowledge-bases)
- [kytmanov/obsidian-llm-wiki-local (Ollama-local)](https://github.com/kytmanov/obsidian-llm-wiki-local)
- [AgriciDaniel/claude-obsidian](https://github.com/AgriciDaniel/claude-obsidian)
- [ekadetov/llm-wiki](https://github.com/ekadetov/llm-wiki)
- [nvk/llm-wiki](https://github.com/nvk/llm-wiki)
- [jabez007/johnny-decimal-zettelkasten](https://github.com/jabez007/johnny-decimal-zettelkasten) — JD+ZK+AI librarian hybrid
- [rohitg00 — LLM Wiki v2 gist (extensions)](https://gist.github.com/rohitg00/2067ab416f7bbe447c1977edaaa681e2)

### Zettelkasten / Agentic Memory Academic
- [A-MEM: Agentic Memory for LLM Agents (arXiv:2502.12110)](https://arxiv.org/abs/2502.12110)
- [A-MEM HTML version](https://arxiv.org/html/2502.12110v11)
- [Alpha's Manifesto — A-MEM: Zettelkasten for agents](https://blog.alphasmanifesto.com/2026/04/11/a-mem-zettelkasten-for-agents/)
- [Deep Paper — A-MEM explainer](https://deep-paper.org/en/paper/2502.12110/)
- [joshylchen/zettelkasten — AI-powered Zettelkasten with CEQRC](https://github.com/joshylchen/zettelkasten)

### PARA / PKM Frameworks
- [ArceApps: The PARA Method and File-Based AI Memory](https://arceapps.com/blog/para-method-file-based-ai-memory/)
- [Building a Second Brain: The AI Second Brain](https://www.buildingasecondbrain.com/ai-second-brain)
- [LYT Blog — ACE Folder Framework](https://blog.linkingyourthinking.com/notes/ace-folder-framework)
- [Linking Your Thinking (Nick Milo) — landing](https://www.linkingyourthinking.com/)
- [Ideaverse Pro](https://www.linkingyourthinking.com/ideaverse-pro)
- [Obsidian PKM Guide: Building LYT with AI (Yu WenHao)](https://yu-wenhao.com/en/blog/lyt-framework-guide/)
- [Nick Milo on X: "Your AI needs a home"](https://x.com/NickMilo/status/2018008419047993518)

### Critiques
- [Medium/Gupta: Karpathy's LLM Wiki is a Bad Idea](https://medium.com/data-science-in-your-pocket/andrej-karpathys-llm-wiki-is-a-bad-idea-8c7e8953c618)
- [Hacker News: LLM Wiki – example of an "idea file"](https://news.ycombinator.com/item?id=47640875)
- [Hacker News: Show HN — LLM Wiki OSS implementation](https://news.ycombinator.com/item?id=47656181)
- [DEV: Karpathy's LLM Wiki is right, I just didn't want to run it locally](https://dev.to/hjarni/karpathys-llm-wiki-is-right-i-just-didnt-want-to-run-it-locally-170m)

### Tooling (MCP / Obsidian)
- [MorphLLM: Obsidian MCP Server — Connect Your Vault to AI Agents (2026)](https://www.morphllm.com/obsidian-mcp-server)
- [ChatForest: MCP and PKM — How AI Agents Connect to Obsidian, Notion, Logseq, etc.](https://chatforest.com/guides/mcp-personal-knowledge-management-pkm/)
- [Obsidian Forum: LLM Wiki plugin showcase](https://forum.obsidian.md/t/new-plugin-llm-wiki-turn-your-vault-into-a-queryable-knowledge-base-privately/113223)

### Practitioner Walkthroughs
- [aimaker.substack — How I Took Karpathy's LLM Wiki and Built a Second Brain in Obsidian](https://aimaker.substack.com/p/llm-wiki-obsidian-knowledge-base-andrej-karphaty)
- [thetoolnerd — Step-by-Step Guide: Build Your Own AI Second Brain with Obsidian + Karpathy's Pattern](https://www.thetoolnerd.com/p/step-by-step-guide-build-your-own-second-brain-obsidian-kaparthy)
- [Medium/Mart Kempenaar: Turning Obsidian into an AI-Native Knowledge System](https://medium.com/@martk/turning-obsidian-into-an-ai-native-knowledge-system-with-claude-code-27cb224404cf)
- [eferro: My second brain — markdown, Dropbox, and an AI agent](https://www.eferro.net/2026/04/my-second-brain-markdown-dropbox-and-ai.html)
- [Louis Wang: Building a Self-Improving Personal Knowledge Base Powered by LLM](https://louiswang524.github.io/blog/llm-knowledge-base/)
- [Substack/Nandigam: Andrej Karpathy's LLM Wiki — Full Breakdown](https://nandigamharikrishna.substack.com/p/andrej-karpathys-llm-wiki-full-breakdown)

## Open Questions

1. **Scale ceiling**: Where exactly does the pure-markdown approach break? Reports range from "200 pages" (rvk7895 reading strategy) to "400k words / 100 articles" (Karpathy). Empirical benchmarks still missing.

2. **Evaluation of A-MEM in production**: the 85-93% token reduction is reported in controlled academic benchmarks; no public case study of long-running personal use yet.

3. **Multi-agent collision**: several implementations claim multi-agent compatibility via shared AGENTS.md, but no public study of two agents writing concurrently to the same vault.

4. **Loss of "organization insight"**: the HN critique that users lose thinking by outsourcing organization — is this empirically supported or conservative speculation?

5. **LYT + Karpathy merger**: Nick Milo's forthcoming "Linking Your AI" product (referenced on LYT landing page) isn't yet public. How does ACE formally integrate agent skills?

6. **Supersession vs. immutability trade-off**: LLM Wiki v2 proposes evolving old pages with confidence decay; Karpathy's original implies pages are updated freely. Which produces more accurate long-term knowledge?

7. **Privacy / local-first**: Ollama-based implementations (kytmanov) exist but are slower; is there a quality threshold below which local models can't maintain a wiki competently?

8. **When is a codebase a knowledge base?**: `obsidian-wiki` auto-detects codebase vs. knowledge project and proposes different article structures. The boundary between code wiki and knowledge wiki is fuzzy.
