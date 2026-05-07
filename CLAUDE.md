# Claude Instructions for Cotor

Follow [AGENTS.md](AGENTS.md) as the full repository operating manual. This file exists so Claude Code sessions have the same short source-of-truth routing rules.

## Before Editing

- For architecture, debug, refactor, or cross-module questions, read `graphify-out/GRAPH_REPORT.md` first.
- Do not paste `graphify-out/graph.json` into prompts or docs. It is machine graph data, not assistant context.
- Use `graphify query`, `graphify path`, or `graphify explain` to narrow the relevant subgraph before broad file reading.
- Check [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/modules/README.md](docs/modules/README.md) before adding cross-domain imports or moving files.

## Change Rules

- Avoid new folders or files named only `utils`, `helpers`, `common`, `misc`, `manager`, or `service`; name the domain responsibility.
- Public API, import path, route path, or config path changes require a compatibility shim or migration note.
- New modules require an update to `README.md` or `docs/modules/README.md`.
- Keep English and Korean docs functionally aligned for user-visible behavior.

## Graphify Workflow

- Initial graph build: `graphify .`
- Incremental refresh after code/docs changes: `graphify update .`
- Large boundary/cluster refresh: `graphify cluster-only .`
- Assistant slash-command environments may expose the equivalent forms `/graphify .`, `/graphify . --update`, and `/graphify . --cluster-only`.

After running Graphify, reread `graphify-out/GRAPH_REPORT.md` and confirm it does not contradict the architecture/module docs.
