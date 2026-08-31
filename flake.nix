{
  description = "Nhost-inspired Nix, EKS, Terraform, and Kustomize platform lab";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [ "terraform" ];
        };
        version = self.shortRev or self.dirtyShortRev or "dev";
        commit = self.rev or self.dirtyRev or "unknown";

        demoApi = import ./services/demo-api/project.nix {
          inherit pkgs version commit;
        };

        demoApiImage = pkgs.dockerTools.buildLayeredImage {
          name = "demo-api";
          tag = version;
          created = "1970-01-01T00:00:01Z";
          contents = [ pkgs.cacert ];
          config = {
            Entrypoint = [ "${demoApi}/bin/demo-api" ];
            Env = [
              "PORT=3000"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            ExposedPorts = { "3000/tcp" = { }; };
            User = "65532:65532";
            Labels = {
              "org.opencontainers.image.source" = "https://github.com/olandodeflexy/nhost-platform-lab";
              "org.opencontainers.image.revision" = commit;
              "org.opencontainers.image.version" = version;
            };
          };
        };

        manifestCheck = pkgs.writeShellApplication {
          name = "manifest-check";
          runtimeInputs = [ pkgs.kubeconform pkgs.kustomize ];
          text = ''
            export KUSTOMIZE_ROOT=${./deploy/kustomize}
            ${builtins.readFile ./scripts/check-manifests.sh}
          '';
        };

        manifestValidation = pkgs.runCommand "kustomize-manifest-validation" {
          # Nix builds cannot fetch kubeconform schemas. Full schema validation
          # runs through the manifest-check app outside the Nix sandbox in CI.
          nativeBuildInputs = [ pkgs.kustomize ];
        } ''
          export KUSTOMIZE_ROOT=${./deploy/kustomize}
          ${builtins.readFile ./scripts/check-manifests.sh}
          touch "$out"
        '';

        deploy = pkgs.writeShellApplication {
          name = "deploy";
          runtimeInputs = [ pkgs.awscli2 pkgs.jq pkgs.kubectl pkgs.kustomize ];
          text = ''
            export KUSTOMIZE_ROOT="''${KUSTOMIZE_ROOT:-${./deploy/kustomize}}"
            ${builtins.readFile ./scripts/deploy.sh}
          '';
        };

        verifyPromotion = pkgs.writeShellApplication {
          name = "verify-promotion";
          runtimeInputs = [ pkgs.awscli2 pkgs.gh pkgs.jq pkgs.skopeo ];
          text = builtins.readFile ./scripts/verify-promotion.sh;
        };

        linuxPackages = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          demo-api-image = demoApiImage;
          publish-image = pkgs.writeShellApplication {
            name = "publish-image";
            runtimeInputs = [ pkgs.awscli2 pkgs.jq pkgs.skopeo ];
            text = ''
              export IMAGE_ARCHIVE=${demoApiImage}
              ${builtins.readFile ./scripts/publish-image.sh}
            '';
          };
        };
      in
      {
        packages = {
          default = demoApi;
          demo-api = demoApi;
          manifest-check = manifestCheck;
          deploy = deploy;
          verify-promotion = verifyPromotion;
        } // linuxPackages;

        apps = {
          manifest-check = flake-utils.lib.mkApp { drv = manifestCheck; };
          deploy = flake-utils.lib.mkApp { drv = deploy; };
          verify-promotion = flake-utils.lib.mkApp { drv = verifyPromotion; };
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          publish-image = flake-utils.lib.mkApp { drv = linuxPackages.publish-image; };
        };

        checks = {
          demo-api = demoApi;
          manifests = manifestValidation;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          demo-api-image = demoApiImage;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.actionlint
            pkgs.awscli2
            pkgs.git
            pkgs.go
            pkgs.golangci-lint
            pkgs.gh
            pkgs.kubeconform
            pkgs.kubectl
            pkgs.kubernetes-helm
            pkgs.kustomize
            pkgs.ripgrep
            pkgs.shellcheck
            pkgs.skopeo
            pkgs.terraform
            pkgs.terragrunt
          ];
        };

        formatter = pkgs.alejandra;
      });
}
