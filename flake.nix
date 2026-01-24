{
  description = "yort's first nixos attempt";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # grab datum-gateway source below, need to change commit hash when updated
    datum-src = {
      url = "git+https://github.com/OCEAN-xyz/datum_gateway.git?rev=cd7b7a30d681b58420bc24d09ea561a620cbd4ac";
      flake = false;
    };
    # grab bip-110 specific pre-release source below, need to change commit hash when updated
    nixpkgs-bip110.url = "github:NixOS/nixpkgs/pull/482673/head";
  };

  outputs =
    { self, nixpkgs, datum-src, nixpkgs-bip110, ... }@inputs: let
      secrets = import ./secrets.nix;
      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages.${system};

      datum = pkgs.stdenv.mkDerivation rec {
        pname = "datum_gateway";
        version = "0.4.0beta";  # Matches tag for easy tracking.
        src = datum-src;
        nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ];  
        buildInputs = with pkgs; [ curl jansson libsodium libmicrohttpd ];
        preConfigure = ''
          export NIX_CFLAGS_COMPILE="-DJSON_INTEGER_IS_LONG_LONG=1 $NIX_CFLAGS_COMPILE"
        '';
        buildPhase = "cmake . && make";
        installPhase = ''
          install -Dm755 datum_gateway $out/bin/datum_gateway
        '';
      };
      
    in {
      packages = {
        ${system} = {
          datum = datum;
        };
      };
      
      nixosConfigurations."${secrets.hostname}" = nixpkgs.lib.nixosSystem {
        pkgs = nixpkgs.legacyPackages.${system};
        specialArgs = { inherit datum; };
        modules = [
          ./configuration.nix
          {
            nixpkgs.overlays = [
              (final: prev: {
                bitcoin-knots-bip110 = nixpkgs-bip110.legacyPackages.${prev.stdenv.hostPlatform.system}.bitcoin-knots-bip110;
              })
            ];
          }
        ];
      };
    };
}
