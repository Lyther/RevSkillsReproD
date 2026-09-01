# RevSkillsReproD

Reproduction and overlay workspace for [Lyther/rev-skills](https://github.com/Lyther/rev-skills) (fork of [dslsdzc/rev-skills](https://github.com/dslsdzc/rev-skills)).

Pinned at `bc7fac97` (`v0.0.5` plus the marketplace `0.0.5` sync on `origin/main`). Skill docs CC BY 4.0; tooling Apache-2.0. Attribution: original dslsdzc/rev-skills; pin tracked at Lyther/rev-skills.

**Use boundary:** authorized security research only. Do not use this tree for unauthorized reverse engineering, cracking, or malware activity. See `LICENSE`.

This repo does **not** fork the 121 skills and does **not** replace agent-surface's installer. It keeps a clean vendor pin. `patches/` is a proposed-upstream quilt applied only into gitignored `dist/rev-skills` (never into `vendor/`). Grimoire indexes the matching clean pin in `agent-surface/external/rev-skills` as `rev-skills:<name>`. The indexer stores name, description, and body; extra frontmatter such as overlay `guard` is not a retrieval field until upstream models it.

## What is real

- 121 validated skills (entry + gateways + atomics) in `vendor/rev-skills/.claude/skills`.
- Overlay series in `patches/` (currently machine-readable `guard` on `re-cracking`, `re-keygen`, `re-exploit`).
- Distribution: [agent-surface](../agent-surface) `install` for host wiring; Grimoire indexes this pack as `rev-skills:<skill>` next to `anthropic-cybersecurity-skills`.

## What is not claimed

- Not a complete reverse-engineering product, and not "50+ agent runtimes" or live Claude `/plugin` proof.
- Cross-OS install guidance is not present on every atomic skill.
- `npx rev-skills` on the published npm tarball is unused here; agent-surface is the distributor.

## Prerequisites

- Git (with submodule support)
- Node.js 18+ (overlay apply also needs `rsync` + `git apply`)
- Docker Compose v2 only for `make test` / `make up` on a remote with Docker
- SSH to `dev-box-cpu` for `/ops-server` runs (local Docker is not used)
- Sibling `../agent-surface` to rebuild the Grimoire index

## Commands

```bash
git submodule update --init --recursive
npm test                      # vendor check + overlay apply
npm run test:repro            # vendor/installer only (what the image runs)
npm run test:overlay          # apply patches/ onto dist/rev-skills
make overlay                  # scripts/apply-overlay.sh
make bump-upstream            # REF=origin/main scripts/bump-upstream.sh
node src/repro.mjs install    # Cursor rules from the clean pin
make remote-repro             # rsync to dev-box-cpu, image test + ByteLLM
```

After a pin bump, update `pins/rev-skills.json` and the matching `external/rev-skills` pin in agent-surface, then `npm run install:grimoire` there.

## Limits

- Prototype evaluation workspace. No production, deployment, or completeness claim.
- Generated client rules are local (gitignored). Re-run `node src/repro.mjs install` after a pin bump.
- Overlay output is `dist/rev-skills` (gitignored). The submodule stays clean so cherry-picks stay possible.
