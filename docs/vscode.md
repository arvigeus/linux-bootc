# VS Code Extensions

Shadows the `code` command to track extension installations.

## How it works

| Subcommand                      | Container                     | Baremetal                         |
| ------------------------------- | ----------------------------- | --------------------------------- |
| `code --install-extension <id>` | Records to `extensions.list`  | Installs (unprivileged) + records |
| Everything else                 | Passes through (unprivileged) | Passes through (unprivileged)     |

All `code` commands run unprivileged (via `run_unprivileged`) since VS Code is a user-space tool.

## State directory layout

```
/usr/share/system-state.d/vscode/
  extensions.list      — managed extensions (one per line)
  extensions.base.list — unmanaged baseline (seeded on first reconciliation)
  config               — shell-sourceable vars (CODE_CONF_DIR, etc.)
  settings.json        — merged settings for post-deploy
```

## Post-deploy

`provision/deploy/50-vscode.sh` merges settings and installs extensions:

1. Deep-merges `settings.json` with user's existing settings (if any)
2. Installs all declared extensions

## Reconciliation

Same managed/baseline model:

- **Pre**: Seeds `extensions.base.list` from currently installed extensions
- **Post**: Promotes, self-cleans, flags missing managed and untracked extra extensions

## Related files

- [provision/shims/vscode.sh](../provision/shims/vscode.sh) — build-time shim
- [provision/deploy/50-vscode.sh](../provision/deploy/50-vscode.sh) — post-deploy script
- [scripts/reconciliation/packages/vscode.sh](../scripts/reconciliation/packages/vscode.sh) — reconciliation script
