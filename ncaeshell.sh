#!/usr/bin/env bash
# =============================================================================
#  BLUE TEAM TOOLKIT — NCAE CyberGames 2026 Regionals Overflow 3
#  SSH + SMB | Rocky Linux 9 (shell VM)
#  Scored: SSH Login (1000pts), SMB Login (500pts),
#          SMB Write (1000pts), SMB Read (1000pts)
#  Run as root: sudo bash ncae_shell.sh
# =============================================================================

set -uo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m';    BRED='\033[1;31m'
GREEN='\033[0;32m';  BGREEN='\033[1;32m'
YELLOW='\033[1;33m'; CYAN='\033[0;36m';   BCYAN='\033[1;36m'
BLUE='\033[0;34m';   WHITE='\033[1;37m';  DIM='\033[2m';  NC='\033[0m'

LOGFILE="/var/log/ncae_shell_$(date +%Y%m%d_%H%M%S).log"
touch "$LOGFILE"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()     { echo -e "${GREEN}[+]${NC} $*" | tee -a "$LOGFILE"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOGFILE"; }
err()     { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOGFILE"; }
ok()      { echo -e "${BGREEN}[✓]${NC} $*" | tee -a "$LOGFILE"; }
info()    { echo -e "${CYAN}[i]${NC} $*" | tee -a "$LOGFILE"; }
die()     { err "$1"; exit 1; }
section() {
    echo -e "\n${BLUE}══════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}  $*${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════${NC}\n"
}
pause()   { echo; read -rp "  Press [Enter] to continue..."; }

[[ $EUID -ne 0 ]] && die "Must be run as root.  sudo bash $0"

# ── Rocky Linux 9 only ────────────────────────────────────────────────────────
[[ -f /etc/os-release ]] && source /etc/os-release || die "Cannot detect OS."
[[ "$ID" == "rocky" || "$ID" == "rhel" || "$ID" == "almalinux" ]] || \
    warn "This script is designed for Rocky Linux 9. Proceed with caution on $ID."

PKG_INSTALL="dnf install -y"
PKG_REMOVE="dnf remove -y"
PKG_UPDATE="dnf check-update -y; true"
PKG_AUTOREMOVE="dnf autoremove -y"
SSH_SERVICE="sshd"
SFTP_SUBSYSTEM="/usr/libexec/openssh/sftp-server"
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/root/ncae_backups/$(date +%Y%m%d_%H%M%S)"

# =============================================================================
#  !! REPLACE THESE WHEN RELEASED !!
# =============================================================================
# TODO: Replace with real scoring engine public key when released
AUTHORIZED_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC0PLACEHOLDER_REPLACE_ME_WITH_REAL_KEY_WHEN_RELEASED placeholder@scoring-engine"

# TODO: Replace/extend this list with all 25-30 real users when released
# Format: just the username — key auth only, no passwords for SSH
SCORED_USERS=(
    "user01"
    "user02"
    "user03"
    "user04"
    "user05"
    # ── ADD REAL USERS HERE WHEN RELEASED ──
    # "alice"
    # "bob"
    # "charlie"
    # ... up to 30 users
)

# SMB share config — update share name/path if different
SMB_SHARE_NAME="share"
SMB_SHARE_PATH="/srv/samba/share"
# =============================================================================

# =============================================================================
#  BANNER
# =============================================================================
print_header() {
    clear
    echo -e "${BCYAN}"
    echo "  ███╗   ██╗ ██████╗ █████╗ ███████╗"
    echo "  ████╗  ██║██╔════╝██╔══██╗██╔════╝"
    echo "  ██╔██╗ ██║██║     ███████║█████╗  "
    echo "  ██║╚██╗██║██║     ██╔══██║██╔══╝  "
    echo "  ██║ ╚████║╚██████╗██║  ██║███████╗"
    echo "  ╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝╚══════╝"
    echo -e "${YELLOW}         SHELL VM — SSH + SMB${NC}"
    echo -e "${NC}"
    echo -e "  ${WHITE}NCAE 2026 Regionals — Overflow 3${NC}  ${DIM}|${NC}  ${GREEN}Rocky Linux 9${NC}  ${DIM}|${NC}  ${DIM}log: ${LOGFILE}${NC}"
    echo -e "  ${DIM}SSH: 1000pts  |  SMB Login: 500pts  |  SMB Write: 1000pts  |  SMB Read: 1000pts${NC}"
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────────────────────${NC}"
    echo
}

# =============================================================================
#  MAIN MENU
# =============================================================================
main_menu() {
    while true; do
        print_header
        echo -e "  ${WHITE}── SSH OPERATIONS ────────────────────────────────────────${NC}"
        echo -e "   ${BGREEN}[1]${NC}  Initial SSH Setup       ${DIM}install, create users, deploy scoring key${NC}"
        echo -e "   ${CYAN}[2]${NC}  Harden SSH               ${DIM}strict config + fail2ban${NC}"
        echo -e "   ${YELLOW}[3]${NC}  Rebuild SSH (clean)      ${DIM}purge + reinstall + golden config${NC}"
        echo -e "   ${BRED}[4]${NC}  Nuke SSH                 ${DIM}full purge, no reinstall [DANGER]${NC}"
        echo -e "   ${CYAN}[5]${NC}  Verify SSH               ${DIM}status, perms, firewall, key check${NC}"
        echo -e "   ${CYAN}[6]${NC}  Fix chattr / Lock Keys   ${DIM}make authorized_keys immutable${NC}"
        echo -e "   ${CYAN}[7]${NC}  Update scoring key       ${DIM}replace placeholder with real key${NC}"
        echo -e "   ${CYAN}[8]${NC}  Create/sync all users    ${DIM}create all scored SSH users${NC}"
        echo
        echo -e "  ${WHITE}── SMB OPERATIONS ────────────────────────────────────────${NC}"
        echo -e "   ${CYAN}[9]${NC}  SMB Setup                ${DIM}install samba, create share, add users${NC}"
        echo -e "  ${CYAN}[10]${NC}  SMB Status               ${DIM}service status, share check${NC}"
        echo -e "  ${CYAN}[11]${NC}  SMB Harden               ${DIM}tighten smb.conf${NC}"
        echo -e "  ${CYAN}[12]${NC}  Restart SMB              ${DIM}restart smb + nmb services${NC}"
        echo
        echo -e "  ${WHITE}── FIREWALL ───────────────────────────────────────────────${NC}"
        echo -e "  ${CYAN}[13]${NC}  Apply Strict Firewall    ${DIM}DROP all except 22, 445, 139, ICMP${NC}"
        echo -e "  ${CYAN}[14]${NC}  Flush Firewall           ${DIM}ACCEPT all [resets everything]${NC}"
        echo -e "  ${CYAN}[15]${NC}  View Firewall Rules      ${DIM}iptables -L -v${NC}"
        echo
        echo -e "  ${WHITE}── THREAT HUNTING ────────────────────────────────────────${NC}"
        echo -e "  ${CYAN}[16]${NC}  Hunt Suspicious          ${DIM}processes, connections, modified files${NC}"
        echo -e "  ${CYAN}[17]${NC}  Find SUID/SGID Binaries  ${DIM}scan + interactive removal${NC}"
        echo -e "  ${CYAN}[18]${NC}  Audit Cron Jobs          ${DIM}all users, timers, rc.local${NC}"
        echo -e "  ${CYAN}[19]${NC}  Kill Suspicious Process  ${DIM}list + kill + optionally blacklist${NC}"
        echo -e "  ${CYAN}[20]${NC}  Check Reverse Shells     ${DIM}external ESTABLISHED connections${NC}"
        echo
        echo -e "  ${WHITE}── USERS & SYSTEM ────────────────────────────────────────${NC}"
        echo -e "  ${CYAN}[21]${NC}  User Management          ${DIM}list, lock, delete, sudoers${NC}"
        echo -e "  ${CYAN}[22]${NC}  Lock passwd/shadow       ${DIM}tighten permissions${NC}"
        echo -e "  ${CYAN}[23]${NC}  Backup Configs           ${DIM}ssh, passwd, shadow, iptables, smb${NC}"
        echo -e "  ${CYAN}[24]${NC}  Restore Configs          ${DIM}from backup${NC}"
        echo -e "  ${CYAN}[25]${NC}  Service Status           ${DIM}check all scored ports${NC}"
        echo -e "  ${CYAN}[26]${NC}  Show Scoring Public Key  ${DIM}current key in script${NC}"
        echo
        echo -e "   ${DIM}[q]  Quit${NC}"
        echo
        echo -e "  ${DIM}──────────────────────────────────────────────────────────────────────────────${NC}"
        echo -ne "  ${WHITE}Choice:${NC} "
        read -r CHOICE

        case "$CHOICE" in
            1)  op_setup ;;
            2)  op_harden ;;
            3)  op_rebuild ;;
            4)  op_nuke ;;
            5)  op_verify ;;
            6)  op_fix_chattr ;;
            7)  op_update_key ;;
            8)  op_create_users ;;
            9)  op_smb_setup ;;
            10) op_smb_status ;;
            11) op_smb_harden ;;
            12) op_smb_restart ;;
            13) fw_strict ;;
            14) fw_flush ;;
            15) fw_view ;;
            16) hunt_suspicious ;;
            17) find_suid ;;
            18) audit_crons ;;
            19) kill_suspicious ;;
            20) check_reverse_shells ;;
            21) menu_users ;;
            22) lockdown_passwd ;;
            23) backup_configs ;;
            24) restore_configs ;;
            25) service_status ;;
            26) op_show_key ;;
            q|Q) log "Exiting."; exit 0 ;;
            *) warn "Invalid choice."; sleep 1 ;;
        esac
        pause
    done
}

