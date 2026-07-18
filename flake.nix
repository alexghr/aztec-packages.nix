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
      ];

      perSystem = {
        config,
        lib,
        pkgs,
        system,
        ...
      }: let
        versions = builtins.fromJSON (builtins.readFile ./versions.json);
        channelDefinitions = builtins.fromJSON (builtins.readFile ./channels.json);
        resolvedChannels = versions.channels or {};
        configuredChannels =
          lib.mapAttrs (
            channel: definition:
              definition
              // lib.optionalAttrs (
                builtins.hasAttr channel resolvedChannels
                && resolvedChannels.${channel} ? tag
              ) {
                tag = resolvedChannels.${channel}.tag;
              }
          )
          channelDefinitions;

        releaseSupportsSystem = release:
          release ? systems
          && builtins.hasAttr system release.systems
          && release.systems.${system} ? foundry
          && release.systems.${system} ? noir;

        bbJsPlatform = {
          x86_64-linux = "amd64-linux";
          aarch64-linux = "arm64-linux";
        };

        mkRelease = tag: release:
          import ./pkgs/release.nix {
            inherit pkgs system tag release;
          };

        defaultChannel = "v4-stable";
        supportedReleaseDefs = lib.filterAttrs (_: release: releaseSupportsSystem release) versions.releases;
        releases = lib.mapAttrs mkRelease supportedReleaseDefs;
        defaultTag =
          if
            builtins.hasAttr defaultChannel configuredChannels
            && configuredChannels.${defaultChannel} ? tag
          then configuredChannels.${defaultChannel}.tag
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
          configuredChannels;
        channelTestEnabled = testName: channel:
          ! (
            channel ? tests
            && builtins.hasAttr testName channel.tests
            && channel.tests.${testName} == false
          );
        gettingStartedChannels = lib.filterAttrs (_: channel: channelTestEnabled "gettingStarted" channel) mirroredChannels;
        counterContractChannels = lib.filterAttrs (_: channel: channelTestEnabled "counterContract" channel) mirroredChannels;

        channelPackages =
          lib.concatMapAttrs (
            channel: metadata: let
              release = releases.${metadata.tag};
            in {
              "${channel}" = release.aztec-bin;
              "${channel}-aztec-bin" = release.aztec-bin;
              "${channel}-bb" = release.aztec-bin;
              "${channel}-contracts" = release.contracts;
              "${channel}-foundry" = release.foundry;
              "${channel}-noir" = release.noir;
            }
          )
          mirroredChannels;

        mkGettingStartedE2E = channel: release:
          pkgs.callPackage ./e2e/getting_started {
            name = "${channel}-getting-started-e2e";
            aztec-bin = release.aztec-bin;
            foundry = release.foundry;
          };

        mkCounterContractE2E = channel: release:
          pkgs.callPackage ./e2e/counter_contract {
            name = "${channel}-counter-contract-e2e";
            aztec-bin = release.aztec-bin;
            foundry = release.foundry;
          };

        mkE2ESuite = name: tests:
          pkgs.writeShellApplication {
            inherit name;
            text =
              lib.concatMapStringsSep "\n"
              (test: ''
                echo
                echo "running ${test.name}"
                ${lib.getExe test}
              '')
              tests;
          };

        mkChannelE2E = channel: metadata: let
          release = releases.${metadata.tag};
        in
          mkE2ESuite "${channel}-e2e" (
            lib.optional
            (channelTestEnabled "gettingStarted" metadata)
            (mkGettingStartedE2E channel release)
            ++ lib.optional
            (channelTestEnabled "counterContract" metadata)
            (mkCounterContractE2E channel release)
          );

        channelGettingStartedE2EPackages =
          lib.concatMapAttrs (
            channel: metadata: let
              release = releases.${metadata.tag};
            in {
              "${channel}-getting-started-e2e" = mkGettingStartedE2E channel release;
            }
          )
          gettingStartedChannels;

        channelCounterContractE2EPackages =
          lib.concatMapAttrs (
            channel: metadata: let
              release = releases.${metadata.tag};
            in {
              "${channel}-counter-contract-e2e" = mkCounterContractE2E channel release;
            }
          )
          counterContractChannels;

        channelE2EPackages =
          lib.concatMapAttrs (
            channel: metadata: {
              "${channel}-e2e" = mkChannelE2E channel metadata;
            }
          )
          mirroredChannels;

        allE2EPackage = mkE2ESuite "aztec-e2e" (lib.attrValues channelE2EPackages);

        channelConfigCheck =
          pkgs.runCommand "aztec-channel-config" {
            nativeBuildInputs = [
              pkgs.gnugrep
              pkgs.jq
            ];
          } ''
            ${pkgs.bash}/bin/bash ${./scripts/check-channels.sh} ${./channels.json} ${./versions.json}
            touch $out
          '';

        channelApps =
          lib.concatMapAttrs (
            channel: metadata: let
              release = releases.${metadata.tag};
            in {
              "${channel}" = mkApp "Run the Aztec CLI for ${channel}" "${release.aztec-bin}/bin/aztec";
              "${channel}-aztec" = mkApp "Run the Aztec CLI for ${channel}" "${release.aztec-bin}/bin/aztec";
              "${channel}-aztec-anvil" = mkApp "Run Aztec-bundled Anvil for ${channel}" "${release.aztec-bin}/bin/aztec-anvil";
              "${channel}-aztec-bb" = mkApp "Run Aztec-bundled Barretenberg for ${channel}" "${release.aztec-bin}/bin/aztec-bb";
              "${channel}-aztec-cast" = mkApp "Run Aztec-bundled Cast for ${channel}" "${release.aztec-bin}/bin/aztec-cast";
              "${channel}-aztec-chisel" = mkApp "Run Aztec-bundled Chisel for ${channel}" "${release.aztec-bin}/bin/aztec-chisel";
              "${channel}-aztec-forge" = mkApp "Run Aztec-bundled Forge for ${channel}" "${release.aztec-bin}/bin/aztec-forge";
              "${channel}-aztec-nargo" = mkApp "Run Aztec-bundled Noir nargo for ${channel}" "${release.aztec-bin}/bin/aztec-nargo";
              "${channel}-aztec-wallet" = mkApp "Run the Aztec wallet CLI for ${channel}" "${release.aztec-bin}/bin/aztec-wallet";
              "${channel}-bb" = mkApp "Run Aztec-bundled Barretenberg for ${channel}" "${release.aztec-bin}/bin/aztec-bb";
              "${channel}-nargo" = mkApp "Run Noir nargo for ${channel}" "${release.noir}/bin/nargo";
            }
          )
          mirroredChannels;

        mkApp = description: program: {
          type = "app";
          inherit program;
          meta.description = description;
        };

        mkDevShell = channel: release: let
          isV4Channel = lib.hasPrefix "v4-" channel;
          bbBinary = "${release.node-runtime-unwrapped}/lib/aztec/node/node_modules/@aztec/bb.js/build/${bbJsPlatform.${system}}/bb";
        in
          pkgs.mkShell {
            packages = [
              release.aztec-bin
              release.noir
              pkgs.corepack
              pkgs.jq
              pkgs.netcat-openbsd
              pkgs.nodejs_24
              pkgs.procps
              pkgs.python3
            ];

            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            AZTEC_CONTRACTS_DIR = "${release.aztec-bin}/share/aztec/contracts";
            ANVIL_BIN = "${release.foundry}/bin/anvil";
            BB = bbBinary;
            BB_BINARY_PATH = bbBinary;
            FORGE_BIN = "${release.foundry}/bin/forge";
            NARGO = "${release.noir}/bin/nargo";

            shellHook =
              ''
                export BB_WORKING_DIRECTORY="''${BB_WORKING_DIRECTORY:-''${TMPDIR:-/tmp}/aztec-bb}"
              ''
              # on v4 we need to patch bb.js since it does not read BB_BINARY_PATH
              + lib.optionalString isV4Channel ''
                aztec_link_bb() {
                  local bb_js_dir="node_modules/@aztec/bb.js/build/${bbJsPlatform.${system}}"

                  if [ -d "$bb_js_dir" ]; then
                    ln -sfn "${bbBinary}" "$bb_js_dir/bb"
                  fi
                }

                aztec_link_bb
              '';
          };

        channelDevShells =
          lib.mapAttrs (
            channel: metadata:
              mkDevShell channel releases.${metadata.tag}
          )
          mirroredChannels;

        channelGettingStartedE2EApps =
          lib.mapAttrs (
            packageName: package:
              mkApp
              "Run the Aztec getting-started local-network E2E for ${lib.removeSuffix "-getting-started-e2e" packageName}"
              (lib.getExe package)
          )
          channelGettingStartedE2EPackages;

        channelCounterContractE2EApps =
          lib.mapAttrs (
            packageName: package:
              mkApp
              "Run the Aztec counter contract local-network E2E for ${lib.removeSuffix "-counter-contract-e2e" packageName}"
              (lib.getExe package)
          )
          channelCounterContractE2EPackages;

        channelE2EApps =
          lib.mapAttrs (
            packageName: package:
              mkApp
              "Run the Aztec local-network E2E suite for ${lib.removeSuffix "-e2e" packageName}"
              (lib.getExe package)
          )
          channelE2EPackages;
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
              aztec-bb = latest.aztec-bin;
              aztec-contracts = latest.contracts;
              aztec-foundry = latest.foundry;
              aztec-noir = latest.noir;
              e2e = allE2EPackage;
              getting-started-e2e = mkGettingStartedE2E defaultChannel latest;
            }
          )
          // channelPackages
          // channelGettingStartedE2EPackages
          // channelCounterContractE2EPackages
          // channelE2EPackages;

        apps =
          (
            lib.optionalAttrs hasDefault {
              default = config.apps.aztec;
              aztec = mkApp "Run the Aztec CLI" "${config.packages.aztec-bin}/bin/aztec";
              aztec-anvil = mkApp "Run Aztec-bundled Anvil" "${config.packages.aztec-bin}/bin/aztec-anvil";
              aztec-bb = mkApp "Run Aztec-bundled Barretenberg" "${config.packages.aztec-bin}/bin/aztec-bb";
              aztec-cast = mkApp "Run Aztec-bundled Cast" "${config.packages.aztec-bin}/bin/aztec-cast";
              aztec-chisel = mkApp "Run Aztec-bundled Chisel" "${config.packages.aztec-bin}/bin/aztec-chisel";
              aztec-forge = mkApp "Run Aztec-bundled Forge" "${config.packages.aztec-bin}/bin/aztec-forge";
              aztec-nargo = mkApp "Run Aztec-bundled Noir nargo" "${config.packages.aztec-bin}/bin/aztec-nargo";
              aztec-wallet = mkApp "Run the Aztec wallet CLI" "${config.packages.aztec-bin}/bin/aztec-wallet";
              bb = mkApp "Run Aztec-bundled Barretenberg" "${config.packages.aztec-bin}/bin/aztec-bb";
              e2e = mkApp "Run all Aztec local-network E2E suites" (lib.getExe config.packages.e2e);
              getting-started-e2e = mkApp "Run the Aztec getting-started local-network E2E" (lib.getExe config.packages.getting-started-e2e);
              nargo = mkApp "Run Noir nargo" "${config.packages.aztec-noir}/bin/nargo";
            }
          )
          // channelApps
          // channelGettingStartedE2EApps
          // channelCounterContractE2EApps
          // channelE2EApps;

        checks =
          {
            channel-config = channelConfigCheck;
          }
          // lib.optionalAttrs (hasDefault && system == "x86_64-linux") {
            smoke = pkgs.runCommand "aztec-bin-smoke" {} ''
              ${pkgs.bash}/bin/bash ${./scripts/smoke-test.sh} ${config.packages.aztec-bin}
              touch $out
            '';
          };

        devShells =
          (
            lib.optionalAttrs hasDefault {
              default = mkDevShell defaultChannel latest;
            }
          )
          // channelDevShells
          // {
            mirror = pkgs.mkShell {
              packages = [
                pkgs.coreutils
                pkgs.curl
                pkgs.git
                pkgs.gnugrep
                pkgs.jq
                pkgs.nodejs_24
              ];

              SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            };
          };
      };
    };
}
