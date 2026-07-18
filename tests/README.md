# Tests

Unit tests for Symo, organized with one subfolder per module (mirroring
`src/symo/`).

```bash
pixi run test           # run everything
bash tests/test.sh core # run one module's tests
```

Tests import the prebuilt package (`tests/symo.mojoc`), which is produced by
`pixi run package`.
