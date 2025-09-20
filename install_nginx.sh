#!/bin/bash
# ============================================
# Script d'installation Docker, Nginx multi-sites et FTP (vsftpd)
# Version SANS le service PHP/Laravel
# Compatible Debian 12
# Idempotent et commenté
# ============================================

set -e  # Stop script si une commande échoue

# -------- Fonctions utilitaires --------
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
error() { echo -e "\e[31m[ERREUR]\e[0m $1"; exit 1; }

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

# -------- Générer des certificats SSL --------
generate_ssl_certs() {
    info "Génération des certificats SSL..."
    mkdir -p ~/docker/nginx/ssl

    # Générer un certificat auto-signé pour chaque site
    for site in "eventhub" "meteo"; do
        # Ne génère que si le certificat n'existe pas déjà
        if [ ! -f ~/docker/nginx/ssl/$site.lurcat.local.crt ]; then
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout ~/docker/nginx/ssl/$site.lurcat.local.key \
                -out ~/docker/nginx/ssl/$site.lurcat.local.crt \
                -subj "/CN=$site.lurcat.local"
        else
            info "Certificat pour $site.lurcat.local existe déjà."
        fi
    done
}

# -------- Ajouter un site --------
add_site() {
    local site=$1
    local ftp_user=$2
    local ftp_pass=$3

    info "Création du site '$site' avec FTP user '$ftp_user'"

    # Dossiers
    mkdir -p ~/docker/ftp/$site
    mkdir -p ~/docker/ftp/$site/public

    # Fichier d'index HTML par défaut si vide (remplacement de PHP)
    [[ -f ~/docker/ftp/$site/public/index.html ]] || echo "<h1>$site fonctionne ! (serveur statique)</h1>" > ~/docker/ftp/$site/public/index.html

    # Fichier conf Nginx
    cat > ~/docker/nginx/conf.d/$site.conf <<EOF
server {
    listen 80;
    server_name $site.lurcat.local;
    root /home/vsftpd/$site/public;
    index index.html index.htm; # Priorité aux fichiers statiques

    location / {
        try_files \$uri \$uri/ =404;
    }
}

server {
    listen 443 ssl;
    server_name $site.lurcat.local;
    root /home/vsftpd/$site/public;
    index index.html index.htm; # Priorité aux fichiers statiques

    ssl_certificate /etc/nginx/ssl/$site.lurcat.local.crt;
    ssl_certificate_key /etc/nginx/ssl/$site.lurcat.local.key;

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
services:
  nginx:
    image: nginx:latest
    container_name: nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./ftp:/home/vsftpd
      - ./nginx/ssl:/etc/nginx/ssl
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
      FTP_USER: "eventhub"
      FTP_PASS: "eventhubpass"
      PASV_ADDRESS: "127.0.0.1" # Remplacez par votre IP publique si besoin
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
    docker compose up -d --remove-orphans
}

# -------- Test des sites --------
test_sites() {
    info "Test des sites Nginx..."
    for site in "$@"; do
        # Utilise --insecure pour les certificats auto-signés
        curl -s --insecure --connect-timeout 5 https://$site.lurcat.local -o /dev/null
        if [ $? -eq 0 ]; then
            echo "[OK] $site est accessible sur https://$site.lurcat.local"
        else
            echo "[ERREUR] $site n'est pas accessible."
        fi
    done
}

# -------- Script principal --------
main() {
    install_docker
    setup_directories
    generate_ssl_certs

    # Ajouter vos sites ici
    add_site "eventhub" "eventhub" "eventhubpass"
    add_site "meteo" "meteo" "meteopass"

    create_docker_compose
    start_containers

    # Test
    test_sites "eventhub" "meteo"

    info "Installation terminée !"
    echo "N'oublie pas d'ajouter les entrées dans ton fichier hosts local :"
    echo "127.0.0.1 eventhub.lurcat.local"
    echo "127.0.0.1 meteo.lurcat.local"
}

main