{
  barretenberg,
  contracts,
  lib,
  node-runtime,
  noir,
  stdenvNoCC,
  tag,
  release,
  system,
}:
stdenvNoCC.mkDerivation {
  pname = "aztec-bin";
  version = release.version or tag;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/aztec
    ln -s ${contracts}/share/aztec/contracts $out/share/aztec/contracts

    for cmd in aztec aztec-wallet aztec-txe; do
      if [ -x ${node-runtime}/bin/$cmd ]; then
        ln -s ${node-runtime}/bin/$cmd $out/bin/$cmd
      fi
    done

    ln -s ${barretenberg}/bin/bb $out/bin/bb

    ln -s ${noir}/bin/acvm $out/bin/acvm
    ln -s ${noir}/bin/nargo $out/bin/nargo
    ln -s ${noir}/bin/nargo $out/bin/aztec-nargo

    if [ -x ${noir}/bin/noir-profiler ]; then
      ln -s ${noir}/bin/noir-profiler $out/bin/aztec-noir-profiler
    fi

    runHook postInstall
  '';

  meta = {
    description = "Unofficial binary distribution of Aztec development tooling";
    homepage = "https://github.com/AztecProtocol/aztec-packages";
    mainProgram = "aztec";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
  };
}
