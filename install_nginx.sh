#!/bin/bash

# Variables de configuration
NGINX_VERSION="latest"
DOCKER_COMPOSE_VERSION="1.29.2"
INSTALL_DIR="/opt/nginx-docker"

# Codes de couleur pour rendre le texte plus lisible
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # NC pour No Color

# Fonction pour afficher les messages d'information
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Fonction pour afficher les erreurs
error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Vérification que le script est exécuté en tant que root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Ce script doit être exécuté en tant que root. Utilisez sudo."
    fi
}

install_docker() {
    info "Installation de Docker..."
    
    # Mise à jour des paquets
    apt-get update
    
    # Installation des dépendances
    info "Installation des dépendances..."
    apt-get install -y ca-certificates curl gnupg
    
    # Installation de Docker
    curl -fsSL https://get.docker.com | sh
    
    # Ajout du repository Docker
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    
    # Ajout de l'utilisateur au groupe docker
    usermod -aG docker $SUDO_USER
}

create_directory_structure() {
    info "Création de la structure de répertoires..."
    
    mkdir -p "$INSTALL_DIR"/{html,conf,logs,ssl}
    
    # Création d'une page HTML par défaut
    cat > "$INSTALL_DIR/html/index.html" << EOF
    <!DOCTYPE html>
    <html>
        <head>
            <title>Serveur Nginx avec Docker</title>
        </head>
        <body>
            <h1>Serveur Nginx fonctionne avec Docker !</h1>
        </body>
    </html>
EOF
}

create_docker_compose_file() {
    info "Création du fichier docker-compose.yml..."
    
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  nginx:
    image: nginx:$NGINX_VERSION
    container_name: nginx-server
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html
      - ./conf:/etc/nginx/conf.d
    networks:
      - nginx-network

networks:
  nginx-network:
    driver: bridge
EOF
}

start_containers() {
    info "Démarrage des conteneurs Docker..."
    cd "$INSTALL_DIR"
    docker-compose up -d
}

# Fonction principale
main() {
    check_root
    install_docker
    create_directory_structure
    create_docker_compose_file
    start_containers
    info "Installation terminée avec succès!"
}

# Exécution de la fonction principale
main "$@"