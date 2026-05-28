{
  package,
  system ? builtins.currentSystem,
  tag,
}: let
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);
  nixpkgsInput = lock.nodes.root.inputs.nixpkgs;
  nixpkgs = builtins.fetchTree lock.nodes.${nixpkgsInput}.locked;
  pkgs = import nixpkgs {inherit system;};
  versions = builtins.fromJSON (builtins.readFile ../versions.json);
  release =
    versions.releases.${tag}
    or (throw "release ${tag} is not declared in versions.json");
  packages = import ../pkgs/release.nix {
    inherit pkgs system tag release;
  };
in
  packages.${package}
  or (throw "release package ${package} is not supported")
