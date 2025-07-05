#!/bin/bash

# === Colors ===
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
NC='\033[0m'

# === Root check ===
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Please run this script as root (sudo)${NC}"
  exit 1
fi

# === Welcome banner ===
clear
echo -e "${YELLOW}==================================================${NC}"
echo -e "${GREEN}=       🚀 Nexus Multi-Node Setup              =${NC}"
echo -e "${YELLOW}=  Telegram: https://t.me/KatayanAirdropGnC  =${NC}"
echo -e "${GREEN}=        by: _Jheff | PNGO Boiz!!             =${NC}"
echo -e "${YELLOW}==================================================${NC}\n"

# === Working directory ===
WORKDIR="/root/nexus-prover"
echo -e "${GREEN}[*] Working directory: $WORKDIR${NC}"
mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1

# === Install dependencies ===
apt update && apt upgrade -y
apt install -y screen curl wget build-essential pkg-config libssl-dev git-all protobuf-compiler ca-certificates

# === Install Rust if missing ===
if ! command -v rustup &>/dev/null; then
  echo -e "${GREEN}[*] Installing Rust...${NC}"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

# === Setup Rust environment ===
source "$HOME/.cargo/env"
echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> "$HOME/.bashrc"
source "$HOME/.bashrc"
rustup target add riscv32i-unknown-none-elf

# === Ask user to choose install method ===
echo -e "${YELLOW}[?] Do you want to build Nexus CLI from source? (y/n)${NC}"
read -rp "> " USE_SOURCE

if [[ "$USE_SOURCE" == "y" || "$USE_SOURCE" == "Y" ]]; then
  echo -e "${GREEN}[*] Building Nexus CLI from source...${NC}"
  cd "$WORKDIR"
  git clone https://github.com/nexus-xyz/nexus-cli.git
  cd "$WORKDIR/nexus-cli/clients/cli" || exit 1
  cargo build --release

  if [ ! -f "$WORKDIR/nexus-cli/target/release/nexus-network" ]; then
    echo -e "${RED}[!] Build failed. nexus-network binary not found.${NC}"
    exit 1
  fi

  cp "$WORKDIR/nexus-cli/target/release/nexus-network" /usr/local/bin/
  chmod +x /usr/local/bin/nexus-network
  echo -e "${GREEN}[✓] Nexus CLI built and installed successfully.${NC}"
else
  # === Install Nexus CLI prebuilt ===
  echo -e "${GREEN}[*] Downloading and installing Nexus CLI...${NC}"
  yes | curl -s https://cli.nexus.xyz/ | bash

  # === Reload shell path ===
  source "$HOME/.bashrc"

  # === Find and copy binary if needed ===
  echo -e "${GREEN}[*] Locating nexus-network binary...${NC}"
  NEXUS_BIN=$(find / -type f -name "nexus-network" -perm /u+x 2>/dev/null | head -n 1)

  if [ -x "$NEXUS_BIN" ]; then
    echo -e "${GREEN}[✓] nexus-network found at: $NEXUS_BIN${NC}"
    cp "$NEXUS_BIN" /usr/local/bin/
    chmod +x /usr/local/bin/nexus-network
  else
    echo -e "${RED}[!] nexus-network binary not found after install. Aborting.${NC}"
    exit 1
  fi
fi

# === Ask user how many nodes ===
echo -e "${YELLOW}[?] How many node IDs do you want to run? (1-10)${NC}"
read -rp "> " NODE_COUNT
if ! [[ "$NODE_COUNT" =~ ^[1-9]$|^10$ ]]; then
  echo -e "${RED}[!] Invalid number. Choose between 1 to 10.${NC}"
  exit 1
fi

# === Read node IDs ===
NODE_IDS=()
for ((i=1;i<=NODE_COUNT;i++)); do
  echo -e "${YELLOW}Enter node-id #$i:${NC}"
  read -rp "> " NODE_ID
  if [ -z "$NODE_ID" ]; then
    echo -e "${RED}[!] Empty node-id. Aborting.${NC}"
    exit 1
  fi
  NODE_IDS+=("$NODE_ID")
done

# === Launch nodes in screen sessions ===
for ((i=0;i<NODE_COUNT;i++)); do
  SESSION_NAME="nexus$((i+1))"
  NODE_ID="${NODE_IDS[$i]}"
  
  screen -S "$SESSION_NAME" -X quit >/dev/null 2>&1 || true

  echo -e "${GREEN}[*] Launching node-id $NODE_ID in screen session '$SESSION_NAME'...${NC}"
  
  screen -dmS "$SESSION_NAME" bash -c "cd $WORKDIR && nexus-network start --node-id $NODE_ID 2>&1 | tee $WORKDIR/log_$SESSION_NAME.txt"
  
  sleep 1

  if screen -list | grep -q "$SESSION_NAME"; then
    echo -e "${GREEN}[✓] Screen '$SESSION_NAME' created successfully for node-id $NODE_ID.${NC}"
  else
    echo -e "${RED}[✗] Failed to create screen for node-id $NODE_ID (${SESSION_NAME}).${NC}"
  fi

  sleep 1
done

# === Final instructions ===
echo -e "${YELLOW}\n[i] To detach logs: CTRL+A then D"
echo -e "[i] To reattach: screen -r nexus1 (or nexus2, etc.)"
echo -e "[i] To stop: screen -XS nexusX quit"
echo -e "[i] To cleanup: rm -rf $WORKDIR${NC}"
echo -e "${GREEN}[✓] All done. Nexus prover nodes are running.${NC}"
