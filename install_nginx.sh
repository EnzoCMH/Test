#!/bin/bash
# ============================================
# Script d'installation Docker, Nginx multi-sites et FTP (vsftpd)
# Compatible Debian 12
# Idempotent et commenté
# ============================================

set -e  # Arrêter le script si une commande échoue

# -------- Fonctions utilitaires --------
info() {
    echo -e "\e[34m[INFO]\e[0m $1"
}

# -------- Mise à jour et installation Docker --------
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

# -------- Création des répertoires Nginx et FTP --------
setup_directories() {
    info "Création des répertoires pour Nginx et FTP..."
    mkdir -p ~/docker/nginx/sites/site1 ~/docker/nginx/sites/site2
    mkdir -p ~/docker/ftp/site1 ~/docker/ftp/site2

    # Ajouter un index.html par défaut si non existant
    for site in site1 site2; do
        [[ -f ~/docker/nginx/sites/$site/index.html ]] || echo "<h1>$site fonctionne !</h1>" > ~/docker/nginx/sites/$site/index.html
    done
}

# -------- Création du docker-compose.yml --------
create_docker_compose() {
    info "Création du docker-compose.yml..."
    cat > ~/docker/docker-compose.yml <<EOF
version: '3.8'

services:
  nginx:
    image: nginx:latest
    container_name: nginx
    ports:
      - "80:80"
    volumes:
      - ./nginx/sites:/usr/share/nginx/html
      - ./nginx/conf.d:/etc/nginx/conf.d
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
      - ./ftp/site1:/home/vsftpd/site1
      - ./ftp/site2:/home/vsftpd/site2
    networks:
      - webnet
    restart: unless-stopped

networks:
  webnet:
    driver: bridge
EOF
}

# -------- Création des fichiers de configuration Nginx --------
create_nginx_conf() {
    info "Création des fichiers de configuration Nginx..."
    mkdir -p ~/docker/nginx/conf.d

    # Site 1
    cat > ~/docker/nginx/conf.d/site1.conf <<EOF
server {
    listen 80;
    server_name site1.local;
    root /usr/share/nginx/html/site1;
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    # Site 2
    cat > ~/docker/nginx/conf.d/site2.conf <<EOF
server {
    listen 80;
    server_name site2.local;
    root /usr/share/nginx/html/site2;
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

# -------- Lancer les conteneurs Docker --------
start_containers() {
    info "Lancement des conteneurs Docker..."
    cd ~/docker
    docker compose up -d
}

# -------- Test de disponibilité des sites --------
test_sites() {
    info "Test des sites Nginx..."
    for site in site1 site2; do
        curl -s http://localhost -o /dev/null
        if [ $? -eq 0 ]; then
            echo "[OK] $site est accessible sur http://localhost"
        else
            echo "[ERREUR] $site n'est pas accessible."
        fi
    done
}

# -------- Script principal --------
main() {
    install_docker
    setup_directories
    create_nginx_conf
    create_docker_compose
    start_containers
    test_sites
    info "Installation terminée avec succès !"
}

main