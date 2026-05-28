{
  pkgs,
  system,
  tag,
  release,
}: let
  barretenberg = pkgs.callPackage ./barretenberg-bin.nix {
    inherit tag release system;
  };
  noir = pkgs.callPackage ./noir-bin.nix {
    inherit tag release system;
  };
  foundry = pkgs.callPackage ./foundry-bin.nix {
    inherit tag release system;
  };
  contracts = pkgs.callPackage ./contracts.nix {
    inherit tag release system;
  };
  node-runtime = pkgs.callPackage ./node-runtime.nix {
    inherit tag release system barretenberg noir contracts;
  };
  aztec-bin = pkgs.callPackage ./aztec-bin.nix {
    inherit tag release system barretenberg noir contracts node-runtime;
  };
in {
  inherit aztec-bin barretenberg contracts foundry node-runtime noir;
}
