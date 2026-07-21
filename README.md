# aztec-packages.nix

Unofficial binary Nix packaging for Aztec development tooling from
[`AztecProtocol/aztec-packages`](https://github.com/AztecProtocol/aztec-packages).

This flake packages prebuilt Aztec release artifacts.

## Usage

```bash
$ nix run github:alexghr/aztec-packages.nix#aztec -- --version
5.0.1
```

For a ready-to-use Aztec contract development environment:

```bash
$ nix develop github:alexghr/aztec-packages.nix
$ aztec --version
5.0.1
$ aztec start --local-network
anvil Version: 1.4.1-v1.4.1
Commit SHA: cf7746048646f2ecff48246dd61e265e49ab16f0
Build Timestamp: 2025-10-14T13:49:09.432023782Z (1760449749)
Build Profile: maxperf

               _
    /\        | |
   /  \    ___| |_ ___  ___
  / /\ \  |_  / __/ _ \/ __|
 / ____ \  / /| ||  __/ (__
/_/___ \_\/___|\__\___|\___|

https://github.com/AztecProtocol


Setting up Aztec local network 5.0.1, please stand by...
Setting up test accounts
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
> $ yarn add @aztec/aztec.js@5.0.1 @aztec/accounts@5.0.1 @aztec/noir-contracts.js@5.0.1 @aztec/wallets@5.0.1
> ```

## Channels

This flake exports multiple channels, each following a release of Aztec:

|Channel name|Aztec versions|Live networks|Notes|
|------------|--------------|-------------|-----|
|v4-stable[^1]|v4.x.y|None|v4 used to be live on mainnet until v5 was executed. This channel might still be useful if you are migrating state to v5 otherwise consider it **deprecated**.|
|v5-stable|v5.x.y|Testnet, Mainnet|Use this for development against the current live networks.|
|v5-nightly|v5.x.y-nightly.yyyymmdd|None|Nightly builds for the v5 release of Aztec. Generally compatible with live networks but stability is not guaranteed. Useful to try out new features ahead of stable releases.|
|v6-nightly|v6.x.y-nightly.yyyymmdd|None|Nightly builds for the next release of Aztec. Incompatible with any live networks. Only useful for local development and to try out bleeding edge features.|

[^1]: deprecated

Each channel comes with a development shell:

```bash
nix develop github:alexghr/aztec-packages.nix#v5-stable
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
          aztec-packages.packages.${system}.v5-stable # aztec, aztec-bb, aztec-nargo
          pkgs.nodejs_24
          pkgs.corepack
          pkgs.jq
        ];
      };
    };
}
```