# =============================================================================
#  SSH — 1. INITIAL SETUP
# =============================================================================
op_setup() {
    section "1. INITIAL SSH SETUP"
    info "Installs openssh-server, creates scored users, deploys scoring key."
    warn "Open a second console session before proceeding!"
    echo
    echo -ne "  ${WHITE}Proceed? [y/N]:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted."; return; }
    echo

    log "Updating package lists..."
    dnf check-update -y 2>>"$LOGFILE" || true

    log "Installing OpenSSH server..."
    dnf install -y openssh-server 2>>"$LOGFILE" || die "Failed to install openssh-server"

    [[ -f "$SSHD_CONFIG" ]] || die "Missing $SSHD_CONFIG after install."

    log "Stripping conflicting sshd_config directives..."
    for key in Port ListenAddress PermitRootLogin PasswordAuthentication \
               PubkeyAuthentication PermitEmptyPasswords UsePAM AuthorizedKeysFile \
               ChallengeResponseAuthentication KbdInteractiveAuthentication Subsystem AllowUsers; do
        sed -i "/^${key}[[:space:]]/d"  "$SSHD_CONFIG" 2>/dev/null || true
        sed -i "/^#${key}[[:space:]]/d" "$SSHD_CONFIG" 2>/dev/null || true
    done

    # Build AllowUsers list from scored users array
    local allow_users
    allow_users=$(IFS=' '; echo "${SCORED_USERS[*]}")

    log "Writing sshd_config block..."
    cat >> "$SSHD_CONFIG" << EOF

# --- NCAE SETUP ---
Port 22
ListenAddress 0.0.0.0
Protocol 2

PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

UsePAM yes
Subsystem sftp ${SFTP_SUBSYSTEM}

AllowUsers ${allow_users}
EOF

    log "Generating host keys..."
    ssh-keygen -A 2>>"$LOGFILE" || true

    # Create all scored users
    op_create_users

    log "Validating sshd config..."
    sshd -t || die "sshd config validation FAILED — check $SSHD_CONFIG"

    log "Enabling and starting sshd..."
    systemctl enable sshd 2>>"$LOGFILE"
    systemctl restart sshd

    _open_port_22

    echo
    ok "SSH SETUP COMPLETE"
    systemctl status sshd --no-pager | grep -E "Active:|Main PID:" || true
    echo
    warn "KEY IS PLACEHOLDER — replace with real scoring key when released (option 7)"
}

