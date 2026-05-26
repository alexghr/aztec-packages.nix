{
  description = "Unofficial binary Nix flake for Aztec development tooling";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {
    self,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem = {
        config,
        lib,
        pkgs,
        system,
        ...
      }: let
        versions = builtins.fromJSON (builtins.readFile ./versions.json);

        releaseSupportsSystem = release:
          release ? systems
          && builtins.hasAttr system release.systems
          && release.systems.${system} ? barretenberg
          && release.systems.${system} ? foundry
          && release.systems.${system} ? noir;

        mkRelease = tag: release: let
          barretenberg = pkgs.callPackage ./pkgs/barretenberg-bin.nix {
            inherit tag release system;
          };
          noir = pkgs.callPackage ./pkgs/noir-bin.nix {
            inherit tag release system;
          };
          foundry = pkgs.callPackage ./pkgs/foundry-bin.nix {
            inherit tag release system;
          };
          contracts = pkgs.callPackage ./pkgs/contracts.nix {
            inherit tag release system;
          };
          node-runtime = pkgs.callPackage ./pkgs/node-runtime.nix {
            inherit tag release system barretenberg noir contracts foundry;
          };
          aztec-bin = pkgs.callPackage ./pkgs/aztec-bin.nix {
            inherit tag release system barretenberg noir contracts foundry node-runtime;
          };
        in {
          inherit aztec-bin barretenberg contracts foundry node-runtime noir;
        };

        defaultChannel = "v4-stable";
        supportedReleaseDefs = lib.filterAttrs (_: release: releaseSupportsSystem release) versions.releases;
        releases = lib.mapAttrs mkRelease supportedReleaseDefs;
        defaultTag =
          if
            versions ? channels
            && builtins.hasAttr defaultChannel versions.channels
            && versions.channels.${defaultChannel} ? tag
          then versions.channels.${defaultChannel}.tag
          else versions.latest;
        hasDefault = builtins.hasAttr defaultTag releases;
        latest =
          if hasDefault
          then releases.${defaultTag}
          else null;

        mirroredChannels =
          lib.filterAttrs (
            _: channel:
              channel ? tag && builtins.hasAttr channel.tag releases
          )
          (versions.channels or {});

        channelPackages =
          lib.concatMapAttrs (
            channel: metadata: {"${channel}" = releases.${metadata.tag}.aztec-bin;}
          )
          mirroredChannels;

        channelApps =
          lib.concatMapAttrs (
            channel: metadata: {"${channel}" = mkApp "Run the Aztec CLI for ${channel}" "${releases.${metadata.tag}.aztec-bin}/bin/aztec";}
          )
          mirroredChannels;

        mkApp = description: program: {
          type = "app";
          inherit program;
          meta.description = description;
        };
      in {
        formatter = pkgs.writeShellApplication {
          name = "alejandra-wrapper";
          runtimeInputs = [pkgs.alejandra];
          text = ''
            if [ "$#" -eq 0 ]; then
              exec alejandra .
            fi
            exec alejandra "$@"
          '';
        };

        packages =
          (
            lib.optionalAttrs hasDefault {
              default = latest.aztec-bin;
              aztec-bin = latest.aztec-bin;
              aztec-bb = latest.barretenberg;
              aztec-contracts = latest.contracts;
              aztec-foundry = latest.foundry;
              aztec-node-runtime = latest.node-runtime;
              aztec-noir = latest.noir;
            }
          )
          // channelPackages;

        apps =
          (
            lib.optionalAttrs hasDefault {
              default = config.apps.aztec;
              aztec = mkApp "Run the Aztec CLI" "${config.packages.aztec-bin}/bin/aztec";
              aztec-wallet = mkApp "Run the Aztec wallet CLI" "${config.packages.aztec-bin}/bin/aztec-wallet";
              "bb-avm" = mkApp "Run Barretenberg" "${config.packages.aztec-bin}/bin/bb-avm";
              nargo = mkApp "Run Noir nargo" "${config.packages.aztec-bin}/bin/nargo";
            }
          )
          // channelApps;

        checks = lib.optionalAttrs (hasDefault && system == "x86_64-linux") {
          smoke = pkgs.runCommand "aztec-bin-smoke" {} ''
            ${pkgs.bash}/bin/bash ${./scripts/smoke-test.sh} ${config.packages.aztec-bin}
            touch $out
          '';
        };

        devShells.default = pkgs.mkShell ({
            packages =
              lib.optionals hasDefault [
                config.packages.aztec-bin
              ]
              ++ [
                pkgs.git
                pkgs.jq
                pkgs.nodejs_24
                pkgs.pnpm
              ];

            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          }
          // lib.optionalAttrs hasDefault {
            AZTEC_CONTRACTS_DIR = "${config.packages.aztec-bin}/share/aztec/contracts";
          });
      };
    };
}
