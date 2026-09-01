# Overlay series

Quilt-style patches on the pinned `vendor/rev-skills` commit. The submodule stays clean.

- `series` lists patches in apply order.
- `scripts/apply-overlay.sh` copies the pin into `dist/rev-skills` and applies this series for review and `git format-patch` refresh. Grimoire does not read `dist/`.
- Refresh a patch against a new pin with `scripts/bump-upstream.sh`, then re-cut the series.
- Upstream PRs are the same commits, sent from a throwaway branch of the pin — do not push overlay history into `vendor/`.

Current series:

1. `0001-add-machine-readable-guards-for-sensitive-skills.patch` — `guard` on `re-cracking`, `re-keygen`, `re-exploit` (template already requires this on sensitive skills).
