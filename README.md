# aztec-packages.nix

Unofficial binary Nix packaging for Aztec development tooling from
[`aztec-labs-eng/aztec-node`](https://github.com/aztec-labs-eng/aztec-node).

This flake packages prebuilt Aztec release artifacts.

## Usage

```bash
$ nix run github:alexghr/aztec-packages.nix#aztec -- --version
6.0.0
```

For a ready-to-use Aztec contract development environment:

```bash
$ nix develop github:alexghr/aztec-packages.nix
$ aztec --version
6.0.0
$ aztec start --local-network
```

The development shell provides everything necessary to start building contracts on Aztec:
- `aztec`
- `aztec-bb`
- `aztec-nargo`
- Node.js + Corepack

It also exports `ANVIL_BIN` and `FORGE_BIN` for Aztec's JavaScript testing
helpers.

Follow the official Aztec guide to develop contracts, compile with
`aztec-nargo`/`aztec`, and test against the local network:

https://docs.aztec.network/developers/getting_started_on_local_network

> [!IMPORTANT]
> This flake only provides the environment for contracts development.
> Actual Aztec libraries and dependencies should be installed with npm/yarn as usual
> ```bash
> $ yarn add @aztec-labs/aztec.js@6.0.0 @aztec-labs/accounts@6.0.0 @aztec-labs/noir-contracts.js@6.0.0 @aztec-labs/wallets@6.0.0
> ```

## Channels

This flake exports multiple channels, each following a release of Aztec:

|Channel name|Aztec versions|Live networks|Notes|
|------------|--------------|-------------|-----|
|v6|v6.x.y|Testnet, Mainnet|Stable v6 releases. Use this for development against the live networks.|
|v6-nightly|v6.x.y-nightly.yyyymmdd|None|Nightly v6 builds for local development and trying upcoming features. Stability and live-network compatibility are not guaranteed.|

Each channel comes with a development shell:

```bash
nix develop github:alexghr/aztec-packages.nix#v6
```

## Inspect channel metadata

Print the complete channel metadata as JSON:

```bash
nix run github:alexghr/aztec-packages.nix#info
```

## Flake

You can use this flake as an inputs in your own flake:

```nix
{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.aztec-packages.url = "github:alexghr/aztec-packages.nix";
  inputs.aztec-packages.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, aztec-packages }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          aztec-packages.packages.${system}.v6 # aztec, aztec-bb, aztec-nargo
          pkgs.nodejs_24
          pkgs.corepack
          pkgs.jq
        ];
      };
    };
}
```

Access channel metadata with `lib.channelInfo`:

```bash
nix eval --json github:alexghr/aztec-packages.nix#lib.channelInfo.channels.v6
```
