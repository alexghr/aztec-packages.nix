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
      tar -xzf ${src} -C $out/bin
      chmod +x $out/bin/* || true

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
      description = "Noir binaries used by Aztec";
      homepage = "https://github.com/noir-lang/noir";
      mainProgram = "nargo";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
