{
  autoPatchelfHook,
  barretenberg,
  cacert,
  contracts,
  lib,
  makeWrapper,
  nodejs_24,
  noir,
  openssl,
  stdenv,
  tag,
  release,
  system,
  zlib,
  buildNpmPackage,
}: let
  nodeRuntimePath = release.nodeRuntime.path or tag;
  nativeArtifacts = lib.getAttr system {
    x86_64-linux = {
      bbJs = "amd64-linux";
      leveldown = "linux-x64";
    };
    aarch64-linux = {
      bbJs = "arm64-linux";
      leveldown = "linux-arm64";
    };
  };

  runtimePath = lib.makeBinPath [
    barretenberg
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
            nodeModules=$out/lib/aztec/node/node_modules

            keepOnly() {
              dir=$1
              keep=$2
              if [ -d "$dir" ]; then
                find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name "$keep" -exec rm -rf {} +
              fi
            }

            keepOnly "$nodeModules/@aztec/bb.js/build" "${nativeArtifacts.bbJs}"
            keepOnly "$nodeModules/leveldown/prebuilds" "${nativeArtifacts.leveldown}"
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
            wrapAztec "$npmBin/txe" aztec-txe

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
  }
