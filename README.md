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
  inputs.forge.url = "github:shazow/forge.nix";

  outputs = { nixpkgs, aztec-packages, forge }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          aztec-packages.packages.${system}.default
          forge.packages.${system}.default
          pkgs.nodejs_24
          pkgs.corepack
        ];
      };
    };
}
```

For JavaScript libraries, keep using npm/pnpm/yarn in the consuming project:

```bash
yarn add @aztec/aztec@4.3.0 @aztec/aztec.js@4.3.0
```

Nix provides the toolchain, CLIs, native binaries, and contract artifacts; it
does not replace the normal package manager for application dependencies.

Mirrored channels also get package and app aliases. The initial channels are:

```text
v4-stable  -> latest stable v4 release
v4-nightly -> latest v4 nightly release
v5-nightly -> latest v5 nightly release
```

## Known Limitations

- `aztec start --local-network` is manually verified, but has not been promoted
  into an automated check.
- The Noir release tarball used here does not include a standalone `acvm`
  binary, so `ACVM_BINARY_PATH` is intentionally not set yet.
- Only `x86_64-linux` is exposed for now; `v4.3.0` does not publish the
  required arm64 Barretenberg tarball.
- This is an unofficial binary distribution. Nix metadata marks native binary
  packages with `sourceProvenance = [ binaryNativeCode ]`.
