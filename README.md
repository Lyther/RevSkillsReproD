# RevSkillsReproD

Reproduction wrapper for [dslsdzc/rev-skills](https://github.com/dslsdzc/rev-skills) v0.0.5 (121 reverse-engineering agent skills + multi-tool installer).

**Use boundary:** authorized security research only. Do not use this tree for unauthorized reverse engineering, cracking, or malware activity. See `LICENSE` for wrapper terms; skill docs are CC BY 4.0 and installer/validator code is Apache-2.0. Attribution: dslsdzc/rev-skills.

This wrapper does not modify upstream skill content. It pins the library as a git submodule and runs its real validator in a pinned Node container.

## Prerequisites

- Git (with submodule support)
- Docker Compose v2

Host Node is optional (`make check` only).

## Commands

```bash
make setup    # init submodule + copy .env.example → .env
make up       # build image (runs npm test) and start a healthy workspace
make test     # hermetic: validate 121 skills, unit tests, installer --dry-run
make check    # same gate on host Node
make down     # stop containers
make clean    # stop and remove compose volumes
make rebuild  # docker compose build --no-cache --pull
```

## Limits

- Prototype evaluation wrapper. No production, deployment, or completeness claim.
- No Postgres/Redis: upstream has no datastore.
- Upstream declares zero npm dependencies; there is no lockfile to pin.
- Improving skills is out of scope until this repro is accepted.
