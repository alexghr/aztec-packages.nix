{
  aztec-bin,
  bash,
  coreutils,
  curl,
  foundry,
  git,
  gnused,
  jq,
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
    cp -R . "$out/share/${name}/"

    makeWrapper ${bash}/bin/bash "$out/bin/${name}" \
      --add-flags "$out/share/${name}/counter_contract.sh" \
      --set AZTEC_COUNTER_FIXTURE "$out/share/${name}/fixture" \
      --prefix PATH : ${lib.makeBinPath [
      aztec-bin
      coreutils
      curl
      foundry
      git
      gnused
      jq
      util-linux
    ]}

    runHook postInstall
  '';

  meta = {
    mainProgram = name;
    platforms = aztec-bin.meta.platforms or lib.platforms.linux;
  };
}
