# The foundation domain (always on): bash and zsh, the user-local bin on
# PATH, fd, ripgrep, lazygit, mise, newt, direnv + nix-direnv.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  extras = config.workstation.foundation.shell.extras;
  # a hard-killed TUI leaves mouse reporting on and the pane prints escape
  # garbage at the prompt; every prompt clears the mouse modes
  mouseReset = ''
    ws_mouse_reset() { printf '\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l'; }
  '';
in
{
  options.workstation.foundation.shell.extras = lib.mkOption {
    type = lib.types.lines;
    default = "";
    description = "The operator's interactive shell lines, rendered last in .bashrc and .zshrc.";
  };

  config = lib.mkMerge [
    {
      programs.bash.enable = true;
      programs.zsh.enable = true;

      home.sessionPath = [
        "$HOME/.local/bin"
        "${config.home.profileDirectory}/bin"
      ];

      home.packages = [
        pkgs.fd
        pkgs.ripgrep
        pkgs.lazygit
        pkgs.mise
        pkgs.newt
      ];

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        enableBashIntegration = false;
      };
      programs.bash.initExtra = lib.mkOrder 1950 ''
        eval "$(${lib.getExe config.programs.direnv.package} hook bash)"
        ${mouseReset}
        PROMPT_COMMAND="ws_mouse_reset''${PROMPT_COMMAND:+;''${PROMPT_COMMAND}}"
      '';

      programs.zsh.initContent = lib.mkOrder 1960 ''
        ${mouseReset}
        precmd_functions+=(ws_mouse_reset)
      '';

      # the UTF-8 session default: bare shells (ssh commands, launchers) start
      # with no locale and pagers render multibyte glyphs as hex bytes;
      # C.UTF-8 is builtin to glibc and needs no archive generation
      home.sessionVariables = {
        LANG = lib.mkDefault "C.UTF-8";
        # a nix host outside NixOS resolves locales from the host's archive;
        # NixOS owns its own path and its own environment
        LOCALE_ARCHIVE = lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && !builtins.pathExists /etc/NIXOS) (
          lib.mkDefault "/usr/lib/locale/locale-archive"
        );
      };
    }
    (lib.mkIf (extras != "") {
      programs.bash.initExtra = lib.mkOrder 2000 extras;
      programs.zsh.initContent = lib.mkOrder 2000 extras;
    })
  ];
}
