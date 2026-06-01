{
  barretenberg,
  contracts,
  foundry,
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

    for cmd in \
      aztec \
      aztec-wallet \
      aztec-bb-cli \
      aztec-blob-client \
      aztec-noir-codegen \
      aztec-txe; do
      ln -s ${node-runtime}/bin/$cmd $out/bin/$cmd
    done

    ln -s ${barretenberg}/bin/bb $out/bin/aztec-bb

    ln -s ${noir}/bin/nargo $out/bin/aztec-nargo

    if [ -x ${noir}/bin/noir-profiler ]; then
      ln -s ${noir}/bin/noir-profiler $out/bin/aztec-noir-profiler
    fi

    if [ -x ${noir}/bin/noir-inspector ]; then
      ln -s ${noir}/bin/noir-inspector $out/bin/aztec-noir-inspector
    fi

    for cmd in forge cast anvil chisel; do
      if [ -x ${foundry}/bin/$cmd ]; then
        ln -s ${foundry}/bin/$cmd $out/bin/aztec-$cmd
      fi
    done

    runHook postInstall
  '';

  meta = {
    description = "Unofficial binary distribution of Aztec development tooling";
    homepage = "https://github.com/AztecProtocol/aztec-packages";
    license = lib.licenses.asl20;
    mainProgram = "aztec";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
  };
}