# =============================================================================
#  SSH — 2. HARDEN
# =============================================================================
op_harden() {
    section "2. HARDEN SSH"
    warn "Keep a second console session open before proceeding!"
    echo -ne "  ${WHITE}Proceed? [y/N]:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted."; return; }
    echo

    [[ -f "$SSHD_CONFIG" ]] || die "Missing $SSHD_CONFIG"

    log "Stripping existing directives..."
    for key in Protocol X11Forwarding AllowTcpForwarding ClientAliveInterval \
               ClientAliveCountMax LoginGraceTime MaxAuthTries AllowAgentForwarding \
               PermitTunnel GatewayPorts PermitUserEnvironment Compression LogLevel \
               StrictModes MaxSessions TCPKeepAlive PrintMotd PrintLastLog SyslogFacility \
               AllowUsers PasswordAuthentication PubkeyAuthentication PermitRootLogin \
               PermitEmptyPasswords ChallengeResponseAuthentication \
               KbdInteractiveAuthentication AuthorizedKeysFile Subsystem; do
        sed -i "/^${key}[[:space:]]/d"  "$SSHD_CONFIG" 2>/dev/null || true
        sed -i "/^#${key}[[:space:]]/d" "$SSHD_CONFIG" 2>/dev/null || true
    done

    local allow_users
    allow_users=$(IFS=' '; echo "${SCORED_USERS[*]}")

    log "Appending hardening directives..."
    cat >> "$SSHD_CONFIG" << EOF

# --- NCAE HARDENING ---
Protocol 2
StrictModes yes
MaxAuthTries 3
MaxSessions 5

PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
GatewayPorts no
PermitUserEnvironment no
Compression no

ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30
TCPKeepAlive yes

PrintMotd no
PrintLastLog yes
SyslogFacility AUTH
LogLevel VERBOSE

Subsystem sftp ${SFTP_SUBSYSTEM}
AllowUsers ${allow_users}
EOF

    log "Validating config..."
    sshd -t || die "sshd config validation FAILED"

    log "Restarting sshd..."
    systemctl restart sshd

    log "Installing fail2ban..."
    dnf install -y epel-release 2>>"$LOGFILE" || true
    dnf install -y fail2ban 2>>"$LOGFILE" || warn "fail2ban install failed"

    if command -v fail2ban-server &>/dev/null; then
        cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 600
findtime = 300
maxretry = 3
backend  = auto

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
EOF
        systemctl enable fail2ban 2>>"$LOGFILE" || true
        systemctl restart fail2ban 2>>"$LOGFILE" || true
        ok "fail2ban configured and running"
    fi

    echo
    ok "SSH HARDENING COMPLETE"
    systemctl status sshd --no-pager | grep -E "Active:|Main PID:" || true
}

# =============================================================================
#  SSH — 3. REBUILD CLEAN
# =============================================================================
op_rebuild() {
    section "3. REBUILD SSH — CLEAN SLATE"
    echo -e "  ${BRED}WARNING: Briefly drops SSH. Have console access ready.${NC}"
    echo
    echo -ne "  ${YELLOW}Type 'REBUILD' to confirm:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" == "REBUILD" ]] || { warn "Aborted."; return; }

    log "Stopping sshd..."
    systemctl stop sshd 2>/dev/null || true

    log "Purging openssh packages..."
    dnf remove -y openssh-server openssh-clients 2>/dev/null || true

    log "Removing /etc/ssh..."
    rm -rf /etc/ssh

    dnf autoremove -y 2>/dev/null || true
    dnf check-update -y 2>>"$LOGFILE" || true

    log "Reinstalling openssh-server..."
    dnf install -y openssh-server 2>>"$LOGFILE" || die "Install failed"
    [[ -d /etc/ssh ]] || die "/etc/ssh missing after install"

    ssh-keygen -A 2>>"$LOGFILE" || true

    local allow_users
    allow_users=$(IFS=' '; echo "${SCORED_USERS[*]}")

    log "Writing golden sshd_config..."
    cat > "$SSHD_CONFIG" << GOLDEN
# NCAE Golden Config — Rocky Linux 9
Port 22
ListenAddress 0.0.0.0
AddressFamily inet
Protocol 2

PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 5

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no

UsePAM yes

AllowTcpForwarding no
X11Forwarding no
PermitTunnel no
GatewayPorts no
AllowAgentForwarding no

LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive yes

PermitUserEnvironment no
Compression no
PrintLastLog yes
PrintMotd no

SyslogFacility AUTH
LogLevel VERBOSE

Subsystem sftp ${SFTP_SUBSYSTEM}

AllowUsers ${allow_users}
GOLDEN

    # Recreate all scored users
    op_create_users

    log "Validating config..."
    sshd -t || die "sshd config FAILED"

    log "Starting sshd..."
    systemctl enable sshd 2>>"$LOGFILE"
    systemctl restart sshd
    sleep 2
    systemctl is-active --quiet sshd && ok "SSH is UP" || \
        die "SSH failed — journalctl -u sshd -n 50"

    _open_port_22

    echo
    ok "REBUILD COMPLETE"
    warn "KEY IS PLACEHOLDER — replace with real key when released (option 7)"
}

# =============================================================================
#  SSH — 4. NUKE
# =============================================================================
op_nuke() {
    section "4. NUKE SSH — FULL PURGE"
    echo -e "  ${BRED}⚠  YOU WILL LOSE REMOTE ACCESS IMMEDIATELY  ⚠${NC}"
    echo
    echo -ne "  ${RED}Type 'NUKE' to confirm:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" == "NUKE" ]] || { warn "Aborted."; return; }
    warn "Starting in 5 seconds... Ctrl+C to abort"
    sleep 5

    systemctl stop sshd 2>/dev/null || true
    systemctl disable sshd 2>/dev/null || true
    dnf remove -y openssh-server openssh-clients 2>/dev/null || true
    rm -rf /etc/ssh
    dnf autoremove -y 2>/dev/null || true

    # Close port 22
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --remove-service=ssh 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    else
        iptables -D INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
        iptables -A INPUT -p tcp --dport 22 -j DROP 2>/dev/null || true
        _save_iptables
    fi

    echo
    echo -e "  ${BRED}SSH NUKED.${NC} Run option ${YELLOW}[3] Rebuild${NC} to restore."
}

