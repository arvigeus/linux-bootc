# Reconciliation

Reconciliation keeps a running system in sync with what the build declared. It runs in two phases: **pre** (restore the system to its pre-build state so the build can re-apply from scratch) and **post** (verify the build produced expected results and flag drift).

`reconcile.sh` is the entry point — it coordinates all reconciliation scripts.

## Documentation

See [docs/](../../docs/) for detailed documentation.
