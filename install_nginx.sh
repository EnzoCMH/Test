#!/usr/bin/env bash
#
# install_docker_nginx.sh
# Installation automatisée de Docker + déploiement d'un conteneur Nginx
# Compatible Debian 12 (bookworm).
#
# Usage: sudo ./install_docker_nginx.sh
#
# Variables configurables (exportez-les avant d'exécuter le script
# pour changer le comportement) :
#   USE_REVERSE_PROXY=false   -> si true, active un exemple de reverse proxy
#   PROXY_UPSTREAM="http://127.0.0.1:8080" -> cible pour le reverse proxy si activé
#   INSTALL_DIR=/opt/docker/nginx  -> dossier hôte avec config/html
#
set -euo pipefail

### Configuration (modifiable via variables d'environnement) ###
: "${USE_REVERSE_PROXY:=false}"
: "${PROXY_UPSTREAM:=http://example.com}"   # exemple ; à remplacer si USE_REVERSE_PROXY=true
: "${INSTALL_DIR:=/opt/docker/nginx}"
CONTAINER_NAME="nginx_docker"
IMAGE="nginx:stable"
DOCKER_GPG_KEYRING="/etc/apt/keyrings/docker.gpg"

### Fonctions utilitaires ###
info()  { printf "\e[34m[INFO]\e[0m %s\n" "$*"; }
warn()  { printf "\e[33m[WARN]\e[0m %s\n" "$*"; }
error() { printf "\e[31m[ERROR]\e[0m %s\n" "$*" >&2; }

# Nettoyage "soft" en cas d'erreur (ne supprime pas automatiquement)
on_error() {
  error "Le script a rencontré une erreur. Consultez les messages ci-dessus."
  error "Si un container a été créé, vérifiez son état : docker ps -a | grep ${CONTAINER_NAME} || true"
}
trap on_error ERR

# Vérifier l'exécution en root (nécessaire pour apt et configuration système)
if [ "$(id -u)" -ne 0 ]; then
  error "Ce script doit être exécuté en root. Lancez : sudo ./install_docker_nginx.sh"
  exit 1
fi

### 1) Vérifier si Docker est déjà installé ###
if command -v docker >/dev/null 2>&1; then
  info "Docker est déjà installé. Version : $(docker --version 2>/dev/null || echo 'inconnue')"
  DOCKER_INSTALLED=true
else
  DOCKER_INSTALLED=false
fi

### 2) Installer Docker si nécessaire (idempotent) ###
if [ "$DOCKER_INSTALLED" = false ]; then
  info "Installation des prérequis..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https

  info "Ajout de la clé GPG officielle de Docker..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o "${DOCKER_GPG_KEYRING}"
  chmod 644 "${DOCKER_GPG_KEYRING}"

  info "Ajout du dépôt Docker APT..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=${DOCKER_GPG_KEYRING}] https://download.docker.com/linux/debian \
    $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

  info "Mise à jour des paquets et installation de Docker Engine..."
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  info "Activation et démarrage du service Docker..."
  systemctl enable --now docker
  info "Docker installé et démarré."
else
  info "Passage de l'installation de Docker (déjà présent)."
  # S'assurer que le service Docker est activé et démarré
  systemctl enable --now docker || warn "Impossible d'activer/ démarrer le service docker automatiquement."
fi

### 3) Préparer les dossiers de configuration & contenu (idempotent) ###
info "Création des dossiers hôtes pour la configuration Nginx..."
mkdir -p "${INSTALL_DIR}/html" "${INSTALL_DIR}/conf.d" "${INSTALL_DIR}/logs"
chown -R root:root "${INSTALL_DIR}"
chmod -R 755 "${INSTALL_DIR}"

# Helper : écrire fichier uniquement si contenu différent (sauvegarde si diverge)
write_if_different() {
  local dest="$1"
  local tmp
  tmp="$(mktemp)"
  cat > "${tmp}"
  if [ -f "${dest}" ]; then
    if cmp -s "${tmp}" "${dest}"; then
      rm -f "${tmp}"
      return 0
    else
      cp -a "${dest}" "${dest}.$(date +%Y%m%d%H%M%S).bak"
      info "Le fichier ${dest} a été sauvegardé avant modification."
    fi
  fi
  mv "${tmp}" "${dest}"
  chmod 644 "${dest}"
  return 0
}

# 3.1 index.html (page de test) -> ne remplace pas si l'utilisateur a déjà personnalisé
if [ ! -f "${INSTALL_DIR}/html/index.html" ]; then
  info "Création d'une page de test (${INSTALL_DIR}/html/index.html)..."
  cat > "${INSTALL_DIR}/html/index.html" <<'HTML'
<!doctype html>
<html lang="fr">
<head><meta charset="utf-8"><title>Nginx Docker - Test</title></head>
<body>
  <h1>Nginx dans Docker — page de test</h1>
  <p>Conteneur: nginx_docker</p>
  <p>Date : <!-- date injected --> </p>
</body>
</html>
HTML
  # Injecter la date actuelle
  sed -i "s/<!-- date injected -->/$(date -u +"%Y-%m-%d %H:%M UTC")/" "${INSTALL_DIR}/html/index.html"
else
  info "index.html existe déjà, ne pas l'écraser (idempotence)."
fi