# =============================================================================
#  SSH — 5. VERIFY
# =============================================================================
op_verify() {
    section "5. VERIFY / DEBUG SSH"

    echo -e "  ${WHITE}── SERVICE ───────────────────────────────────────${NC}"
    systemctl is-active --quiet sshd && ok "sshd is running" || warn "sshd NOT running"
    systemctl is-enabled --quiet sshd && ok "sshd enabled on boot" || warn "sshd NOT enabled"

    echo -e "\n  ${WHITE}── PORT ──────────────────────────────────────────${NC}"
    ss -tlnp | grep -q ":22 " && ok "Port 22 listening" || warn "Port 22 NOT listening"

    echo -e "\n  ${WHITE}── CONFIG ────────────────────────────────────────${NC}"
    sshd -t 2>&1 && ok "sshd_config valid" || warn "sshd_config has ERRORS"

    echo -e "\n  ${WHITE}── FIREWALLD ─────────────────────────────────────${NC}"
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-services 2>/dev/null | grep -q ssh && \
            ok "firewalld: SSH allowed" || warn "firewalld: SSH NOT in allowed services"
        firewall-cmd --list-all 2>/dev/null | grep -E "services:|ports:"
    fi

    echo -e "\n  ${WHITE}── SELINUX ───────────────────────────────────────${NC}"
    getenforce 2>/dev/null | tee -a "$LOGFILE"
    if sestatus 2>/dev/null | grep -q "enabled"; then
        semanage port -l 2>/dev/null | grep ssh || true
    fi

    echo -e "\n  ${WHITE}── USERS & KEYS ──────────────────────────────────${NC}"
    for user in "${SCORED_USERS[@]}"; do
        local keyfile="/home/${user}/.ssh/authorized_keys"
        if id "$user" &>/dev/null; then
            if [[ -f "$keyfile" ]]; then
                # Check our key is in there
                local our_fp key_fp
                our_fp=$(echo "$AUTHORIZED_KEY" | ssh-keygen -lf /dev/stdin 2>/dev/null | awk '{print $2}') || true
                key_fp=$(ssh-keygen -lf "$keyfile" 2>/dev/null | awk '{print $2}') || true
                if [[ "$our_fp" == "$key_fp" ]]; then
                    ok "  ${user}: key matches"
                else
                    warn "  ${user}: key MISMATCH or multiple keys"
                fi
                # Immutable check
                lsattr "$keyfile" 2>/dev/null | grep -q "\-i\-" && \
                    ok "  ${user}: authorized_keys is IMMUTABLE" || \
                    info "  ${user}: authorized_keys NOT immutable (run option 6)"
            else
                warn "  ${user}: authorized_keys MISSING"
            fi
        else
            warn "  ${user}: USER DOES NOT EXIST"
        fi
    done

    echo -e "\n  ${WHITE}── KEY CONFIG VALUES ─────────────────────────────${NC}"
    for key in PasswordAuthentication PubkeyAuthentication PermitRootLogin \
               Port AllowUsers MaxAuthTries LogLevel; do
        val=$(grep "^${key} " "$SSHD_CONFIG" 2>/dev/null | tail -1 || true)
        [[ -n "${val:-}" ]] && info "$val" || warn "$key not explicitly set"
    done

    echo -e "\n  ${WHITE}── LAST 15 AUTH LOG ENTRIES ──────────────────────${NC}"
    journalctl -u sshd -n 15 --no-pager 2>/dev/null || \
        tail -15 /var/log/secure 2>/dev/null || \
        warn "No auth log found"
}

# =============================================================================
#  SSH — 6. CHATTR FIX + LOCK KEYS
# =============================================================================
op_fix_chattr() {
    section "6. FIX CHATTR + LOCK authorized_keys"
    echo -ne "  ${WHITE}Proceed? [y/N]:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted."; return; }

    if ! command -v chattr &>/dev/null; then
        warn "chattr not found — reinstalling e2fsprogs..."
        dnf install -y e2fsprogs 2>>"$LOGFILE"
        command -v chattr &>/dev/null && ok "chattr restored" || die "chattr still missing"
    else
        ok "chattr found: $(which chattr)"
    fi

    for user in "${SCORED_USERS[@]}"; do
        local keyfile="/home/${user}/.ssh/authorized_keys"
        if [[ -f "$keyfile" ]]; then
            chattr -i "$keyfile" 2>/dev/null || true
            echo "$AUTHORIZED_KEY" > "$keyfile"
            chmod 600 "$keyfile"
            chown "${user}:${user}" "$keyfile"
            chattr +i "$keyfile"
            ok "  ${user}: authorized_keys is now IMMUTABLE"
        else
            warn "  ${user}: authorized_keys not found — run option 1 or 8 first"
        fi
    done
}

# =============================================================================
#  SSH — 7. UPDATE SCORING KEY (run when real key is released)
# =============================================================================
op_update_key() {
    section "7. UPDATE SCORING ENGINE KEY"
    warn "Use this when the real scoring key is released."
    echo
    info "Current key fingerprint:"
    echo "$AUTHORIZED_KEY" | ssh-keygen -lf /dev/stdin 2>/dev/null || \
        info "(placeholder — not a valid key yet)"
    echo
    echo -e "  Paste the new public key (single line, starts with ssh-rsa or ssh-ed25519):"
    echo -ne "  > "; read -r new_key

    [[ -z "$new_key" ]] && { warn "Empty key — aborted."; return; }
    [[ "$new_key" =~ ^ssh- ]] || { warn "Key doesn't look valid (should start with ssh-)"; return; }

    # Update all user authorized_keys
    for user in "${SCORED_USERS[@]}"; do
        local keyfile="/home/${user}/.ssh/authorized_keys"
        [[ -d "/home/${user}/.ssh" ]] || continue
        chattr -i "$keyfile" 2>/dev/null || true
        echo "$new_key" > "$keyfile"
        chmod 600 "$keyfile"
        chown "${user}:${user}" "$keyfile"
        chattr +i "$keyfile"
        ok "  Updated + locked key for: ${user}"
    done

    # Update the variable in this script file itself
    local script_path
    script_path=$(realpath "$0")
    sed -i "s|^AUTHORIZED_KEY=.*|AUTHORIZED_KEY=\"${new_key}\"|" "$script_path" && \
        ok "Script updated with new key." || warn "Could not update script — update manually."

    ok "Key update complete."
}

