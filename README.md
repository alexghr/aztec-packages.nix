# aztec-packages.nix

Unofficial binary Nix packaging for Aztec development tooling from
[`AztecProtocol/aztec-packages`](https://github.com/AztecProtocol/aztec-packages).

This flake packages prebuilt Aztec release artifacts. It does not build Aztec
from source with Nix. Artifacts are fetched by pinned URL and verified by
cryptographic hash, then patched or wrapped for NixOS compatibility where
required.

## Status

Phase 1 proof of concept. The pinned release is `v4.3.0`.

Working on `x86_64-linux`:

- `aztec --help`
- `aztec-wallet --help`
- `bb-avm --help`
- `nargo --help`

The default package also exposes prefixed tools matching upstream `aztec-up`
behavior: `aztec-bb-cli`, `aztec-nargo`, `aztec-noir-profiler`,
`aztec-forge`, `aztec-cast`, `aztec-anvil`, and `aztec-chisel`.

## Usage

```bash
nix run .#aztec -- --help
nix run .#bb-avm -- --help
nix develop
```

Build the aggregate package:

```bash
nix build .#aztec-bin
```

Downstream projects can use the flake in a development shell:

```nix
{
  inputs.aztec-packages-nix.url = "github:your-user/aztec-packages.nix";

  outputs = { nixpkgs, aztec-packages-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          aztec-packages-nix.packages.${system}.aztec-bin
          pkgs.nodejs_24
          pkgs.pnpm
        ];
      };
    };
}
```

For JavaScript libraries, keep using npm or pnpm in the consuming project:

```bash
pnpm add @aztec/aztec @aztec/aztec.js
```

Nix provides the toolchain, CLIs, native binaries, and contract artifacts; it
does not replace the normal package manager for application dependencies.

## Outputs

```text
packages.${system}.aztec-bin
packages.${system}.aztec-bb
packages.${system}.aztec-contracts
packages.${system}.aztec-node-runtime
packages.${system}.aztec-noir
packages.${system}.default

apps.${system}.aztec
apps.${system}.aztec-wallet
apps.${system}.bb-avm
apps.${system}.nargo

devShells.${system}.default
```

Versioned package names are also generated from `versions.json`, for example
`aztec-bin-v4_3_0`.

## Release Inputs

The `versions.json` manifest is the source of truth. For `v4.3.0` it pins:

- Barretenberg tarballs from the Aztec GitHub release. For `v4.3.0`, this is
  the upstream asset named `barretenberg-avm-amd64-linux.tar.gz`.
- Noir binaries from the `noir-lang/noir` release named by the upstream
  installer `versions` file.
- Aztec CLI npm packages, with a checked-in `node-runtime/package-lock.json`
  and fixed `npmDepsHash`.
- Contract artifacts from `@aztec/noir-contracts.js`,
  `@aztec/noir-test-contracts.js`, `@aztec/protocol-contracts`, and
  `@aztec/l1-artifacts`.

Newer Aztec tags may publish Barretenberg assets under
`AztecProtocol/barretenberg`; the updater checks both repositories.

## Release Updates

Collect release metadata:

```bash
scripts/update-release.sh v4.3.0 --dry-run
scripts/update-release.sh v4.3.0
scripts/update-release.sh v4.4.0 --set-latest
```

After adding a release, regenerate `node-runtime/package-lock.json` for that
version and build once to replace the placeholder `npmDepsHash` reported by
Nix.

`scripts/mirror-release.sh` automates the full local mirror step:

```bash
scripts/mirror-release.sh v4.3.0
```

It updates `versions.json`, `node-runtime/package.json`,
`node-runtime/package-lock.json`, and the release `npmDepsHash`.

## Release Mirror Automation

`.github/workflows/mirror-release.yml` mirrors upstream Aztec releases into pull
requests. It can be triggered manually with a `tag` input, by the daily cron, or
by a `repository_dispatch` event of type `aztec-packages-release`.

The dispatch payload should include either `client_payload.tag` or
`client_payload.release.tag_name`:

```json
{
  "event_type": "aztec-packages-release",
  "client_payload": {
    "tag": "v4.3.0"
  }
}
```

Scheduled runs poll the latest GitHub release from
`AztecProtocol/aztec-packages` and skip work when that tag is already mirrored
as `versions.latest`.

The workflow uses Cachix cache `alexghr` by default. Override it with the
repository variable `CACHIX_CACHE_NAME`. Set the repository secret
`CACHIX_AUTH_TOKEN` to push build results; without it, the workflow configures
Cachix in pull-only mode.

## Smoke Testing

After building or entering a dev shell:

```bash
scripts/smoke-test.sh
scripts/smoke-test.sh ./result
```

By default it checks `aztec`, `bb-avm`, and `nargo`. Override the command list
for partial packages:

```bash
SMOKE_COMMANDS="bb-avm" scripts/smoke-test.sh ./result
```

Networked tests, including `aztec start --local-network`, remain opt-in because
they start Anvil and long-running services.

## Artifact Inspection

Inspect downloaded artifacts or unpacked directories with:

```bash
scripts/inspect-artifacts.sh ./result
scripts/inspect-artifacts.sh ./downloads/barretenberg-avm-amd64-linux.tar.gz
scripts/inspect-artifacts.sh https://github.com/AztecProtocol/aztec-packages/releases/download/v4.3.0/barretenberg-avm-amd64-linux.tar.gz
```

The inspector reports `file`, `ldd`, ELF interpreter, and rpath information
where those tools are available.

## Known Limitations

- `aztec start --local-network` has not been promoted into an automated check.
- The Noir release tarball used here does not include a standalone `acvm`
  binary, so `ACVM_BINARY_PATH` is intentionally not set yet.
- Only `x86_64-linux` is exposed for now; `v4.3.0` does not publish the
  required arm64 Barretenberg tarball.
- This is an unofficial binary distribution. Nix metadata marks native binary
  packages with `sourceProvenance = [ binaryNativeCode ]`.
