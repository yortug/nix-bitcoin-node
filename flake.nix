{
  description = "yort's first nixos attempt";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # grab datum-gateway source below, need to change commit hash when updated
    datum-src = {
      #url = "git+https://github.com/OCEAN-xyz/datum_gateway.git?rev=5b061233a3d3323771b2be98e17f543e59346619";
      url = "git+https://github.com/yortug/datum_gateway.git?rev=eb63a28bc9634052fb6b9218b511939141a2c500";
      flake = false;
    };
    joinmarket-src = {
      url = "github:JoinMarket-Org/joinmarket-clientserver/v0.9.11";
      flake = false;
    };
    old-nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-25.05";
      flake = false;
    };
    knots-prerdts-src = {
      url = "https://github.com/bitcoinknots/bitcoin/releases/download/v29.3.knots20260507/bitcoin-29.3.knots20260507-x86_64-linux-gnu.tar.gz";
      flake = false;
    };
    knots-blake-src = {
      url = "https://test.bitcoinknots.org/~luke-jr/programs/bitcoin/files/bitcoin-knots/29.x/29.4.1.knots20260508/test/rc5/bitcoin-29.4.1.knots20260508rc5-x86_64-linux-gnu.tar.gz";
      flake = false;
    };
    
  };

  outputs =
    { self, nixpkgs, datum-src, joinmarket-src, old-nixpkgs, knots-prerdts-src, knots-blake-src, ... }@inputs: let
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
      
      joinmarket = pkgs.callPackage ./pkgs/joinmarket.nix {
        inherit (inputs) joinmarket-src old-nixpkgs;
        secp256k1 = (import old-nixpkgs { inherit system; }).secp256k1;
      };
      

      bitcoind-knots-prerdts = pkgs.stdenv.mkDerivation {
        pname = "bitcoind-knots-prerdts";
        version = "29.3.knots20260507";
        src = knots-prerdts-src;
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc pkgs.zlib ];
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/bin
          install -Dm755 bin/bitcoind       $out/bin/bitcoind
          install -Dm755 bin/bitcoin-cli    $out/bin/bitcoin-cli
          install -Dm755 bin/bitcoin-tx     $out/bin/bitcoin-tx
          install -Dm755 bin/bitcoin-wallet $out/bin/bitcoin-wallet
        '';
      };

      bitcoind-knots-blake = pkgs.stdenv.mkDerivation {
        pname = "bitcoind-knots-blake";
        version = "29.4.1.knots20260508rc5";
        src = knots-blake-src;
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc pkgs.zlib ];
        dontConfigure = true;
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/bin
          install -Dm755 bin/bitcoind       $out/bin/bitcoind
          install -Dm755 bin/bitcoin-cli    $out/bin/bitcoin-cli
          install -Dm755 bin/bitcoin-tx     $out/bin/bitcoin-tx
          install -Dm755 bin/bitcoin-wallet $out/bin/bitcoin-wallet
        '';
      };

      
    in {
      packages = {
        ${system} = {
          datum = datum;
          joinmarket = joinmarket;
        };
      };
      
      nixosConfigurations."${secrets.hostname}" = nixpkgs.lib.nixosSystem {
        pkgs = nixpkgs.legacyPackages.${system};
        specialArgs = { inherit datum joinmarket bitcoind-knots-prerdts bitcoind-knots-blake; };
        modules = [
          ./configuration.nix
          ({ config, ... }: {
            _module.args.joinmarket = self.packages.${system}.joinmarket;
          })
        ];
      };
    };
}
