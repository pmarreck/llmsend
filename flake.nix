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
          wakeLua = pkgs.luajit.withPackages (p: [ p.luafilesystem p.lua-cjson ]);
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
            # Herdr must be the caller's session-aware installed client. Do not
            # pull a second server version into this notification wrapper.
            runtimeInputs = [ pkgs.coreutils wakeLua ];
            text = ''
              export LLMSEND_SCRIPT_DIR=${./skills/llmsend/scripts}
            '' + builtins.readFile ./skills/llmsend/scripts/notify-session;
          };
          blockPromptInjectionHook = pkgs.writeShellApplication {
            name = "llmsend-block-prompt-injection-hook";
            runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.jq ];
            text = builtins.readFile ./skills/llmsend/scripts/block-prompt-injection-hook;
          };
          writeNote = pkgs.writeShellApplication {
            name = "llmsend-write-note";
            runtimeInputs = [ pkgs.coreutils pkgs.gnused pkgs.jq ];
            text = builtins.readFile ./skills/llmsend/scripts/write-note;
          };
        in {
          inherit inboxAwarenessHook inboxMonitor notifySession blockPromptInjectionHook writeNote;
          default = pkgs.symlinkJoin {
            name = "llmsend-tools";
            paths = [ inboxAwarenessHook inboxMonitor notifySession blockPromptInjectionHook writeNote ];
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
            nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.findutils pkgs.git pkgs.gnused pkgs.jq pkgs.ripgrep (pkgs.luajit.withPackages (p: [ p.luafilesystem p.lua-cjson ])) ];
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
          packages = [ pkgs.bash pkgs.coreutils pkgs.findutils pkgs.git pkgs.gnused pkgs.jq pkgs.ripgrep (pkgs.luajit.withPackages (p: [ p.luafilesystem p.lua-cjson ])) ];
        };
      });
    };
}
