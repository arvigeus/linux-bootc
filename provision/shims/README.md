# Build-time Shims

Shims are lightweight wrappers that sit between your build scripts and the real system commands. When you write `dnf install -y firefox` or `cp config.conf /etc/`, the shim intercepts the call, runs the real command, and silently records what happened. This recording is what makes reconciliation possible — the system knows what the build *intended*, not just what's currently on disk.

Shims are **transparent** — modules use standard shell commands, and everything works the same with or without shims. The only difference is whether state gets recorded for later reconciliation.

In **container builds**, shims execute the real commands but skip state recording (there's nothing to reconcile inside a disposable container).

To **bypass a shim**, use the full path to the real binary: `/usr/bin/cp`, `/usr/bin/rm`, etc.

## Documentation

See [docs/](../../docs/) for detailed documentation.