# 3.2 configuration Nginx par défaut (server block minimal)
NGINX_CONF_PATH="${INSTALL_DIR}/conf.d/default.conf"
info "Préparation de la configuration Nginx dans ${NGINX_CONF_PATH}..."
if [ "${USE_REVERSE_PROXY}" = "true" ]; then
  # Reverse proxy configuration (exemple)
  cat > /tmp/nginx_default.conf <<EOF
server {
    listen 80;
    server_name _;
    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log;

    location / {
        proxy_pass ${PROXY_UPSTREAM};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
EOF
else
  # Simple static server (page de test)
  cat > /tmp/nginx_default.conf <<'EOF'
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
fi

# Écrire le fichier si différent
write_if_different "${NGINX_CONF_PATH}" < /tmp/nginx_default.conf
rm -f /tmp/nginx_default.conf

### 4) Déterminer le port hôte libre (éviter conflit avec un service local) ###
HOST_PORT=80
port_in_use() {
  local port="$1"
  # essayer ss, puis lsof, puis netstat
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :${port} )" >/dev/null 2>&1 && return 0 || return 1
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP -sTCP:LISTEN -P | grep -q ":${port} " && return 0 || return 1
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tln | grep -q ":${port} " && return 0 || return 1
  else
    # Pas d'outil fiable : on suppose port libre
    return 1
  fi
}

if port_in_use 80; then
  warn "Le port 80 est déjà utilisé sur l'hôte. Le conteneur Nginx sera publié sur le port 8080 à la place."
  HOST_PORT=8080
  # trouver un port libre à partir de 8080
  for p in $(seq 8080 8099); do
    if ! port_in_use "${p}"; then
      HOST_PORT="${p}"
      break
    fi
  done
  info "Port choisi : ${HOST_PORT}"
fi

### 5) Pull de l'image et création / redéploiement du conteneur (idempotent) ###
info "Récupération de l'image Docker (${IMAGE})..."
docker pull "${IMAGE}"

# Si un container du même nom existe -> on le supprime proprement pour recréer identique (volumes host persistent)
if docker ps -a --format '{{.Names}}' | grep -q -w "${CONTAINER_NAME}"; then
  info "Un conteneur nommé ${CONTAINER_NAME} existe déjà. Arrêt et suppression pour redéploiement."
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || warn "Impossible de supprimer ${CONTAINER_NAME} automatiquement."
fi

info "Démarrage du conteneur Nginx Docker..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p "${HOST_PORT}":80 \
  -v "${INSTALL_DIR}/html":/usr/share/nginx/html:ro \
  -v "${INSTALL_DIR}/conf.d":/etc/nginx/conf.d:ro \
  -v "${INSTALL_DIR}/logs":/var/log/nginx \
  "${IMAGE}" >/dev/null

info "Conteneur lancé."

# donner le temps au container de démarrer un peu puis afficher l'état
sleep 1
if docker ps --format '{{.Names}}' | grep -q -w "${CONTAINER_NAME}"; then
  info "Le conteneur ${CONTAINER_NAME} est en cours d'exécution."
else
  warn "Le conteneur ${CONTAINER_NAME} ne semble pas en cours d'exécution. Vérifiez : docker ps -a"
fi

### 6) Ajout de l'utilisateur sudo (optionnel) au groupe docker pour usage sans sudo ###
if [ -n "${SUDO_USER:-}" ] && id -u "${SUDO_USER}" >/dev/null 2>&1; then
  if getent group docker >/dev/null 2>&1; then
    if id -nG "${SUDO_USER}" | grep -qw docker; then
      info "L'utilisateur ${SUDO_USER} appartient déjà au groupe docker."
    else
      usermod -aG docker "${SUDO_USER}" && info "Ajout de ${SUDO_USER} au groupe docker (déconnexion/reconnexion nécessaire)."
    fi
  fi
fi

### 7) Résumé et actions post-install ###
info "Résumé :"
info "  - Nginx (Docker) image : ${IMAGE}"
info "  - Nom du conteneur      : ${CONTAINER_NAME}"
info "  - Dossier hôte config   : ${INSTALL_DIR}"
info "  - Port exposé (hôte)    : ${HOST_PORT}"
info ""
info "Accédez à la page de test : http://<IP-de-la-machine>:${HOST_PORT}/"
info "Vérifier les logs du conteneur : docker logs -f ${CONTAINER_NAME}"
info "Arrêter/redémarrer : docker stop ${CONTAINER_NAME} && docker start ${CONTAINER_NAME}"
info "Supprimer le conteneur : docker rm -f ${CONTAINER_NAME} (les fichiers sous ${INSTALL_DIR} restent)"
info ""
info "Si vous avez ajouté votre utilisateur au groupe docker, reconnectez-vous pour appliquer le changement."

### Section nettoyage / suppression (manuel) ###
cat <<'EOFF'

=== Nettoyage manuel (instructions) ===

Si vous voulez tout supprimer (container + dossiers créés) :
  sudo docker rm -f nginx_docker
  sudo rm -rf /opt/docker/nginx
  sudo rm /etc/apt/sources.list.d/docker.list
  sudo rm -f /etc/apt/keyrings/docker.gpg
  sudo apt-get remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo apt-get autoremove -y

Note: Le script n'effectue pas la suppression automatiquement pour éviter toute perte de données.

EOFF

exit 0
