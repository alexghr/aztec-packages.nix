# aztec-packages.nix

Unofficial binary Nix packaging for Aztec development tooling from
[`AztecProtocol/aztec-packages`](https://github.com/AztecProtocol/aztec-packages).

This flake packages prebuilt Aztec release artifacts.

## Usage

```bash
nix run github:alexghr/aztec-packages.nix#aztec -- --help
```

For a ready-to-use Aztec contract development environment:

```bash
nix develop github:alexghr/aztec-packages.nix
```

The default shell follows `v4-stable` and includes the Aztec CLI,
Aztec-bundled native tools (`aztec-nargo`, `aztec-bb`, `aztec-forge`,
`aztec-cast`, `aztec-anvil`, `aztec-chisel`), Node.js 24, Corepack, and `jq`.

Channel-specific shells are also available:

```bash
nix develop github:alexghr/aztec-packages.nix#v4-stable
nix develop github:alexghr/aztec-packages.nix#v5-stable
nix develop github:alexghr/aztec-packages.nix#v5-nightly
```

Follow the official Aztec guide to develop contracts, compile with
`aztec-nargo`/`aztec`, and test against the local network:

https://docs.aztec.network/developers/getting_started_on_local_network

Downstream projects can use the flake in a development shell:

```nix
{
  inputs.aztec-packages.url = "github:alexghr/aztec-packages.nix";

  outputs = { nixpkgs, aztec-packages }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          aztec-packages.packages.${system}.v4-stable
          pkgs.nodejs_24
          pkgs.corepack
        ];
      };
    };
}
```

Or enter the same environment directly:

```bash
nix shell \
  github:alexghr/aztec-packages.nix#v4-stable \
  nixpkgs#{nodejs_24,corepack}

# v4 projects using @aztec/bb.js need this until AztecProtocol/aztec-packages#23570 is merged
ln -sfn "$(command -v aztec-bb)" node_modules/@aztec/bb.js/build/amd64-linux/bb

# You now have a full Aztec contract development environment.
# Follow the official Aztec guide to develop contracts, compile with aztec-nargo/aztec,
# and test against the local network.
aztec start --local-network
```

For JavaScript libraries, keep using npm/pnpm/yarn in the consuming project:

```bash
yarn add @aztec/aztec@4.3.0 @aztec/aztec.js@4.3.0
```

Mirrored channels also get package and app aliases. The initial channels are:

```text
v4-stable  -> latest stable v4 release
v5-stable  -> latest stable v5 release
v5-nightly -> latest v5 nightly release
```
