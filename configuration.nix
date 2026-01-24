{
  config,
  lib,
  pkgs,
  datum,
  ...
}:
let
  secrets = import ./secrets.nix;

  datumConfig = {
    bitcoind = {
      rpccookiefile = "/home/${secrets.username}/.bitcoin/.cookie";
      rpcurl = "http://127.0.0.1:8332";
    };
    stratum = {
      listen_port = 23334;
    };
    mining = {
      pool_address = secrets.datum_mining_address;
      coinbase_tag_primary = "DATUM Gateway";
      coinbase_tag_secondary = secrets.datum_coinbase_secondary;
    };
    logger = {
      log_level_console = 1;
    };
  };

  datumConfigFile = pkgs.writeText "datum_gateway_config.json" (builtins.toJSON datumConfig);

in
{
  imports = [
    ./hardware-configuration.nix
  ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  
  nix.nixPath = [
    "nixos-config=/home/${secrets.username}/.nixos/configuration.nix"
  ];
  
  boot.swraid.mdadmConf = ''
    MAILADDR=placeholder
  '';

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 3;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = secrets.hostname;
  networking.wireless.interfaces = [ "wlp3s0" ];
  networking.wireless = {
    enable = true;
    networks = {
      "${secrets.wifi_ssid}" = {
        pskRaw = secrets.wifi_psk_hashed;
      };
    };
  };
  networking.firewall = {
    enable = true;
    interfaces = {
      "wlp3s0" = {
        allowedTCPPorts = [
          22
          8332
          50001
          23334
        ]; # ssh, bitcoin rpc, electrs rpc, datum gateway
      };
    };
  };

  time.timeZone = "Australia/Perth";

  users.groups."${secrets.username}" = { };

  users.users."${secrets.username}" = {
    isNormalUser = true;
    group = secrets.username;
    extraGroups = [
      "wheel"
      "tor"
    ];
    hashedPassword = secrets.user_password_hashed;
  };

  security.sudo.wheelNeedsPassword = true;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  services.tor = {
    enable = true;
    client.enable = true;
    settings = {
      ControlPort = 9051;
      CookieAuthentication = true;
      CookieAuthFileGroupReadable = true;
    };
  };

  services.bitcoind.default = {
    enable = true;
    #package = pkgs.bitcoind-knots;
    package = pkgs.bitcoin-knots-bip110;
    user = secrets.username;
    group = secrets.username;
    dataDir = "/home/${secrets.username}/.bitcoin";
    dbCache = 8000; # can adjust (down) post-sync if needed
    extraConfig = ''
      server=1
      txindex=1
      rpcport=8332
      rpcbind=0.0.0.0
      rpcallowip=127.0.0.1
      rpcallowip=10.0.0.0/8
      rpcallowip=172.0.0.0/8
      rpcallowip=192.0.0.0/8
      whitelist=127.0.0.1
      rpcauth=${secrets.btc_rpc_username}:${secrets.btc_rpc_password_hashed}
      proxy=127.0.0.1:9050
      listen=1
      bind=127.0.0.1
      onlynet=onion
      # extra config options suggested / required for datum solo mining
      blockmaxsize=3985000
      blockmaxweight=3985000
      maxmempool=1000
      blockreconstructionextratxn=1000000
      blocknotify=killall -USR1 datum_gateway
      # added to prevent / fix corrupt chainstate (hopefully)
      shutdownonreboot=1
      #reindex-chainstate=1
      #reindex=1
    '';
  };

  # ensures bitcoind doesn't start until tor is up and running - makes sense
  systemd.services.bitcoind-default = {
    after = [ "tor.service" ];
    wants = [ "tor.service" ];
    serviceConfig = {
      TimeoutStopSec = "30min";
      TimeoutStartSec = "30min";
      Restart = "on-failure";
      RestartSec = "10s";
      KillMode = "process";
    };
  };

  systemd.services.electrs = {
    description = "Electrs Electrum Server";
    after = [
      "bitcoind-default.service"
      "network.target"
    ];
    wantedBy = [ "multi-user.target" ];
    requires = [ "bitcoind-default.service" ];
    serviceConfig = {
      User = secrets.username;
      Group = secrets.username;
      WorkingDirectory = "/home/${secrets.username}";
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'while [ ! -f /home/${secrets.username}/.bitcoin/.cookie ]; do echo \"Waiting for bitcoind cookie...\"; sleep 1; done'"; # custom script to wait for .cookie
      ExecStart = "${pkgs.electrs}/bin/electrs --log-filters=INFO --cookie-file=/home/${secrets.username}/.bitcoin/.cookie --db-dir=/home/${secrets.username}/electrs_db --electrum-rpc-addr=0.0.0.0:50001 --daemon-rpc-addr=127.0.0.1:8332";
      Restart = "always";
      RestartSec = 60;
      # extra hardening measures follow
      PrivateTmp = true;
      ProtectSystem = "full";
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = true;
    };
  };

  systemd.services.datum_gateway = {
    description = "DATUM Gateway for Bitcoin Mining";
    after = [
      "bitcoind-default.service"
      "network.target"
    ];
    wantedBy = [ "multi-user.target" ];
    wants = [ "bitcoind-default.service" ];
    serviceConfig = {
      User = secrets.username;
      Group = secrets.username;
      WorkingDirectory = "/home/${secrets.username}";
      ExecStart = "${datum}/bin/datum_gateway -c ${datumConfigFile}";
      Restart = "always";
      RestartSec = 10;
      StandardOutput = "syslog";
      StandardError = "syslog";
      SyslogIdentifier = "datum_gateway";
      # extra hardening measures follow
      PrivateTmp = true;
      ProtectSystem = "full";
      NoNewPrivileges = true;
      MemoryDenyWriteExecute = true;
    };
  };

  programs.bash = {
    #enable = true; # deprecated?
    promptInit = ''
      PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
    '';
  };

  programs.git = {
    enable = true;
    config = {
      user = {
        name = "${secrets.git_user}";
        email = "${secrets.git_email}";
      };
      advice.defaultBranchName = false;
      init.defaultBranch = "master";
    };
  };

  environment.systemPackages = with pkgs; [
    (vim-full.customize {
      name = "vim";
      vimrcConfig = {
        customRC = ''
          set relativenumber
          set number

          set expandtab
          set tabstop=2
          set shiftwidth=2

          set nocompatible
          set backspace=indent,eol,start
          syntax on
        '';
      };
    })
    wget
    neofetch
    git
    tor
    bitcoind-knots
    electrs
    datum
    psmisc
  ];

  system.stateVersion = "25.05";
}
