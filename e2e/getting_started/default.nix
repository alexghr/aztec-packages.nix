{
  aztec-bin,
  bash,
  coreutils,
  curl,
  foundry,
  lib,
  makeWrapper,
  name,
  stdenvNoCC,
  util-linux,
}:
stdenvNoCC.mkDerivation {
  pname = name;
  version = aztec-bin.version;

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/${name}"
    install -m 0755 getting_started.sh "$out/share/${name}/getting_started.sh"

    makeWrapper ${bash}/bin/bash "$out/bin/${name}" \
      --add-flags "$out/share/${name}/getting_started.sh" \
      --prefix PATH : ${lib.makeBinPath [
      aztec-bin
      coreutils
      curl
      foundry
      util-linux
    ]}

    runHook postInstall
  '';

  meta = {
    mainProgram = name;
    platforms = aztec-bin.meta.platforms or lib.platforms.linux;
  };
}
