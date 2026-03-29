# Deploy Scripts

Deploy scripts run on first boot (container only) to finish setting up the system — installing apps that couldn't be provisioned at build time (Flatpak, AppImages, VS Code extensions) and applying user-space configuration.

Scripts are numbered and run in order by `post-deploy.sh`, driven by `post-deploy.service`.

## Documentation

See [docs/](../../docs/) for detailed documentation.
