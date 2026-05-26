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
  artifact = release.systems.${system}.foundry;
  src = fetchurl {
    inherit (artifact) url hash;
  };
in
  stdenv.mkDerivation {
    pname = "aztec-foundry-bin";
    version = release.foundryVersion or release.version or tag;

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

      runHook postInstall
    '';

    meta = {
      description = "Foundry binaries pinned to the Aztec release";
      homepage = "https://github.com/foundry-rs/foundry";
      mainProgram = "forge";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
