{
  autoPatchelfHook,
  bash,
  barretenberg,
  cacert,
  contracts,
  coreutils,
  foundry,
  git,
  gnugrep,
  gnused,
  jq,
  lib,
  makeWrapper,
  netcat-openbsd,
  nodejs_24,
  noir,
  openssl,
  perl,
  stdenv,
  tag,
  release,
  system,
  zlib,
  buildNpmPackage,
}: let
  nodeRuntimePath = release.nodeRuntime.path or tag;

  runtimePath = lib.makeBinPath [
    bash
    barretenberg
    coreutils
    foundry
    git
    gnugrep
    gnused
    jq
    netcat-openbsd
    nodejs_24
    noir
    perl
  ];

  wrapperFlags =
    lib.concatStringsSep " "
    [
      "--prefix PATH : ${runtimePath}"
      "--set SSL_CERT_FILE ${cacert}/etc/ssl/certs/ca-bundle.crt"
      "--set AZTEC_CONTRACTS_DIR ${contracts}/share/aztec/contracts"
      "--set BB ${barretenberg}/bin/bb-avm"
      "--set BB_BINARY_PATH ${barretenberg}/bin/bb-avm"
      "--run 'export BB_WORKING_DIRECTORY=\"\${BB_WORKING_DIRECTORY:-\${TMPDIR:-/tmp}/aztec-bb}\"'"
      "--run 'export ACVM_WORKING_DIRECTORY=\"\${ACVM_WORKING_DIRECTORY:-\${TMPDIR:-/tmp}/aztec-acvm}\"'"
    ];
in
  buildNpmPackage {
    pname = "aztec-node-runtime";
    version = release.version or tag;

    src = ../node-runtime + "/${nodeRuntimePath}";
    npmDepsHash = release.npmDepsHash;
    dontNpmBuild = true;

    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
    ];

    buildInputs = [
      openssl
      stdenv.cc.cc.lib
      zlib
    ];

    autoPatchelfIgnoreMissingDeps = [
      "libc.musl-x86_64.so.1"
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/aztec/node $out/bin
      cp -R node_modules package.json package-lock.json $out/lib/aztec/node/
      chmod -R u+w $out/lib/aztec/node
      patchShebangs $out/lib/aztec/node/node_modules/.bin || true
      patchShebangs $out/lib/aztec/node/node_modules/@aztec || true

      npmBin=$out/lib/aztec/node/node_modules/.bin

      wrapAztec() {
        makeWrapper "$1" "$out/bin/$2" ${wrapperFlags}
      }

      wrapAztec "$npmBin/aztec" aztec
      wrapAztec "$npmBin/aztec-wallet" aztec-wallet

      for bin in pxe txe validator-client blob-client bb-cli; do
        if [ -e "$npmBin/$bin" ]; then
          wrapAztec "$npmBin/$bin" "aztec-$bin"
        fi
      done

      runHook postInstall
    '';

    meta = {
      description = "Node runtime for Aztec CLI packages";
      homepage = "https://github.com/AztecProtocol/aztec-packages";
      platforms = ["x86_64-linux"];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
