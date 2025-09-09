#!/bin/bash
# ============================================
# Script d'installation Docker, Nginx multi-sites et FTP (vsftpd)
# Compatible Debian 12
# Idempotent et commenté
# ============================================

set -e  # Stop script si une commande échoue

# -------- Fonctions utilitaires --------
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
error() { echo -e "\e[31m[ERREUR]\e[0m $1"; }

# -------- Installation Docker & Compose --------
install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        info "Installation de Docker..."
        apt-get update -y
        apt-get install -y ca-certificates curl gnupg lsb-release
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable docker
        systemctl start docker
    else
        info "Docker est déjà installé."
    fi
}

# -------- Créer répertoires pour chaque site --------
setup_directories() {
    info "Création des répertoires Nginx/FTP..."
    mkdir -p ~/docker/nginx/conf.d
    mkdir -p ~/docker/ftp
}

# -------- Ajouter un site --------
add_site() {
    local site=$1
    local ftp_user=$2
    local ftp_pass=$3

    info "Création du site '$site' avec FTP user '$ftp_user'"

    # Dossiers
    mkdir -p ~/docker/ftp/$site

    # Index par défaut si vide
    [[ -f ~/docker/ftp/$site/index.html ]] || echo "<h1>$site fonctionne !</h1>" > ~/docker/ftp/$site/index.html

    # Fichier conf Nginx
    cat > ~/docker/nginx/conf.d/$site.conf <<EOF
server {
    listen 80;
    server_name $site.local;
    root /home/vsftpd/$site;
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

# -------- Création docker-compose.yml --------
create_docker_compose() {
    info "Création du docker-compose.yml..."
    cat > ~/docker/docker-compose.yml <<'EOF'
version: '3.8'

services:
  nginx:
    image: nginx:latest
    container_name: nginx
    ports:
      - "80:80"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./ftp:/home/vsftpd
    networks:
      - webnet
    restart: unless-stopped

  vsftpd:
    image: fauria/vsftpd
    container_name: vsftpd
    ports:
      - "21:21"
      - "30000-30009:30000-30009"
    environment:
      FTP_USER: "site1"
      FTP_PASS: "site1pass"
      PASV_ADDRESS: "127.0.0.1"
      PASV_MIN_PORT: "30000"
      PASV_MAX_PORT: "30009"
      LOG_STDOUT: "TRUE"
    volumes:
      - ./ftp:/home/vsftpd
    networks:
      - webnet
    restart: unless-stopped

networks:
  webnet:
    driver: bridge
EOF
}

# -------- Lancer conteneurs --------
start_containers() {
    info "Lancement des conteneurs Docker..."
    cd ~/docker
    docker compose up -d
}

# -------- Test des sites --------
test_sites() {
    info "Test des sites Nginx..."
    for site in "$@"; do
        curl -s --connect-timeout 5 http://$site.local -o /dev/null
        if [ $? -eq 0 ]; then
            echo "[OK] $site est accessible sur http://$site.local"
        else
            echo "[ERREUR] $site n'est pas accessible."
        fi
    done
}

# -------- Script principal --------
main() {
    install_docker
    setup_directories

    # Ajouter vos sites ici
    add_site "site1" "site1" "site1pass"
    add_site "site2" "site2" "site2pass"

    create_docker_compose
    start_containers

    # Test
    test_sites "site1" "site2"

    info "Installation terminée !"
    echo "N'oublie pas d'ajouter les entrées dans /etc/hosts :"
    echo "127.0.0.1 site1.local"
    echo "127.0.0.1 site2.local"
}

main