# =============================================================================
#  SSH — 8. CREATE/SYNC ALL SCORED USERS
# =============================================================================
op_create_users() {
    section "8. CREATE / SYNC SCORED SSH USERS"
    info "Creating ${#SCORED_USERS[@]} users from SCORED_USERS array..."
    echo

    for user in "${SCORED_USERS[@]}"; do
        if id "$user" &>/dev/null; then
            info "  ${user} already exists — refreshing key"
        else
            useradd -m -s /bin/bash "$user" 2>>"$LOGFILE"
            passwd -l "$user" 2>/dev/null || true
            ok "  Created: ${user}"
        fi

        # Set up .ssh dir and authorized_keys
        local ssh_dir="/home/${user}/.ssh"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chattr -i "${ssh_dir}/authorized_keys" 2>/dev/null || true
        echo "$AUTHORIZED_KEY" > "${ssh_dir}/authorized_keys"
        chmod 600 "${ssh_dir}/authorized_keys"
        chown -R "${user}:${user}" "/home/${user}"
        chattr +i "${ssh_dir}/authorized_keys"
        ok "  ${user}: key deployed + locked"

        # Remove from sudo/wheel
        gpasswd -d "$user" sudo  2>/dev/null || true
        gpasswd -d "$user" wheel 2>/dev/null || true
    done

    echo
    ok "All ${#SCORED_USERS[@]} users created and keys deployed."
    warn "KEY IS PLACEHOLDER — run option 7 when real key is released!"
}

# =============================================================================
#  SMB — 9. SETUP
# =============================================================================
op_smb_setup() {
    section "9. SMB SETUP (Samba)"
    info "Scored: SMB Login (500), SMB Write (1000), SMB Read (1000)"
    echo -ne "  ${WHITE}Proceed? [y/N]:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted."; return; }

    log "Installing Samba..."
    dnf install -y samba samba-client samba-common 2>>"$LOGFILE" || die "Samba install failed"

    log "Creating share directory: ${SMB_SHARE_PATH}"
    mkdir -p "$SMB_SHARE_PATH"
    chmod 2775 "$SMB_SHARE_PATH"

    log "Writing smb.conf..."
    cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak_$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    cat > /etc/samba/smb.conf << EOF
[global]
    workgroup = WORKGROUP
    server string = NCAE Shell Server
    netbios name = SHELL
    security = user
    map to guest = never
    encrypt passwords = yes
    smb ports = 445
    log file = /var/log/samba/log.%m
    max log size = 50
    logging = file
    server min protocol = SMB2

[${SMB_SHARE_NAME}]
    path = ${SMB_SHARE_PATH}
    browseable = yes
    read only = no
    valid users = @smbusers
    create mask = 0664
    directory mask = 0775
    force group = smbusers
EOF

    log "Creating smbusers group..."
    groupadd smbusers 2>/dev/null || info "smbusers group already exists"
    chown root:smbusers "$SMB_SHARE_PATH"

    # Add all scored users to samba
    log "Adding scored users to SMB..."
    for user in "${SCORED_USERS[@]}"; do
        id "$user" &>/dev/null || useradd -m -s /bin/bash "$user"
        usermod -aG smbusers "$user"
        # Set SMB password same as system (scoring engine needs to auth)
        echo -e "Password1!\nPassword1!" | smbpasswd -a "$user" -s 2>>"$LOGFILE" && \
            ok "  SMB user added: ${user}" || warn "  SMB user failed: ${user}"
    done

    log "Enabling and starting Samba..."
    systemctl enable smb nmb 2>>"$LOGFILE"
    systemctl restart smb nmb

    _open_smb_ports

    log "Setting SELinux context for share..."
    chcon -R -t samba_share_t "$SMB_SHARE_PATH" 2>/dev/null || \
        warn "SELinux context not set — if SELinux enforcing, run: chcon -R -t samba_share_t ${SMB_SHARE_PATH}"
    setsebool -P samba_enable_home_dirs on 2>/dev/null || true

    echo
    ok "SMB SETUP COMPLETE"
    warn "SMB passwords set to 'Password1!' — change them and update PCR if required!"
    testparm -s 2>/dev/null | head -30
}

# =============================================================================
#  SMB — 10. STATUS
# =============================================================================
op_smb_status() {
    section "10. SMB STATUS"

    echo -e "${YELLOW}── Service status ──${NC}"
    systemctl status smb --no-pager | head -10
    systemctl status nmb --no-pager | head -6

    echo -e "\n${YELLOW}── Ports 445/139 listening ──${NC}"
    ss -tlnp | grep -E ":445|:139" && ok "SMB ports listening" || warn "SMB ports NOT listening!"

    echo -e "\n${YELLOW}── Samba config test ──${NC}"
    testparm -s 2>/dev/null | grep -E "\[|path|valid users|read only"

    echo -e "\n${YELLOW}── SMB users ──${NC}"
    pdbedit -L 2>/dev/null || warn "Could not list SMB users"

    echo -e "\n${YELLOW}── Share directory ──${NC}"
    ls -la "$SMB_SHARE_PATH" 2>/dev/null || warn "Share path not found: ${SMB_SHARE_PATH}"

    echo -e "\n${YELLOW}── Active SMB connections ──${NC}"
    smbstatus 2>/dev/null | head -20 || info "No active connections"
}

# =============================================================================
#  SMB — 11. HARDEN
# =============================================================================
op_smb_harden() {
    section "11. HARDEN SMB"
    cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak_$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

    # Add hardening to global section
    if ! grep -q "server signing" /etc/samba/smb.conf; then
        sed -i '/\[global\]/a\    server signing = mandatory\n    ntlm auth = no\n    restrict anonymous = 2\n    server min protocol = SMB2' \
            /etc/samba/smb.conf
        ok "Hardening directives added to smb.conf"
    fi

    testparm -s 2>/dev/null | head -5 && ok "smb.conf valid" || warn "smb.conf has errors"
    systemctl restart smb nmb
    ok "SMB hardened and restarted."
}

# =============================================================================
#  SMB — 12. RESTART
# =============================================================================
op_smb_restart() {
    section "12. RESTART SMB"
    testparm -s &>/dev/null || { warn "smb.conf invalid — fix before restarting"; return; }
    systemctl restart smb nmb
    sleep 1
    systemctl is-active smb && ok "smb is running" || err "smb failed to start"
    systemctl is-active nmb && ok "nmb is running" || err "nmb failed to start"
}

