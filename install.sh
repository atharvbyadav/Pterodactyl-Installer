#!/bin/bash
# ==========================================================
# Pterodactyl Universal Installer v3
# Debian | Ubuntu | Arch | Fedora | RHEL | Alma | Rocky
# ==========================================================

set -e

GREEN="\e[32m"
RED="\e[31m"
BLUE="\e[34m"
NC="\e[0m"

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Run as root (sudo).${NC}"
  exit 1
fi

clear
echo -e "${BLUE}"
echo "#############################################"
echo "#     PTERODACTYL UNIVERSAL INSTALLER v3     #"
echo "#############################################"
echo -e "${NC}"

# -------------------------
# OS DETECTION
# -------------------------

source /etc/os-release
OS=$ID

case "$OS" in
  debian|ubuntu|linuxmint)
    PM="apt"
    BASE_PKGS="curl ca-certificates gnupg unzip tar git lsb-release"
    PHP_PKGS="php php-cli php-fpm php-mysql php-gd php-mbstring php-zip php-bcmath php-xml php-curl"
    SRV_PKGS="mariadb-server redis-server nginx"
    WEB_USER="www-data"
    ;;
  arch)
    PM="pacman"
    BASE_PKGS="curl ca-certificates unzip tar git"
    PHP_PKGS="php php-fpm php-gd php-intl php-sqlite"
    SRV_PKGS="mariadb redis nginx"
    WEB_USER="http"
    ;;
  fedora|rhel|almalinux|rocky)
    PM="dnf"
    BASE_PKGS="curl ca-certificates unzip tar git"
    PHP_PKGS="php php-cli php-fpm php-mysqlnd php-gd php-mbstring php-zip php-bcmath php-xml php-curl"
    SRV_PKGS="mariadb-server redis nginx"
    WEB_USER="nginx"
    ;;
  *)
    echo -e "${RED}Unsupported OS: $OS${NC}"
    exit 1
    ;;
esac

echo -e "${GREEN}Detected OS: $OS${NC}"
echo -e "${BLUE}Note:${NC} Arch/Fedora are supported for development only."
echo -e "${BLUE}Note:${NC} Faster breaking changes, PHP jumps, and repo instability may occur."
echo -e "${BLUE}Note:${NC} Best production OS: Ubuntu 22.04 LTS or Debian 12."
read -p "Press ENTER to continue or CTRL+C to abort..." </dev/tty

# -------------------------
# FUNCTIONS
# -------------------------

install_base() {
  case $PM in
    apt)
      apt update -y
      apt install -y $BASE_PKGS
      ;;
    pacman)
      pacman -Sy --noconfirm $BASE_PKGS
      ;;
    dnf)
      dnf install -y $BASE_PKGS
      ;;
  esac
}

install_php() {
  case $PM in
    apt)
      apt install -y $PHP_PKGS
      ;;
    pacman)
      pacman -S --noconfirm $PHP_PKGS
      ;;
    dnf)
      dnf install -y $PHP_PKGS
      ;;
  esac
}

install_services() {
  case $PM in
    apt)
      apt install -y $SRV_PKGS
      ;;
    pacman)
      pacman -S --noconfirm $SRV_PKGS
      ;;
    dnf)
      dnf install -y $SRV_PKGS
      ;;
  esac

  systemctl enable mariadb redis nginx
}

install_docker() {
  curl -fsSL https://get.docker.com | bash
  systemctl enable docker
}

install_composer() {
  curl -sS https://getcomposer.org/installer | php
  mv composer.phar /usr/local/bin/composer
}

install_panel() {

  echo -e "${GREEN}Installing Panel...${NC}"

  mkdir -p /var/www/pterodactyl
  cd /var/www/pterodactyl

  curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzf panel.tar.gz

  chmod -R 755 storage bootstrap/cache

  install_composer
  composer install --no-dev --optimize-autoloader

  cp .env.example .env
  php artisan key:generate

  php artisan p:environment:setup
  php artisan p:environment:database
  php artisan migrate --seed --force
  php artisan p:user:make

  chown -R $WEB_USER:$WEB_USER /var/www/pterodactyl

  PHP_SOCK=$(find /run/php -name "php*-fpm.sock" | head -n 1)

  cat <<EOF >/etc/nginx/conf.d/pterodactyl.conf
server {
  listen 80;
  server_name _;
  root /var/www/pterodactyl/public;
  index index.php;

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ \.php$ {
    include fastcgi_params;
    fastcgi_pass unix:$PHP_SOCK;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
  }
}
EOF

  systemctl restart nginx
  systemctl restart php-fpm || true

  echo -e "${GREEN}Panel Installed → http://localhost${NC}"
}

install_wings() {

  echo -e "${GREEN}Installing Wings...${NC}"

  mkdir -p /etc/pterodactyl
  curl -L https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64 \
  -o /usr/local/bin/wings

  chmod +x /usr/local/bin/wings

  cat <<EOF >/etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings
After=docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
ExecStart=/usr/local/bin/wings
Restart=always
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable wings

  echo -e "${GREEN}Wings Installed.${NC}"
}

# -------------------------
# MENU
# -------------------------

echo
echo "Select what you want to install:"
echo "1) Install Panel Only"
echo "2) Install Wings Only"
echo "3) Install Panel + Wings"
read -p "Choose: " CHOICE </dev/tty

case $CHOICE in
  1)
    install_base
    install_php
    install_services
    install_panel
    ;;
  2)
    install_base
    install_docker
    install_wings
    ;;
  3)
    install_base
    install_php
    install_services
    install_docker
    install_panel
    install_wings
    ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

echo
echo -e "${GREEN}Installation Completed Successfully.${NC}"
