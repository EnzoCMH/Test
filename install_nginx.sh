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
    apt-get install -y ca-certificates curl gnupg
    
    # Ajout de la clé GPG officielle de Docker
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    
    # Ajout du repository Docker
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    
    # Installation de Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Ajout de l'utilisateur au groupe docker
    usermod -aG docker $SUDO_USER
}