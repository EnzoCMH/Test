#!/bin/bash
# ============================================
# Script d'installation Docker, Nginx multi-sites et FTP (vsftpd)
# Version SANS le service PHP/Laravel
# Compatible Debian 12
# Crée les fichiers dans le répertoire de l'utilisateur sudo et non root
# ============================================

set -e  # Stop script si une commande échoue

# -------- Fonctions utilitaires --------
info() { echo -e "\e[34m[INFO]\e[0m $1"; }
error() { echo -e "\e[31m[ERREUR]\e[0m $1"; exit 1; }

# -------- Vérification des privilèges root --------
if [ "$(id -u)" -ne 0 ]; then
  error "Ce script doit être exécuté avec les privilèges root. Utilisez 'sudo'."
fi

# -------- Déterminer le répertoire personnel de l'utilisateur d'origine --------
# Si le script est lancé avec sudo, $SUDO_USER sera défini.
if [ -n "$SUDO_USER" ]; then
    TARGET_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    # Si le script est lancé directement en tant que root, on utilise /root
    TARGET_HOME=/root
fi

info "Le script s'exécutera pour l'utilisateur : ${SUDO_USER:-root}"
info "Les fichiers seront installés dans : $TARGET_HOME/docker"

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
    mkdir -p "$TARGET_HOME/docker/nginx/conf.d"
    mkdir -p "$TARGET_HOME/docker/ftp"
}

# -------- Générer des certificats SSL --------
generate_ssl_certs() {
    info "Génération des certificats SSL..."
    mkdir -p "$TARGET_HOME/docker/nginx/ssl"

    for site in "eventhub" "meteo"; do
        if [ ! -f "$TARGET_HOME/docker/nginx/ssl/$site.lurcat.local.crt" ]; then
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$TARGET_HOME/docker/nginx/ssl/$site.lurcat.local.key" \
                -out "$TARGET_HOME/docker/nginx/ssl/$site.lurcat.local.crt" \
                -subj "/CN=$site.lurcat.local"
        else
            info "Certificat pour $site.lurcat.local existe déjà."
        fi
    done
}

# -------- Ajouter un site --------
add_site() {
    local site=$1

    info "Création de la configuration pour le site '$site'"

    # Dossiers
    mkdir -p "$TARGET_HOME/docker/ftp/$site/public"

    # Fichier d'index HTML par défaut
    [[ -f "$TARGET_HOME/docker/ftp/$site/public/index.html" ]] || echo "<h1>$site fonctionne ! (serveur statique)</h1>" > "$TARGET_HOME/docker/ftp/$site/public/index.html"

    # Fichier conf Nginx
    cat > "$TARGET_HOME/docker/nginx/conf.d/$site.conf" <<EOF
server {
    listen 80;
    server_name $site.lurcat.local;
    root /home/vsftpd/$site/public;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}

server {
    listen 443 ssl;
    server_name $site.lurcat.local;
    root /home/vsftpd/$site/public;
    index index.html index.htm;

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
    cat > "$TARGET_HOME/docker/docker-compose.yml" <<EOF
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
      # Crée un utilisateur FTP pour chaque site
      FTP_USER_eventhub: "eventhub"
      FTP_PASS_eventhub: "eventhubpass"
      FTP_USER_meteo: "meteo"
      FTP_PASS_meteo: "meteopass"

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

# -------- Corriger les permissions --------
fix_permissions() {
    if [ -n "$SUDO_USER" ] && [ -n "$SUDO_GID" ]; then
        info "Correction des permissions pour l'utilisateur $SUDO_USER..."
        chown -R "$SUDO_USER:$SUDO_GID" "$TARGET_HOME/docker"
    fi
}

# -------- Lancer conteneurs --------
start_containers() {
    info "Lancement des conteneurs Docker..."
    cd "$TARGET_HOME/docker"
    docker compose up -d --remove-orphans
}

# -------- Script principal --------
main() {
    install_docker
    setup_directories
    generate_ssl_certs

    add_site "eventhub"
    add_site "meteo"

    create_docker_compose
    fix_permissions # Très important !
    start_containers

    info "Installation terminée !"
    echo "N'oublie pas d'ajouter les entrées dans ton fichier hosts local :"
    echo "# -- Début config Nginx Docker --"
    echo "127.0.0.1 eventhub.lurcat.local"
    echo "127.0.0.1 meteo.lurcat.local"
    echo "# -- Fin config Nginx Docker --"
}

main
