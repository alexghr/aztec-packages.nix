{
  pkgs,
  system,
  tag,
  release,
}: let
  noir = pkgs.callPackage ./noir-bin.nix {
    inherit tag release system;
  };
  foundry = pkgs.callPackage ./foundry-bin.nix {
    inherit tag release system;
  };
  contracts = pkgs.callPackage ./contracts.nix {
    inherit tag release system;
  };
  node-runtime-unwrapped = pkgs.callPackage ./node-runtime-unwrapped.nix {
    inherit tag release system;
  };
  node-runtime = pkgs.callPackage ./node-runtime.nix {
    inherit tag release system noir contracts foundry node-runtime-unwrapped;
  };
  aztec-bin = pkgs.callPackage ./aztec-bin.nix {
    inherit tag release system noir contracts foundry node-runtime;
  };
in {
  inherit aztec-bin contracts foundry node-runtime node-runtime-unwrapped noir;
}
