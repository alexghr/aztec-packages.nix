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
