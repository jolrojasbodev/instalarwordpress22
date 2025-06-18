#!/bin/bash

# --- VARIABLES ---
DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASS="wordpress"
DB_SERVER="localhost"

WP_DIR="/srv/www/wordpress"
WP_ZIP_PATH="/tmp/wordpress.zip"
WP_EXTRACT_TEMP_DIR="/tmp/wordpress_extracted"

TITULO_SITIO="Actividad_3"
ADMIN_LOGIN="admin"
ADMIN_CLAVE="admin"
ADMIN_CORREO="jolrojasbo@gmail.com"
POST_TITULO="Actividad_3"
# --- CAMBIO EN EL CONTENIDO DEL POST: Usando etiquetas HTML <strong> para negritas ---
CONTENIDO_POST='<p style="text-align: justify;"><strong>Actividad 3 - Cloud Computing DevOps y DevOps Culture - Despliegue Automatizado de WordPress - Eric Garcia, Jose Rojas</strong> : Este trabajo presenta un script Bash diseñado para la <strong>instalación y configuración automatizada de WordPress</strong>. El script se encarga de aprovisionar un entorno LAMP completo, incluyendo <strong>Nginx, PHP-FPM y MySQL</strong>, en un sistema Ubuntu. Además, utiliza WP-CLI para la creación inicial del sitio y su contenido, así como la configuración de reglas de seguridad básicas en Nginx. El objetivo principal de esta actividad es <strong>comparar la eficiencia y el comportamiento de este mismo despliegue en dos entornos distintos: una máquina virtual en VirtualBox y una instancia en AWS EC2</strong>, analizando las diferencias y consideraciones específicas de cada plataforma.</p>'
# --- FIN CAMBIO EN EL CONTENIDO DEL POST ---

LINK_WP_ZIP="https://wordpress.org/latest.zip"
LINK_WP_SHA1="https://wordpress.org/latest.zip.sha1"
LINK_WP_CLI_PHAR="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
RUTA_WP_CLI_BIN="/usr/local/bin/wp"

DIR_PERMISSIONS="0755"
FILE_PERMISSIONS="0644"
WP_CONFIG_PERMISSIONS="0640"

LOG_FILE="$(dirname "$0")/tiempodeinstalacion.log"

# --- FUNCIONES AUXILIARES ---
handle_error() {
    echo "ERROR: $1. Saliendo..." >&2
    exit 1
}

restart_nginx() {
    echo "Reiniciando Nginx..."
    sudo systemctl restart nginx || handle_error "Fallo al reiniciar Nginx"
}

restart_phpfpm() {
    echo "Reiniciando PHP-FPM (php8.1-fpm)..."
    sudo systemctl restart php8.1-fpm || handle_error "Fallo al reiniciar PHP-FPM (php8.1-fpm)"
}

restart_mysql() {
    echo "Reiniciando MySQL..."
    sudo systemctl restart mysql || handle_error "Fallo al reiniciar MySQL"
}

wait_for_apt_lock() {
    local max_attempts=30
    local attempt=0
    echo "Esperando por la liberación de bloqueos de APT..."
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            handle_error "Los bloqueos de APT no se liberaron a tiempo. Otro proceso podría estar bloqueando el gestor de paquetes."
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    echo "Bloqueos de APT liberados."
}

# --- INICIO DEL SCRIPT ---
START_TIME=$(date +%s)
echo "--- Iniciando instalación y configuración de WordPress en Ubuntu 22.04 ---"

if [ "$EUID" -ne 0 ]; then
    handle_error "Por favor, ejecuta este script con sudo o como usuario root."
fi

wait_for_apt_lock
echo "Actualizando lista de paquetes..."
sudo apt update || handle_error "Fallo al actualizar la lista de paquetes"

wait_for_apt_lock
echo "Instalando paquetes necesarios..."
sudo apt install -y nginx php8.1-fpm ghostscript php8.1 php8.1-mysql php8.1-cli php8.1-curl php8.1-gd php8.1-mbstring php8.1-xml php8.1-xmlrpc php8.1-soap php8.1-bcmath php8.1-imagick php8.1-intl php8.1-zip mysql-server unzip lsof || handle_error "Fallo al instalar los paquetes"

# Detección de IP
SERVER_IP=$(hostname -I | awk '{print $1}')
PUBLIC_IP=""

