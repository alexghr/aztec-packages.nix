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

    nativeBuildInputs =
      lib.optionals stdenv.hostPlatform.isLinux [
        autoPatchelfHook
      ]
      ++ [
        makeWrapper
      ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      openssl
      stdenv.cc.cc.lib
      zlib
    ];

    autoPatchelfIgnoreMissingDeps = lib.optionals stdenv.hostPlatform.isLinux [
      "libc.musl-x86_64.so.1"
    ];

    installPhase = ''
            runHook preInstall

            mkdir -p $out/lib/aztec/node $out/bin
            cp -R node_modules package.json package-lock.json $out/lib/aztec/node/
            chmod -R u+w $out/lib/aztec/node
            patchShebangs $out/lib/aztec/node/node_modules/.bin || true
            patchShebangs $out/lib/aztec/node/node_modules/@aztec || true

            deployJs=$out/lib/aztec/node/node_modules/@aztec/ethereum/dest/deploy_aztec_l1_contracts.js
            substituteInPlace "$deployJs" \
              --replace-fail \
                "import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'fs';" \
                "import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'fs';"
            substituteInPlace "$deployJs" \
              --replace-fail \
                "const JSON_DEPLOY_RESULT_PREFIX = 'JSON DEPLOY RESULT:';" \
                "const JSON_DEPLOY_RESULT_PREFIX = 'JSON DEPLOY RESULT:';
      function chmodWritableRecursive(path) {
          const stat = statSync(path);
          if (stat.isDirectory()) {
              chmodSync(path, 0o700);
              for (const entry of readdirSync(path)) {
                  chmodWritableRecursive(join(path, entry));
              }
          } else {
              chmodSync(path, stat.mode & 0o111 ? 0o700 : 0o600);
          }
      }"
            substituteInPlace "$deployJs" \
              --replace-fail \
                "cpSync(join(basePath, 'foundry.lock'), join(tempDir, 'foundry.lock'));" \
                "cpSync(join(basePath, 'foundry.lock'), join(tempDir, 'foundry.lock'));
          chmodWritableRecursive(tempDir);"

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
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
