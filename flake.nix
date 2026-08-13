{
  description = "Editor-independent durable messaging for Codex and Claude sessions";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = function:
        nixpkgs.lib.genAttrs systems (system: function (import nixpkgs { inherit system; }));
      packagesFor = pkgs:
        let
          inboxAwarenessHook = pkgs.writeShellApplication {
            name = "llmsend-inbox-awareness-hook";
            runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.git pkgs.jq ];
            text = builtins.readFile ./skills/llmsend/scripts/inbox-awareness-hook;
          };
          inboxMonitor = pkgs.writeShellApplication {
            name = "llmsend-inbox-monitor";
            runtimeInputs = [ pkgs.coreutils ];
            text = builtins.readFile ./skills/llmsend/scripts/inbox-monitor;
          };
          notifySession = pkgs.writeShellApplication {
            name = "llmsend-notify-session";
            runtimeInputs = [ pkgs.tmux ];
            text = builtins.readFile ./skills/llmsend/scripts/notify-session;
          };
          blockPromptInjectionHook = pkgs.writeShellApplication {
            name = "llmsend-block-prompt-injection-hook";
            runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.jq ];
            text = builtins.readFile ./skills/llmsend/scripts/block-prompt-injection-hook;
          };
        in {
          inherit inboxAwarenessHook inboxMonitor notifySession blockPromptInjectionHook;
          default = pkgs.symlinkJoin {
            name = "llmsend-tools";
            paths = [ inboxAwarenessHook inboxMonitor notifySession blockPromptInjectionHook ];
          };
        };
    in {
      packages = forAllSystems packagesFor;

      checks = forAllSystems (pkgs:
        let packages = packagesFor pkgs;
        in {
          package = packages.default;
          test = pkgs.stdenvNoCC.mkDerivation {
            pname = "llmsend-tests";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.findutils pkgs.git pkgs.jq pkgs.ripgrep ];
            buildPhase = ''
              runHook preBuild
              cp -R "$src" work
              chmod -R u+w work
              patchShebangs work
              cd work
              ./test
              runHook postBuild
            '';
            installPhase = ''
              mkdir -p "$out"
              printf 'llmsend tests passed\n' > "$out/result"
            '';
          };
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.bash pkgs.coreutils pkgs.findutils pkgs.git pkgs.jq pkgs.ripgrep pkgs.tmux ];
        };
      });
    };
}
