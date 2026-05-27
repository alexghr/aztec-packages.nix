{
  autoPatchelfHook,
  fetchurl,
  lib,
  openssl,
  stdenv,
  tag,
  release,
  system,
  zlib,
}: let
  artifact = release.systems.${system}.barretenberg;
  src = fetchurl {
    inherit (artifact) url hash;
  };
in
  stdenv.mkDerivation {
    pname = "aztec-barretenberg-bin";
    version = release.version or tag;

    dontUnpack = true;

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      autoPatchelfHook
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

      if [ ! -x $out/bin/bb ] && [ -x $out/bin/bb-avm ]; then
        ln -s bb-avm $out/bin/bb
      fi

      if [ ! -x $out/bin/bb ]; then
        echo "barretenberg archive did not contain bb or bb-avm" >&2
        exit 1
      fi

      if [ ! -e $out/bin/bb-avm ]; then
        ln -s bb $out/bin/bb-avm
      fi

      runHook postInstall
    '';

    meta = {
      description = "Prebuilt Aztec Barretenberg binary";
      homepage = "https://github.com/AztecProtocol/aztec-packages";
      mainProgram = "bb";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
