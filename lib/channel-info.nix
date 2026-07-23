{lib}: let
  versions = builtins.fromJSON (builtins.readFile ../versions.json);
  channelConfig = builtins.fromJSON (builtins.readFile ../channels.json);

  supportedSystems = release:
    lib.filter
    (system:
      release.systems.${system} ? foundry
      && release.systems.${system} ? noir)
    (lib.attrNames (release.systems or {}));

  mkChannelInfo = channel: definition: let
    resolved = versions.channels.${channel} or null;
    tag =
      if resolved != null && resolved ? tag
      then resolved.tag
      else null;
    release =
      if tag != null && builtins.hasAttr tag versions.releases
      then versions.releases.${tag}
      else null;
  in
    if release == null
    then null
    else {
      inherit tag;
      aztecVersion = release.version;
      inherit (release) foundryVersion noirVersion;
      inherit (definition) liveNetworks releaseType;
      systems = supportedSystems release;
    };

  channels = lib.filterAttrs (_: channel: channel != null) (
    lib.mapAttrs mkChannelInfo channelConfig.channels
  );
in {
  schemaVersion = 1;
  defaultChannel = channelConfig.defaultChannel;
  inherit channels;
}
