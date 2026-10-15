# esm2025-sow: instructions for Claude Code

Read `cmem/INDEX.md` first. It points to the project description and to every saved memory.
When the user asks to remember something, write it as a new file in `cmem/` and add it to
`cmem/INDEX.md`. Do not put memories in this file; keep it as a pointer.

Hard rules (details in `cmem/working_rules.md`):
- Never modify existing scripts unless the user explicitly asks.
- Put your own scripts and intermediate files in `ctemp/`. Keep the root folder clean.
- Any requested edit: minimal change, follow the user's coding style, comment plenty.
- Update `README.md` only when the user asks (they will ask regularly).
- Shared login node (HPC): do not run intensive commands there; submit a SLURM job (qos short, fall back to priority). See `cmem/hpc_slurm.md`.
- SLURM jobs have no internet: downloads and environment setup only on the login node.
- Never write anything to the REMIND output folder (read-only).
