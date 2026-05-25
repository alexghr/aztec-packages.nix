{
  barretenberg,
  contracts,
  coreutils,
  foundry,
  lib,
  makeWrapper,
  node-runtime,
  noir,
  stdenvNoCC,
  tag,
  release,
  system,
}: let
  nativePath = lib.makeBinPath [
    barretenberg
    coreutils
    foundry
    noir
  ];
in
  stdenvNoCC.mkDerivation {
    pname = "aztec-bin";
    version = release.version or tag;

    dontUnpack = true;
    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/share/aztec
      ln -s ${contracts}/share/aztec/contracts $out/share/aztec/contracts

      for cmd in aztec aztec-wallet aztec-pxe aztec-txe aztec-validator-client aztec-blob-client aztec-bb-cli; do
        if [ -x ${node-runtime}/bin/$cmd ]; then
          ln -s ${node-runtime}/bin/$cmd $out/bin/$cmd
        fi
      done

      makeWrapper ${barretenberg}/bin/bb-avm $out/bin/bb-avm \
        --prefix PATH : ${nativePath}

      makeWrapper ${noir}/bin/nargo $out/bin/nargo \
        --prefix PATH : ${nativePath}
      makeWrapper ${noir}/bin/nargo $out/bin/aztec-nargo \
        --prefix PATH : ${nativePath}

      if [ -x ${noir}/bin/noir-profiler ]; then
        makeWrapper ${noir}/bin/noir-profiler $out/bin/aztec-noir-profiler \
          --prefix PATH : ${nativePath}
      fi

      for cmd in forge cast anvil chisel; do
        if [ -x ${foundry}/bin/$cmd ]; then
          makeWrapper ${foundry}/bin/$cmd $out/bin/aztec-$cmd \
            --prefix PATH : ${nativePath}
        fi
      done

      runHook postInstall
    '';

    meta = {
      description = "Unofficial binary distribution of Aztec development tooling";
      homepage = "https://github.com/AztecProtocol/aztec-packages";
      mainProgram = "aztec";
      platforms = ["x86_64-linux"];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