# =============================================================================
#  FIREWALL HELPERS
# =============================================================================
_save_iptables() {
    if command -v iptables-save &>/dev/null; then
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4
        ok "Rules saved to /etc/iptables/rules.v4"
    fi
}

_open_port_22() {
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-service=ssh 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        ok "firewalld: SSH allowed"
    else
        iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || \
            iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
        _save_iptables
    fi
}

_open_smb_ports() {
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-service=samba 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        ok "firewalld: Samba allowed"
    else
        for port in 445 139; do
            iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
                iptables -A INPUT -p tcp --dport "$port" -j ACCEPT
        done
        iptables -C INPUT -p udp --dport 137 -j ACCEPT 2>/dev/null || \
            iptables -A INPUT -p udp --dport 137 -j ACCEPT
        iptables -C INPUT -p udp --dport 138 -j ACCEPT 2>/dev/null || \
            iptables -A INPUT -p udp --dport 138 -j ACCEPT
        _save_iptables
    fi
}

# =============================================================================
#  FIREWALL — 13. STRICT
# =============================================================================
fw_strict() {
    section "13. STRICT FIREWALL"
    echo -e "  ${GREEN}ALLOWED:${NC} 22 (SSH), 445/139 (SMB), ICMP, ESTABLISHED"
    echo -e "  ${RED}DROPPED:${NC} everything else"
    echo
    echo -ne "  ${WHITE}Proceed? [y/N]:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted."; return; }

    if command -v firewall-cmd &>/dev/null; then
        warn "firewalld detected — using firewalld instead of iptables"
        firewall-cmd --set-default-zone=drop 2>/dev/null || true
        firewall-cmd --permanent --add-service=ssh    2>/dev/null || true
        firewall-cmd --permanent --add-service=samba  2>/dev/null || true
        firewall-cmd --permanent --add-icmp-block-inversion 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        ok "firewalld strict rules applied."
        firewall-cmd --list-all
    else
        iptables -F; iptables -X; iptables -Z
        iptables -P INPUT   DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT  ACCEPT
        iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A INPUT -p icmp -j ACCEPT
        iptables -A INPUT -p tcp --dport 22  -j ACCEPT
        iptables -A INPUT -p tcp --dport 445 -j ACCEPT
        iptables -A INPUT -p tcp --dport 139 -j ACCEPT
        iptables -A INPUT -p udp --dport 137 -j ACCEPT
        iptables -A INPUT -p udp --dport 138 -j ACCEPT
        iptables -A INPUT -m limit --limit 5/min -j LOG --log-prefix "FW_DROP: " --log-level 7
        _save_iptables
        ok "iptables strict rules applied."
    fi
}

# =============================================================================
#  FIREWALL — 14. FLUSH
# =============================================================================
fw_flush() {
    section "14. FLUSH FIREWALL"
    echo -e "  ${BRED}This opens everything.${NC}"
    echo -ne "  ${WHITE}Proceed? [y/N]:${NC} "; read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted."; return; }

    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --set-default-zone=trusted 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        warn "firewalld set to trusted (all open)"
    else
        iptables -F; iptables -X; iptables -Z
        iptables -P INPUT   ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT  ACCEPT
        _save_iptables
        warn "iptables flushed — system fully open"
    fi
}

# =============================================================================
#  FIREWALL — 15. VIEW
# =============================================================================
fw_view() {
    section "15. CURRENT FIREWALL RULES"
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-all
    else
        iptables -L -v -n --line-numbers
    fi
}

# =============================================================================
#  THREAT HUNTING — 16
# =============================================================================
hunt_suspicious() {
    section "16. HUNT SUSPICIOUS ACTIVITY"

    echo -e "\n  ${YELLOW}── Listening Ports (expect 22, 445, 139) ───────────────${NC}"
    ss -tlnp
    echo
    ss -ulnp

    echo -e "\n  ${YELLOW}── Unexpected Listeners ─────────────────────────────────${NC}"
    ss -tlnp | grep LISTEN | grep -vE ":(22|445|139)\b" | \
        grep -vE "127\.0\.0|::1" && warn "Review unexpected ports above!" || ok "No unexpected listeners"

    echo -e "\n  ${YELLOW}── Processes Running as Root ─────────────────────────────${NC}"
    ps aux | awk 'NR==1 || $1=="root"' | grep -v "\[" | head -25

    echo -e "\n  ${YELLOW}── Recently Modified /etc Files ─────────────────────────${NC}"
    find /etc -newer /etc/hostname -type f -mmin -1440 2>/dev/null | head -20

    echo -e "\n  ${YELLOW}── Executables in /tmp /var/tmp /dev/shm ────────────────${NC}"
    for d in /tmp /var/tmp /dev/shm; do
        find "$d" -executable -type f 2>/dev/null | while read -r f; do
            warn "Executable found: $f"
        done
    done

    echo -e "\n  ${YELLOW}── World-Writable Files (outside /tmp) ──────────────────${NC}"
    find / -path /proc -prune -o -path /sys -prune -o \
        -not -path "/tmp/*" -not -path "/var/tmp/*" \
        -perm -002 -type f -print 2>/dev/null | head -15

    echo -e "\n  ${YELLOW}── Users Logged In ──────────────────────────────────────${NC}"
    who; w

    echo -e "\n  ${YELLOW}── Last 20 Auth Log Entries ─────────────────────────────${NC}"
    journalctl -u sshd -n 20 --no-pager 2>/dev/null || \
        tail -20 /var/log/secure 2>/dev/null || \
        warn "Auth log not found"

    echo -e "\n  ${YELLOW}── Failed Login Attempts (top IPs) ──────────────────────${NC}"
    grep "Failed" /var/log/secure 2>/dev/null | \
        grep -oP 'from \K[\d.]+' | sort | uniq -c | sort -rn | head -10 || \
        info "Could not parse /var/log/secure"

    echo -e "\n  ${YELLOW}── SELinux Status ───────────────────────────────────────${NC}"
    getenforce 2>/dev/null
    sestatus 2>/dev/null | grep -E "status|mode"
}

