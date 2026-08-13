{
  description = "Boot session picker for the Valve Steam Machine";

  # Pinned rather than tracking a channel: a fixed revision keeps qt6
  # substitutable from a store that already has it. Bump with `nix flake update`.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/21ea275a7c46aef9d4d6ddc962e6d562e9d94183";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # There is no package output on purpose. The target is SteamOS, which has
      # no nix and already ships qml and kwin_wayland; installing is a matter of
      # copying files, which install.sh does on the machine itself.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.qt6.qtdeclarative # provides the `qml` runtime
            pkgs.qt6.qtbase

            # For steamos-vm/. That directory is plain shell and assumes an
            # ordinary Linux; nothing in it knows about nix. This shell exists so
            # that a machine which happens to be NixOS has the same tools.
            pkgs.qemu # qemu-system-x86_64, qemu-img, qemu-nbd
            pkgs.btrfs-progs # the SteamOS rootfs is btrfs, and read-only
            pkgs.tigervnc # `steamos-vm view`: the guest's screen, with a mouse
          ];

          # The `qml` runtime is not wrapped by nixpkgs, so point it at the QML
          # modules and Qt plugins explicitly.
          shellHook = ''
            export QML2_IMPORT_PATH=${pkgs.qt6.qtdeclarative}/lib/qt-6/qml
            export QML_IMPORT_PATH=$QML2_IMPORT_PATH
            export QT_PLUGIN_PATH=${pkgs.qt6.qtbase}/lib/qt-6/plugins:${pkgs.qt6.qtdeclarative}/lib/qt-6/plugins
            export QT_QPA_PLATFORM=wayland

            # steamos-vm looks for OVMF where distributions put it, and nix puts
            # it in none of those places. Point it at the store copy — which is
            # exactly what those two settings exist for.
            export VM_OVMF_CODE=${pkgs.OVMF.firmware}
            export VM_OVMF_VARS=${pkgs.OVMF.variables}
          '';
        };
      });
    };
}
