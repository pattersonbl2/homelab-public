# DevOps Tools Installation

This folder contains scripts and configurations to install the latest DevOps tooling on macOS.

## 📁 Files

- **`install-devops-tools.sh`** - Main installation script for all DevOps tools
- **`install-vscode-extensions.sh`** - Script to install VS Code/Cursor extensions
- **`Brewfile`** - Homebrew bundle file for declarative installation
- **`vscode-extensions.json`** - Recommended VS Code/Cursor extensions list
- **`INSTALL-TOOLS.md`** - Detailed installation guide

## 🚀 Quick Start

### Install All DevOps Tools
```bash
cd tools
./install-devops-tools.sh
```

### Install VS Code/Cursor Extensions Only
```bash
./install-vscode-extensions.sh
```

### Install Using Brewfile
```bash
brew bundle
```

## 📦 What Gets Installed

The installation script installs 50+ DevOps tools including:

- **Infrastructure as Code**: Terraform, Terragrunt, Pulumi, Ansible, Packer
- **Containers**: Docker, Podman, Colima
- **Kubernetes**: kubectl, Helm, k9s, Kustomize, and more
- **Cloud CLIs**: AWS, Azure, GCP, DigitalOcean, Linode, Vultr
- **CI/CD**: GitHub CLI, GitLab CLI, Jenkins
- **Security**: Vault, Trivy, Snyk, Checkov, tfsec
- **Monitoring**: Prometheus, Grafana, Loki, Jaeger
- **Development**: Git, Node.js, Python, Go, Rust
- **And many more...**

## 📚 Documentation

See `INSTALL-TOOLS.md` for detailed installation instructions, post-installation setup, and troubleshooting.

## 🔄 Updates

To update all installed tools:
```bash
brew update
brew upgrade
```

## 🛠️ Customization

Edit the scripts to:
- Remove tools you don't need
- Add additional tools
- Modify configurations