# =============================================================================
#  THREAT HUNTING — 17. SUID
# =============================================================================
find_suid() {
    section "17. FIND SUID/SGID BINARIES"
    log "Scanning for SUID binaries..."
    find / -path /proc -prune -o -path /sys -prune -o \
        -perm /4000 -type f -print 2>/dev/null | tee /tmp/suid_list.txt
    echo
    warn "Common legit SUID: sudo, passwd, su, ping, mount, newgrp"
    warn "Results saved: /tmp/suid_list.txt"

    local gtfo_bins=("python" "python3" "perl" "ruby" "bash" "sh" "find" "awk" "nmap" "vim" "less" "more" "cp" "mv")
    echo -e "\n  ${YELLOW}── Dangerous gtfobins with SUID ─────────────────────────${NC}"
    local found=0
    for bin in "${gtfo_bins[@]}"; do
        local path
        path=$(find / -name "$bin" -perm /4000 2>/dev/null | head -1 || true)
        if [[ -n "$path" ]]; then
            err "SUID on dangerous binary: $path"
            found=1
            echo -ne "    ${WHITE}Remove SUID from $path? [y/N]:${NC} "; read -r r
            [[ "$r" =~ ^[Yy]$ ]] && chmod u-s "$path" && ok "SUID removed from $path"
        fi
    done
    [[ "$found" -eq 0 ]] && ok "No dangerous SUID binaries found"
}

