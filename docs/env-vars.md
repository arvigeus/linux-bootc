# Environment Variables

Copy `env.example` to `.env` and uncomment the variables you need. The file is gitignored.

> **Warning:** (Containers only) Variable values can end up baked into the image if they are written to config files during provisioning. If your `.env` contains sensitive data, do not publish the resulting image publicly.

## How variables are loaded

**`justfile`** — `DISTRO`, `IMAGE_NAME`, and `IMAGE_TAG` are read by `just` directly and never reach the provisioning scripts.

**`build.sh`** — everything else is sourced before provisioning runs. In container builds, `.env` is passed as a secret mount (values won't appear in `podman inspect`). In bootstrap, `.env` is read from the project root.
