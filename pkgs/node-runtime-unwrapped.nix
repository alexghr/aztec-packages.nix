{
  autoPatchelfHook,
  lib,
  nodejs_24,
  openssl,
  stdenv,
  tag,
  release,
  system,
  zlib,
  buildNpmPackage,
}: let
  aztecPackage = release.npm.aztec.package or "@aztec-labs/aztec";
  aztecScope = builtins.dirOf aztecPackage;
  bbPackage = release.npm.bbJs.package or "@aztec-foundation/bb.js";
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

    src = ../node-runtime + "/${tag}";
    npmDepsHash = release.npmDepsHash;
    nodejs = nodejs_24;
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

      find "$nodeModules/${bbPackage}/build" -mindepth 1 -maxdepth 1 -type d \
        ! -name ${lib.escapeShellArg platformDirs.bbJs} \
        -exec rm -rf {} +

      # this script copies files from its package to a tmp dir and calls forge for deployments
      # in this case the files are copied from the nix store as read-only
      # Forge needs writable cache files, including the nested recovery snapshots
      # shipped with v6. Keep those snapshots and make the copied cache writable.
      cacheCopyPatch=$(cat <<'JS'
      cpSync(join(basePath, 'cache'), join(tempDir, 'cache'), copyOpts);
      const makeCacheWritable = dir => {
          chmodSync(dir, 0o755);
          for (const entry of readdirSync(dir, { withFileTypes: true })) {
              const path = join(dir, entry.name);
              if (entry.isDirectory()) {
                  makeCacheWritable(path);
              } else {
                  chmodSync(path, 0o644);
              }
          }
      };
      makeCacheWritable(join(tempDir, 'cache'));
      JS
      )
      substituteInPlace "$nodeModules/${aztecScope}/ethereum/dest/deploy_aztec_l1_contracts.js" \
        --replace-fail \
          "import { cpSync, existsSync," \
          "import { chmodSync, readdirSync, cpSync, existsSync," \
        --replace-fail \
          "cpSync(join(basePath, 'cache'), join(tempDir, 'cache'), copyOpts);" \
          "$cacheCopyPatch"

      # as above but for one of the helper scripts
      # the env vars in this substitution reference vars from inside the script
      substituteInPlace "$nodeModules/${aztecPackage}/scripts/add_crate.sh" \
        --replace-fail \
          'cp -r "$TEMPLATE_DIR/test" "$test_dir"' \
          'cp -r "$TEMPLATE_DIR/test" "$test_dir"; chmod -R u+w "$contract_dir" "$test_dir"'

      patchShebangs $out/lib/aztec/node/node_modules/.bin || true
      patchShebangs "$out/lib/aztec/node/node_modules/${aztecScope}" || true

      runHook postInstall
    '';

    meta = {
      description = "Unwrapped Node runtime for Aztec CLI packages";
      homepage = "https://github.com/aztec-labs-eng/aztec-node";
      license = lib.licenses.asl20;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
