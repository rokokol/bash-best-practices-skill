{
  description = "A standard for shell utilities: one shape, help as the truth, the bash macOS ships";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      # Darwin too: the checker travels to repositories that run CI on macOS, and a
      # contributor there gets `nix develop -c ./check.sh` rather than a flake that does
      # not know their system. Apple silicon only — nixpkgs 26.11 dropped x86_64-darwin,
      # and naming a platform the flake cannot be evaluated for is what the gate refuses.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The pinned toolbox for check.sh, locally and in CI. Every tool a check runs comes
      # from here rather than from whatever the runner happens to have: an unpinned lookup
      # changes a check's behaviour with zero change in the repository
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            actionlint
            shellcheck
            shfmt
            # zsh is not shellcheck's language; `zsh -n` is what can be checked on the
            # zsh completion files the skill ships
            zsh
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
