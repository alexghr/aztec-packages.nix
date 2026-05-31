{
  barretenberg,
  cacert,
  contracts,
  foundry,
  jq,
  lib,
  makeWrapper,
  node-runtime-unwrapped,
  nodejs_24,
  noir,
  stdenvNoCC,
  tag,
  release,
  system,
}: let
  runtimePath = lib.makeBinPath [
    barretenberg
    foundry
    jq
    nodejs_24
    noir
  ];

  wrapperFlags =
    lib.concatStringsSep " "
    [
      "--prefix PATH : ${runtimePath}"
      "--set SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt"
      "--set AZTEC_CONTRACTS_DIR ${contracts}/share/aztec/contracts"
      "--set BB ${barretenberg}/bin/bb"
      "--set BB_BINARY_PATH ${barretenberg}/bin/bb"
      "--set ACVM_BINARY_PATH ${noir}/bin/acvm"
      "--run 'export BB_WORKING_DIRECTORY=\"\${BB_WORKING_DIRECTORY:-\${TMPDIR:-/tmp}/aztec-bb}\"'"
      "--run 'export ACVM_WORKING_DIRECTORY=\"\${ACVM_WORKING_DIRECTORY:-\${TMPDIR:-/tmp}/aztec-acvm}\"'"
    ];
in
  stdenvNoCC.mkDerivation {
    pname = "aztec-node-runtime";
    version = release.version or tag;

    dontUnpack = true;

    nativeBuildInputs = [
      makeWrapper
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/aztec $out/bin
      ln -s ${node-runtime-unwrapped}/lib/aztec/node $out/lib/aztec/node

      npmBin=${node-runtime-unwrapped}/lib/aztec/node/node_modules/.bin

      wrapAztec() {
        makeWrapper "$1" "$out/bin/$2" ${wrapperFlags}
      }

      wrapAztec "$npmBin/aztec" aztec
      wrapAztec "$npmBin/aztec-wallet" aztec-wallet

      for cmd in bb-cli blob-client noir-codegen txe; do
        wrapAztec "$npmBin/$cmd" "aztec-$cmd"
      done

      runHook postInstall
    '';

    meta = {
      description = "Node runtime for Aztec CLI packages";
      homepage = "https://github.com/AztecProtocol/aztec-packages";
      license = lib.licenses.asl20;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
    passthru.unwrapped = node-runtime-unwrapped;
  }