if command -v curl &> /dev/null; then
    PUBLIC_IP_CANDIDATE=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    if [[ "$PUBLIC_IP_CANDIDATE" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        PUBLIC_IP="$PUBLIC_IP_CANDIDATE"
    fi
fi

if [ -n "$PUBLIC_IP" ]; then
    SITIO_URL="http://${PUBLIC_IP}"
    echo "IP pública de AWS detectada: ${PUBLIC_IP}. El sitio se configurará con esta IP."
else
    SITIO_URL="http://${SERVER_IP}"
    echo "Usando IP privada: ${SERVER_IP}. El sitio se configurará con esta IP."
fi
echo "URL del sitio: ${SITIO_URL}"

# Configuración de servicios
echo "Asegurando que MySQL esté iniciado y habilitado..."
sudo systemctl start mysql && sudo systemctl enable mysql || handle_error "Fallo al gestionar MySQL"

echo "Asegurando que PHP-FPM esté iniciado y habilitado..."
sudo systemctl start php8.1-fpm && sudo systemctl enable php8.1-fpm || handle_error "Fallo al gestionar PHP-FPM"

# Preparación de directorios
echo "Creando y configurando permisos para /srv/www y $WP_DIR..."
sudo mkdir -p /srv/www "$WP_DIR" || handle_error "Fallo al crear directorios principales"
sudo chown -R www-data:www-data /srv/www "$WP_DIR" || handle_error "Fallo al establecer propietario de directorios"
sudo chmod "$DIR_PERMISSIONS" /srv/www "$WP_DIR" || handle_error "Fallo al establecer permisos de directorios"

# Descarga y verificación de WordPress
echo "Descargando checksum de WordPress..."
WP_CHECKSUM=$(curl -s "$LINK_WP_SHA1" | awk '{print $1}') || handle_error "Fallo al obtener el checksum de WordPress."

echo "Descargando WordPress..."
sudo curl -sSL "$LINK_WP_ZIP" -o "$WP_ZIP_PATH" || handle_error "Fallo al descargar WordPress"

echo "Verificando checksum de WordPress..."
DOWNLOADED_SHA1=$(sha1sum "$WP_ZIP_PATH" | awk '{print $1}')
if [ "$DOWNLOADED_SHA1" != "$WP_CHECKSUM" ]; then
    handle_error "El checksum de WordPress no coincide."
fi

# Descompresión y movimiento de WordPress
echo "Limpiando y preparando el directorio $WP_DIR..."
sudo rm -rf "$WP_DIR" || handle_error "Fallo al limpiar el directorio $WP_DIR"
sudo mkdir -p "$WP_DIR" || handle_error "Fallo al recrear el directorio $WP_DIR"

echo "Creando directorio temporal de extracción..."
sudo mkdir -p "$WP_EXTRACT_TEMP_DIR" || handle_error "Fallo al crear directorio temporal"

echo "Descomprimiendo WordPress..."
sudo unzip -q "$WP_ZIP_PATH" -d "$WP_EXTRACT_TEMP_DIR" || handle_error "Fallo al descomprimir WordPress"

echo "Moviendo archivos de WordPress al directorio final..."
sudo mv "$WP_EXTRACT_TEMP_DIR"/wordpress/* "$WP_DIR"/ || handle_error "Fallo al mover los archivos de WordPress"

echo "Eliminando archivos y directorios temporales..."
sudo rm -f "$WP_ZIP_PATH" || handle_error "Fallo al eliminar ZIP"
sudo rm -rf "$WP_EXTRACT_TEMP_DIR" || handle_error "Fallo al eliminar directorio temporal"

# Asegurar permisos de WordPress finales
echo "Asegurando permisos finales para WordPress..."
sudo chown -R www-data:www-data "$WP_DIR" || handle_error "Fallo al cambiar propietario de $WP_DIR"
sudo find "$WP_DIR" -type d -exec chmod "$DIR_PERMISSIONS" {} \; || handle_error "Fallo al cambiar permisos de directorios"
sudo find "$WP_DIR" -type f -exec chmod "$FILE_PERMISSIONS" {} \; || handle_error "Fallo al cambiar permisos de archivos"

# Descargar e instalar WP-CLI
echo "Descargando e instalando WP-CLI..."
sudo curl -sSL "$LINK_WP_CLI_PHAR" -o "$RUTA_WP_CLI_BIN" || handle_error "Fallo al descargar WP-CLI"
sudo chmod "$DIR_PERMISSIONS" "$RUTA_WP_CLI_BIN" || handle_error "Fallo al dar permisos a WP-CLI"

# Crear Base de Datos y Usuario WordPress
echo "Creando base de datos y usuario de WordPress..."
MYSQL_ROOT_PASS="$DB_PASS"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_SERVER' IDENTIFIED BY '$DB_PASS';" || handle_error "Fallo al crear usuario MySQL"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;" || handle_error "Fallo al crear base de datos MySQL"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'$DB_SERVER';" || handle_error "Fallo al conceder privilegios MySQL"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;" || handle_error "Fallo al recargar privilegios MySQL"
restart_mysql

# Limpieza de Apache (si existe)
echo "Deteniendo y purgando Apache..."
sudo systemctl stop apache2 2>/dev/null
sudo systemctl disable apache2 2>/dev/null

wait_for_apt_lock
sudo apt purge -y apache2 libapache2-mod-php 2>/dev/null
sudo apt autoremove -y --purge 2>/dev/null

# Asegurar puerto 80 libre
echo "Asegurando que el puerto 80 esté libre..."
if command -v lsof &> /dev/null; then
    PIDS=$(sudo lsof -t -i :80 2>/dev/null)
    if [ -n "$PIDS" ]; then
        echo "Procesos usando el puerto 80: $PIDS. Intentando terminarlos..."
        sudo kill -9 $PIDS 2>/dev/null
        sleep 2
    fi
fi

# Configuración de Nginx
echo "Eliminando sitio Nginx por defecto..."
if [ -f /etc/nginx/sites-enabled/default ]; then
    sudo rm /etc/nginx/sites-enabled/default || handle_error "Fallo al eliminar el sitio Nginx por defecto"
    restart_nginx
fi

echo "Copiando y adaptando configuración de Nginx..."
sed "s|{{SERVER_IP_PLACEHOLDER}}|$SITIO_URL|g" ./data/nginx.conf | sudo tee /etc/nginx/sites-available/wordpress.conf > /dev/null || handle_error "Fallo al copiar y adecuar nginx.conf"

sudo chmod "$FILE_PERMISSIONS" /etc/nginx/sites-available/wordpress.conf || handle_error "Fallo al ajustar permisos de nginx.conf"
sudo nginx -t || handle_error "Error de sintaxis en la configuración de Nginx."

echo "Creando link simbólico para Nginx..."
sudo ln -sf /etc/nginx/sites-available/wordpress.conf /etc/nginx/sites-enabled/wordpress.conf || handle_error "Fallo al crear link simbólico de Nginx"
restart_nginx

echo "Asegurando que Nginx esté iniciado y habilitado..."
sudo systemctl start nginx && sudo systemctl enable nginx || handle_error "Fallo al gestionar Nginx"

# Configuración de WordPress
echo "Copiando wp-config.php al directorio de WordPress..."
sudo cp ./data/wp-config.php "$WP_DIR"/wp-config.php || handle_error "Fallo al copiar wp-config.php"
sudo chown www-data:www-data "$WP_DIR"/wp-config.php || handle_error "Fallo al cambiar propietario de wp-config.php"
sudo chmod "$WP_CONFIG_PERMISSIONS" "$WP_DIR"/wp-config.php || handle_error "Fallo al ajustar permisos de wp-config.php"

echo "Comprobando si WordPress ya está instalado..."
if sudo -u www-data "$RUTA_WP_CLI_BIN" core is-installed --path="$WP_DIR" &>/dev/null; then
    echo "WordPress ya está instalado. Saltando instalación core."
    WP_IS_INSTALLED=true
else
    echo "WordPress no está instalado. Procediendo con la instalación core."
    WP_IS_INSTALLED=false
fi

if [ "$WP_IS_INSTALLED" = false ]; then
    echo "Instalando WordPress core..."
    sudo -u www-data "$RUTA_WP_CLI_BIN" core install \
        --path="$WP_DIR" \
        --url="$SITIO_URL" \
        --title="$TITULO_SITIO" \
        --admin_user="$ADMIN_LOGIN" \
        --admin_password="$ADMIN_CLAVE" \
        --admin_email="$ADMIN_CORREO" \
        --skip-email || handle_error "Fallo al instalar WordPress core"
fi

# Post-instalación de WordPress (plugins, temas, posts)
echo "Actualizando plugins de WordPress..."
sudo -u www-data "$RUTA_WP_CLI_BIN" plugin update --all --path="$WP_DIR" || handle_error "Fallo al actualizar plugins"

echo "Actualizando temas de WordPress..."
sudo -u www-data "$RUTA_WP_CLI_BIN" theme update --all --path="$WP_DIR" || handle_error "Fallo al actualizar temas"

echo "Eliminando post por defecto (ID 1)..."
sudo -u www-data "$RUTA_WP_CLI_BIN" post delete 1 --force --path="$WP_DIR" || true

echo "Eliminando página de ejemplo (ID 2)..."
sudo -u www-data "$RUTA_WP_CLI_BIN" post delete 2 --force --path="$WP_DIR" || true

echo "Creando post personalizado en WordPress..."
sudo -u www-data "$RUTA_WP_CLI_BIN" post create \
    --post_status=publish \
    --post_title="$POST_TITULO" \
    --post_content="$CONTENIDO_POST" \
    --path="$WP_DIR" || handle_error "Fallo al crear post personalizado"

echo "--- Instalación y configuración de WordPress completada con éxito ---"
echo "Ahora puedes acceder a tu sitio WordPress en: ${SITIO_URL}"
echo "Usuario administrador: ${ADMIN_LOGIN}"
echo "Contraseña administrador: ${ADMIN_CLAVE}"

# --- REGISTRO DE TIEMPO ---
END_TIME=$(date +%s)
RUN_TIME=$((END_TIME - START_TIME))
DATE_STAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "Tiempo de ejecución total: ${RUN_TIME} segundos."
echo "${DATE_STAMP} - URL: ${SITIO_URL} - Tiempo de ejecución: ${RUN_TIME} segundos." | sudo tee -a "$LOG_FILE" > /dev/null
