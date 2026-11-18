{
  description = "workstation — a machine's tools and configuration, declared in nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    machine-files = {
      url = "path:./hosts/template";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nixos-wsl,
      nix-darwin,
      nix-homebrew,
      machine-files,
    }:
    let
      lib = nixpkgs.lib;
      ciSystem = "x86_64-linux";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      licensePredicate = import ./nix/lib/license.nix { inherit lib; };

      pkgsFor = lib.genAttrs systems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = licensePredicate;
        }
      );

      machineOf = args: import ./nix/lib/machine.nix ({ inherit lib; } // args);
      machine = machineOf { root = machine-files; };
      # the check legs: the template machine, one per platform
      templateMachine = machineOf { root = ./hosts/template; };
      templateDarwin = machineOf {
        root = ./hosts/template;
        overrides.system = "aarch64-darwin";
      };

      home =
        system: modules:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor.${system};
          modules = modules ++ [ ./nix/modules/workstation-home.nix ];
        };

      homeOf = m: home m.system m.homeModules;
      machineHome = homeOf machine;

      linuxHost =
        m:
        (import ./hosts/linux/default.nix {
          inherit nixpkgs home-manager nixos-wsl;
          machine = m;
        }).nixosConfig;
      macHost =
        m:
        (import ./hosts/mac/default.nix {
          inherit
            nixpkgs
            home-manager
            nix-darwin
            nix-homebrew
            ;
          machine = m;
        }).darwinConfig;

      report = import ./nix/report.nix {
        inherit lib;
        eval = machineHome;
        root = self;
        inherit (machine) settings;
      };

    in
    {
      workstation = {
        inherit report;
        rev = self.rev or self.dirtyRev or "unknown";
        keys = {
          home = machine.homeKey;
          system = machine.systemKey;
        };
      };

      # the machine's legs: the home and NixOS planes on linux, darwin on a mac
      homeConfigurations = lib.optionalAttrs (!machine.isDarwin) {
        ${machine.homeKey} = machineHome;
      };
      nixosConfigurations = lib.optionalAttrs (!machine.isDarwin) {
        ${machine.systemKey} = linuxHost machine;
      };
      darwinConfigurations = lib.optionalAttrs machine.isDarwin {
        ${machine.systemKey} = macHost machine;
      };

      homeManagerModules.workstation = ./nix/modules/workstation-home.nix;

      packages = lib.genAttrs systems (
        system: import ./modules/agent/packages.nix { pkgs = nixpkgs.legacyPackages.${system}; }
      );

      checks.${ciSystem} = import ./tests/nix/checks.nix {
        inherit
          self
          nixpkgs
          home
          ciSystem
          report
          ;
        legs = {
          linux = linuxHost templateMachine;
          mac = macHost templateDarwin;
          home = homeOf templateMachine;
        };
      };
    };
}
