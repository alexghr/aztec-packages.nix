{
  autoPatchelfHook,
  lib,
  openssl,
  stdenv,
  tag,
  release,
  system,
  zlib,
  buildNpmPackage,
}: let
  nodeRuntimePath = release.nodeRuntime.path or tag;
  platformDirs =
    {
      x86_64-linux = {
        bbJs = "amd64-linux";
        leveldown = "linux-x64";
      };
      aarch64-linux = {
        bbJs = "arm64-linux";
        leveldown = "linux-arm64";
      };
    }
    .${
      stdenv.hostPlatform.system
    }
    or (throw "aztec-node-runtime-unwrapped does not support ${stdenv.hostPlatform.system}");
in
  buildNpmPackage {
    pname = "aztec-node-runtime-unwrapped";
    version = release.version or tag;

    src = ../node-runtime + "/${nodeRuntimePath}";
    npmDepsHash = release.npmDepsHash;
    dontNpmBuild = true;

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      autoPatchelfHook
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

      mkdir -p $out/lib/aztec/node
      cp -R node_modules package.json package-lock.json $out/lib/aztec/node/
      chmod -R u+w $out/lib/aztec/node
      nodeModules=$out/lib/aztec/node/node_modules

      # only keep native artifacts for the system we're currently building
      find "$nodeModules/leveldown/prebuilds" -mindepth 1 -maxdepth 1 -type d \
        ! -name ${lib.escapeShellArg platformDirs.leveldown} \
        -exec rm -rf {} +

      find "$nodeModules/@aztec/bb.js/build" -mindepth 1 -maxdepth 1 -type d \
        ! -name ${lib.escapeShellArg platformDirs.bbJs} \
        -exec rm -rf {} +

      # Some releases ship Foundry deployment run caches. Forge rewrites those
      # paths during localnet startup, so keep only the cache file and let Forge
      # recreate writable run-cache directories in the runtime temp directory.
      l1ContractsCache="$nodeModules/@aztec/l1-artifacts/l1-contracts/cache"
      if [ -d "$l1ContractsCache" ]; then
        find "$l1ContractsCache" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
      fi

      # this script copies files from its package to a tmp dir and calls forge for deployments
      # in this case the files are copied from the nix store as read-only
      # forge needs to be able to write cache files. This patch calls chmod to allow writes
      substituteInPlace "$nodeModules/@aztec/ethereum/dest/deploy_aztec_l1_contracts.js" \
        --replace-fail \
          "import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'fs';" \
          "import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'fs';" \
        --replace-fail \
          "cpSync(join(basePath, 'cache'), join(tempDir, 'cache'), copyOpts);" \
          "cpSync(join(basePath, 'cache'), join(tempDir, 'cache'), copyOpts); chmodSync(join(tempDir, 'cache'), 0o755); chmodSync(join(tempDir, 'cache', 'solidity-files-cache.json'), 0o644);"

      # as above but for one of the helper scripts
      # the env vars in this substitution reference vars from inside the script
      substituteInPlace "$nodeModules/@aztec/aztec/scripts/add_crate.sh" \
        --replace-fail \
          'cp -r "$TEMPLATE_DIR/test" "$test_dir"' \
          'cp -r "$TEMPLATE_DIR/test" "$test_dir"; chmod -R u+w "$contract_dir" "$test_dir"'

      patchShebangs $out/lib/aztec/node/node_modules/.bin || true
      patchShebangs $out/lib/aztec/node/node_modules/@aztec || true

      runHook postInstall
    '';

    meta = {
      description = "Unwrapped Node runtime for Aztec CLI packages";
      homepage = "https://github.com/AztecProtocol/aztec-packages";
      license = lib.licenses.asl20;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
