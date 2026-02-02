{
  config,
  lib,
  pkgs,
  datum,
  joinmarket,
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
      coinbase_tag_primary = secrets.datum_coinbase_primary; # ignored when mining in a pool 
      coinbase_tag_secondary = secrets.datum_coinbase_secondary;
    };
    logger = {
      log_level_console = 0;
    };
    datum = {
      pool_host = ""; # defaults to OCEAN; setting empty should enforce *solo* (lottery) mining
      pooled_mining_only = false; # defaults to `true`; which contributes your hash to OCEAN (not *solo*) 
    };
  };

  datumConfigFile = pkgs.writeText "datum_gateway_config.json" (builtins.toJSON datumConfig);

  joinmarketConfig = {
    BLOCKCHAIN = {
      rpc_port          = "8332";
      rpc_cookie_file   = "/home/${secrets.username}/.bitcoin/.cookie";
      rpc_wallet_file   = "joinmarket_wallet";
    };
    POLICY = {
      absurd_fee_per_kb = "20000";
      #max_cj_fee_abs = "0.001";
      #max_cj_fee_rel = "0.003";
    };
    "MESSAGING:onion" = {
      directory_nodes = "jmarketxf5wc4aldf3slm5u6726zsky52bqnfv6qyxe5hnafgly6yuyd.onion:5222,coinjointovy3eq5fjygdwpkbcdx63d7vd4g32mw7y553uj3kjjzkiqd.onion:5222,satoshi2vcg5e2ept7tjkzlkpomkobqmgtsjzegg6wipnoajadissead.onion:5222,nakamotourflxwjnjpnrk7yc2nhkf6r62ed4gdfxmmn5f4saw5q5qoyd.onion:5222"; 
    };
  };
  
  applyJoinmarketConfig = lib.concatStringsSep "\n" (
    # remove user / pwd options, as they default are NOT commented out, but we are using .cookie
    [
      "crudini --del /home/${secrets.username}/.joinmarket/joinmarket.cfg BLOCKCHAIN rpc_user || true"
      "crudini --del /home/${secrets.username}/.joinmarket/joinmarket.cfg BLOCKCHAIN rpc_password || true"
    ]
    ++
    lib.mapAttrsToList (section: attrs:
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList (key: val: ''
          crudini --set /home/${secrets.username}/.joinmarket/joinmarket.cfg ${section} ${key} ${toString val}
        '') attrs
      )
    ) joinmarketConfig
  );


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
          3002
          62601
        ]; # ssh, bitcoin, electrs, datum gateway, btc-rpc-explorer, jm orderbook
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

  systemd.services.btc-rpc-explorer = {
    description = "BTC RPC Explorer";
    after = [ "bitcoind-default.service" "network.target" "electrs.service" ];
    wantedBy = [ "multi-user.target" ];
    requires = [ "bitcoind-default.service" ];
    wants = [ "electrs.service" ];

    serviceConfig = {
      User = secrets.username;
      Group = secrets.username;
      WorkingDirectory = "/home/${secrets.username}";
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'while [ ! -f /home/${secrets.username}/.bitcoin/.cookie ]; do echo \"Waiting for bitcoind cookie...\"; sleep 1; done'";
      ExecStart = "${pkgs.btc-rpc-explorer}/bin/btc-rpc-explorer";
      Restart = "always";
      RestartSec = 10;
      StandardOutput = "syslog";
      StandardError = "syslog";
      SyslogIdentifier = "btc-rpc-explorer";
      PrivateTmp = true;
      ProtectSystem = "full";
      NoNewPrivileges = true;
      #MemoryDenyWriteExecute = true; # doesn't let jscript load when enabled
    };
    environment = {
      BTCEXP_HOST = "0.0.0.0";
      BTCEXP_PORT = "3002";
      BTCEXP_BITCOIND_HOST = "127.0.0.1";
      BTCEXP_BITCOIND_PORT = "8332";
      BTCEXP_BITCOIND_COOKIE = "/home/${secrets.username}/.bitcoin/.cookie";
      BTCEXP_ADDRESS_API = "electrum";
      BTCEXP_ELECTRUM_SERVERS = "tcp://127.0.0.1:50001"; # can be changed to tls://...:50002 if needed
      BTCEXP_PRIVACY_MODE = "true";
      BTCEXP_NO_RATES = "true";
    };
  };

  systemd.services.joinmarket-init-config = {
    description = "Initialize and configure JoinMarket config";
    after = [
      "bitcoind-default.service"
      "network.target"
    ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ crudini ];
    serviceConfig = {
      User = secrets.username;
      Group = secrets.username;
      WorkingDirectory = "/home/${secrets.username}";
      ExecStart = pkgs.writeShellScript "jm-init-config" ''
        set -euo pipefail

        CFG_FILE="/home/${secrets.username}/.joinmarket/joinmarket.cfg"

        # if config file is missing... create it! 
        if [[ ! -f "$CFG_FILE" ]]; then
          echo "joinmarket.cfg missing — running jm-wallet-tool command to create it"
          ${joinmarket}/bin/jm-wallet-tool || true
        fi

        # if the config file exists... apply the custom config options! 
        if [[ -f "$CFG_FILE" ]]; then
          echo "Applying custom specified JoinMarket config options..."
          ${applyJoinmarketConfig}
          echo "Overrides applied."
        else
          echo "Warning: joinmarket.cfg still missing after trigger — skipping overrides"
        fi
      '';
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 30;
      StandardOutput = "syslog";
      StandardError = "syslog";
      SyslogIdentifier = "joinmarket-init-config";
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
    btc-rpc-explorer
    joinmarket
    crudini
    tmux
    python3
  ];

  system.stateVersion = "25.05";
}
