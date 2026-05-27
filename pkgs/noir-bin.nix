{
  autoPatchelfHook,
  fetchurl,
  lib,
  makeWrapper,
  openssl,
  stdenv,
  tag,
  release,
  system,
  zlib,
}: let
  artifact = release.systems.${system}.noir;
  src = fetchurl {
    inherit (artifact) url hash;
  };
in
  stdenv.mkDerivation {
    pname = "aztec-noir-bin";
    version = release.version or tag;

    dontUnpack = true;

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

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      unpackDir=$(mktemp -d)
      tar -xzf ${src} -C "$unpackDir"

      installNoirBin() {
        cmd=$1
        for candidate in \
          "$unpackDir/noir-repo/target/release/$cmd" \
          "$unpackDir/$cmd"; do
          if [ -x "$candidate" ]; then
            install -Dm755 "$candidate" "$out/bin/$cmd"
            return 0
          fi
        done
      }

      installNoirBin nargo
      installNoirBin acvm
      installNoirBin noir-profiler
      installNoirBin noir-inspector

      for required in nargo acvm; do
        if [ ! -x "$out/bin/$required" ]; then
          echo "Noir artifact did not contain required binary: $required" >&2
          exit 1
        fi
      done

      if [ -x $out/bin/nargo ]; then
        makeWrapper $out/bin/nargo $out/bin/aztec-nargo
      fi

      if [ -x $out/bin/noir-profiler ]; then
        makeWrapper $out/bin/noir-profiler $out/bin/aztec-noir-profiler
      fi

      if [ -x $out/bin/noir-inspector ]; then
        makeWrapper $out/bin/noir-inspector $out/bin/aztec-noir-inspector
      fi

      runHook postInstall
    '';

    meta = {
      description = "Aztec forked Noir binaries";
      homepage = "https://github.com/AztecProtocol/aztec-packages/tree/master/noir";
      license = lib.licenses.asl20;
      mainProgram = "nargo";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
