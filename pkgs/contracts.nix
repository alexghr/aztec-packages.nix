{
  fetchurl,
  lib,
  stdenvNoCC,
  tag,
  release,
  system,
}: let
  inherit (release) npm;

  packages = [
    {
      key = "noirContractsJs";
      directory = "noir-contracts.js";
    }
    {
      key = "noirTestContractsJs";
      directory = "noir-test-contracts.js";
    }
    {
      key = "protocolContracts";
      directory = "protocol-contracts";
    }
    {
      key = "l1Artifacts";
      directory = "l1-artifacts";
    }
  ];

  unpackPackage = package: let
    artifact = npm.${package.key};
    src = fetchurl {
      inherit (artifact) url hash;
    };
  in ''
    mkdir -p "$TMPDIR/${package.directory}"
    tar -xzf ${src} -C "$TMPDIR/${package.directory}"
    mkdir -p "$out/share/aztec/contracts/${package.directory}"
    cp -R "$TMPDIR/${package.directory}/package/." "$out/share/aztec/contracts/${package.directory}/"
  '';
in
  stdenvNoCC.mkDerivation {
    pname = "aztec-contracts";
    version = release.version or tag;

    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/aztec/contracts
      ${lib.concatMapStringsSep "\n" unpackPackage packages}

      runHook postInstall
    '';

    passthru.contractsDir = "${placeholder "out"}/share/aztec/contracts";

    meta = {
      description = "Aztec contract artifacts from npm release packages";
      homepage = "https://github.com/AztecProtocol/aztec-packages";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    };
  }
