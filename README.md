# aztec-packages.nix

Unofficial binary Nix packaging for Aztec development tooling from
[`AztecProtocol/aztec-packages`](https://github.com/AztecProtocol/aztec-packages).

This flake packages prebuilt Aztec release artifacts.

## Usage

```bash
nix run .#aztec -- --help
```

Downstream projects can use the flake in a development shell:

```nix
{
  inputs.aztec-packages.url = "github:alexghr/aztec-packages.nix";
  inputs.foundry.url = "github:shazow/foundry.nix";

  outputs = { nixpkgs, aztec-packages, foundry }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          aztec-packages.packages.${system}.default
          foundry.packages.${system}.default
          pkgs.nodejs_24
          pkgs.corepack
        ];
      };
    };
}
```

Local-network and contract workflows need `anvil` on `PATH`; provide Foundry
from `github:shazow/foundry.nix` or another external source.

For JavaScript libraries, keep using npm/pnpm/yarn in the consuming project:

```bash
yarn add @aztec/aztec@4.3.0 @aztec/aztec.js@4.3.0
```

Nix provides the toolchain, CLIs, native binaries, and contract artifacts; it
does not replace the normal package manager for application dependencies.

Current `@aztec/bb.js` releases bundle a Linux `bb` binary that does not run on
NixOS. From a consuming project, after install:

```bash
aztec_pkg=$(nix build --no-link --print-out-paths github:alexghr/aztec-packages.nix#default)
ln -sf "$aztec_pkg/bin/bb-avm" node_modules/@aztec/bb.js/build/amd64-linux/bb
```

Use the same flake channel as the Aztec packages in the project.

Mirrored channels also get package and app aliases. The initial channels are:

```text
v4-stable  -> latest stable v4 release
v4-nightly -> latest v4 nightly release
v5-nightly -> latest v5 nightly release
```

## Known Limitations

- The Noir release tarball used here does not include a standalone `acvm`
  binary, so `ACVM_BINARY_PATH` is intentionally not set yet.
