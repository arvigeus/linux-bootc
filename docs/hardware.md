# Hardware Configuration

During a bootc container build (`just build`), some utilities may report **build machine's** hardware, instead of target machine's. Optional `.env` variables can override that behavior through shims.

## CPU

**`CPU_CORES`** — override the CPU count reported during a container build. The build machine may have a different number of cores than the target machine; setting this ensures any build step that sizes itself by CPU count uses the right value. Has no effect in bootstrap mode.

```txt
CPU_CORES=8
```

**`CPU_OPTIMIZATION_LEVEL`** — Enables optimized packages compiled for your CPU microarchitecture level (`v2`, `v3`, or `v4`), if available.

To find the highest level your CPU supports:

```sh
/lib/ld-linux-x86-64.so.2 --help
```

```txt
CPU_OPTIMIZATION_LEVEL=v3
```
