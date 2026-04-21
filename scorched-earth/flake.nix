{
  description = "Scorched Earth — core C++ module for Logos Basecamp";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nix-bundle-lgx.follows = "logos-module-builder/nix-bundle-lgx";
    delivery_module.url = "github:logos-co/logos-delivery-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