# =============================================================================
#  THREAT HUNTING — 18. CRONS
# =============================================================================
audit_crons() {
    section "18. AUDIT CRON JOBS & STARTUP SCRIPTS"

    echo -e "\n  ${YELLOW}── Root crontab ─────────────────────────────────────────${NC}"
    crontab -l 2>/dev/null || info "No root crontab"

    echo -e "\n  ${YELLOW}── /etc/crontab ─────────────────────────────────────────${NC}"
    cat /etc/crontab 2>/dev/null || true

    echo -e "\n  ${YELLOW}── /etc/cron.d/ ─────────────────────────────────────────${NC}"
    ls -la /etc/cron.d/ 2>/dev/null || true
    for f in /etc/cron.d/*; do
        [[ -f "$f" ]] && echo "--- $f ---" && cat "$f"
    done

    echo -e "\n  ${YELLOW}── All user crontabs ────────────────────────────────────${NC}"
    while IFS=: read -r user _; do
        local jobs
        jobs=$(crontab -u "$user" -l 2>/dev/null | grep -v "^#" | grep -v "^$" || true)
        [[ -n "$jobs" ]] && echo -e "  ${CYAN}${user}:${NC} $jobs"
    done < /etc/passwd

    echo -e "\n  ${YELLOW}── Systemd timers ───────────────────────────────────────${NC}"
    systemctl list-timers --all 2>/dev/null | head -20

    echo -e "\n  ${YELLOW}── Custom systemd units ─────────────────────────────────${NC}"
    find /etc/systemd/system -name "*.service" 2>/dev/null | while read -r f; do
        grep -l "ExecStart" "$f" 2>/dev/null && echo "  -> $(grep ExecStart "$f")"
    done
}

# =============================================================================
#  THREAT HUNTING — 19. KILL PROCESS
# =============================================================================
kill_suspicious() {
    section "19. KILL SUSPICIOUS PROCESSES"

    echo -e "  ${YELLOW}── Processes by CPU usage ───────────────────────────────${NC}"
    ps aux --sort=-%cpu | head -25
    echo

    echo -ne "  ${WHITE}Enter PID to kill (or 'skip'):${NC} "; read -r pid
    if [[ "$pid" != "skip" && "$pid" =~ ^[0-9]+$ ]]; then
        local proc_name
        proc_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
        kill -9 "$pid" 2>/dev/null && ok "Killed PID $pid ($proc_name)" || err "Could not kill PID $pid"

        if [[ "$proc_name" != "unknown" ]]; then
            echo -ne "  ${WHITE}Blacklist $proc_name (chmod 000)? [y/N]:${NC} "; read -r bl
            if [[ "$bl" =~ ^[Yy]$ ]]; then
                local bin_path
                bin_path=$(which "$proc_name" 2>/dev/null || true)
                [[ -n "$bin_path" ]] && chmod 000 "$bin_path" && ok "Permissions removed: $bin_path"
            fi
        fi
    fi
}

# =============================================================================
#  THREAT HUNTING — 20. REVERSE SHELLS
# =============================================================================
check_reverse_shells() {
    section "20. CHECK REVERSE SHELLS"

    echo -e "  ${YELLOW}── All ESTABLISHED connections ──────────────────────────${NC}"
    ss -tnp | grep ESTAB || true

    echo -e "\n  ${YELLOW}── External connections (non-RFC1918) ───────────────────${NC}"
    local found=0
    while IFS= read -r line; do
        if ! echo "$line" | grep -qE "(192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.)"; then
            err "Suspicious external connection: $line"
            found=1
        fi
    done < <(ss -tnp | grep ESTAB || true)
    [[ "$found" -eq 0 ]] && ok "No unexpected external connections"

    echo -e "\n  ${YELLOW}── Common reverse shell process names ───────────────────${NC}"
    for name in "nc " "ncat" "netcat" "bash -i" "sh -i" "python -c" "perl -e"; do
        pgrep -a "$name" 2>/dev/null && warn "Possible reverse shell: $name" || true
    done
}

# =============================================================================
#  USERS — 21. USER MANAGEMENT
# =============================================================================
menu_users() {
    section "21. USER MANAGEMENT"
    echo "  [1] List users with login shells"
    echo "  [2] Change user password"
    echo "  [3] Lock a user account"
    echo "  [4] Delete a user"
    echo "  [5] Audit sudoers"
    echo "  [6] Remove user from sudo/wheel"
    echo "  [7] List UID 0 accounts (root equiv)"
    echo "  [8] Back"
    echo -ne "\n  ${WHITE}Choice:${NC} "; read -r uc

    case "$uc" in
        1) echo; awk -F: '$7 !~ /nologin|false/ {print $1, $3, $6, $7}' /etc/passwd | column -t ;;
        2) echo -ne "  Username: "; read -r u
           echo -ne "  New password: "; read -rs p; echo
           echo "${u}:${p}" | chpasswd && ok "Password changed for $u" ;;
        3) echo -ne "  Username to lock: "; read -r u
           passwd -l "$u" && usermod --expiredate 1 "$u" && ok "Locked: $u" ;;
        4) echo -ne "  Username to delete: "; read -r u
           userdel -r "$u" 2>>"$LOGFILE" && ok "Deleted $u" || err "Failed" ;;
        5) grep -v "^#\|^$" /etc/sudoers 2>/dev/null
           cat /etc/sudoers.d/* 2>/dev/null || true
           getent group sudo wheel 2>/dev/null || true ;;
        6) echo -ne "  Username: "; read -r u
           gpasswd -d "$u" wheel 2>/dev/null && ok "Removed from wheel" || warn "Not in wheel" ;;
        7) awk -F: '$3==0 {print $1}' /etc/passwd ;;
        8) return ;;
    esac
}

# =============================================================================
#  SYSTEM — 22. LOCKDOWN PASSWD/SHADOW
# =============================================================================
lockdown_passwd() {
    section "22. LOCK DOWN /etc/passwd AND /etc/shadow"
    chown root:root /etc/passwd /etc/shadow /etc/group /etc/gshadow
    chmod 644 /etc/passwd /etc/group
    chmod 000 /etc/shadow /etc/gshadow
    ok "passwd/group=644, shadow/gshadow=000"
}

# =============================================================================
#  SYSTEM — 23. BACKUP
# =============================================================================
backup_configs() {
    section "23. BACKUP CRITICAL CONFIGS"
    mkdir -p "$BACKUP_DIR"

    local files=(
        "/etc/ssh/sshd_config"
        "/etc/passwd" "/etc/shadow"
        "/etc/group"  "/etc/gshadow"
        "/etc/sudoers"
        "/etc/iptables/rules.v4"
        "/etc/hosts"  "/etc/hostname"
        "/etc/crontab"
        "/etc/samba/smb.conf"
    )

    for f in "${files[@]}"; do
        [[ -e "$f" ]] && cp -a "$f" "$BACKUP_DIR/" 2>>"$LOGFILE" && log "Backed up: $f"
    done

    ok "Backup stored: $BACKUP_DIR"
    ls -la "$BACKUP_DIR"
}

# =============================================================================
#  SYSTEM — 24. RESTORE
# =============================================================================
restore_configs() {
    section "24. RESTORE CONFIGS"
    local backup_root="/root/ncae_backups"
    [[ -d "$backup_root" ]] || { warn "No backups found at $backup_root"; return; }

    echo "Available backups:"
    ls -1 "$backup_root"
    echo -ne "\n  Enter timestamp (or 'latest'): "; read -r ts
    [[ "$ts" == "latest" ]] && ts=$(ls -1t "$backup_root" | head -1)

    local bdir="${backup_root}/${ts}"
    [[ -d "$bdir" ]] || { err "Backup not found: $bdir"; return; }

    warn "Restoring from: $bdir"
    echo -ne "  Confirm? [y/N]: "; read -r c
    [[ "$c" =~ ^[Yy]$ ]] || return

    for f in "$bdir"/*; do
        fname=$(basename "$f")
        case "$fname" in
            sshd_config) cp "$f" /etc/ssh/sshd_config && ok "Restored sshd_config"
                         sshd -t && systemctl restart sshd && ok "sshd restarted" ;;
            passwd)      cp "$f" /etc/passwd  && ok "Restored passwd" ;;
            shadow)      cp "$f" /etc/shadow  && ok "Restored shadow" ;;
            group)       cp "$f" /etc/group   && ok "Restored group" ;;
            sudoers)     cp "$f" /etc/sudoers && ok "Restored sudoers" ;;
            smb.conf)    cp "$f" /etc/samba/smb.conf && \
                         testparm -s &>/dev/null && systemctl restart smb nmb && \
                         ok "SMB config restored and restarted" ;;
            rules.v4)    cp "$f" /etc/iptables/rules.v4 && \
                         iptables-restore < /etc/iptables/rules.v4 && \
                         ok "Firewall restored and applied" ;;
            *)           warn "Unknown file: $fname" ;;
        esac
    done
}

# =============================================================================
#  SYSTEM — 25. SERVICE STATUS
# =============================================================================
service_status() {
    section "25. SCORED SERVICE STATUS"
    echo

    _chk() {
        local name="$1" port="$2" proto="${3:-tcp}"
        if [[ "$proto" == "udp" ]]; then
            ss -ulnp | grep -q ":${port} " && \
                echo -e "  ${BGREEN}[UP]${NC}   ${name} (UDP:${port})" || \
                echo -e "  ${BRED}[DOWN]${NC} ${name} (UDP:${port})"
        else
            ss -tlnp | grep -q ":${port} " && \
                echo -e "  ${BGREEN}[UP]${NC}   ${name} (TCP:${port})" || \
                echo -e "  ${BRED}[DOWN]${NC} ${name} (TCP:${port})"
        fi
    }

    _chk "SSH Login (1000pts)"    22   tcp
    _chk "SMB (445) (2500pts)"    445  tcp
    _chk "SMB NetBIOS (139)"      139  tcp

    echo
    info "Scored users: ${#SCORED_USERS[@]} configured"
    warn "KEY STATUS: $(echo "$AUTHORIZED_KEY" | grep -q PLACEHOLDER && echo 'PLACEHOLDER — update with option 7!' || echo 'Real key deployed')"
}

# =============================================================================
#  SHOW KEY — 26
# =============================================================================
op_show_key() {
    section "CURRENT SCORING ENGINE PUBLIC KEY"
    echo -e "  ${DIM}Deployed to all users' authorized_keys${NC}"
    echo
    echo -e "${DIM}────────────────────────────────────────────────────────${NC}"
    echo -e "${GREEN}${AUTHORIZED_KEY}${NC}"
    echo -e "${DIM}────────────────────────────────────────────────────────${NC}"
    echo
    echo "$AUTHORIZED_KEY" | grep -q PLACEHOLDER && \
        warn "THIS IS A PLACEHOLDER — replace with real key using option 7 when released!" || \
        ok "Real key is deployed."
}

# =============================================================================
#  ENTRY
# =============================================================================
main_menu
