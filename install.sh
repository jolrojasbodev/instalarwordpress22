#!/bin/bash

# --- VARIABLES ---
# Ajusta estas variables si cambian en tu entorno.
DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASS="wordpress" # ¡IMPORTANTE! Para producción, usa una contraseña muy segura.
DB_SERVER="localhost" # Asume que MySQL está en el mismo servidor

WP_DIR="/srv/www/wordpress"
WP_ZIP_PATH="/tmp/wordpress.zip" # Ubicación temporal para la descarga del ZIP
WP_EXTRACT_TEMP_DIR="/tmp/wordpress_extracted" # Directorio temporal para la descompresión

TITULO_SITIO="Actividad_3"
ADMIN_LOGIN="admin" # Considera un nombre de usuario más complejo.
ADMIN_CLAVE="admin" # ¡CRÍTICO! Para producción, usa una contraseña fuerte.
ADMIN_CORREO="jolrojasbo@gmail.com"
POST_TITULO="Actividad_3"
CONTENIDO_POST='<p style="text-align: justify;">Actividad 3 - Despliegue Automatizado de WordPress: Este trabajo presenta un script Bash diseñado para la **instalación y configuración automatizada de WordPress**. El script se encarga de aprovisionar un entorno LAMP/LEMP completo, incluyendo **Nginx, PHP-FPM y MySQL**, en un sistema Ubuntu. Además, utiliza WP-CLI para la creación inicial del sitio y su contenido, así como la configuración de reglas de seguridad básicas en Nginx. El objetivo principal de esta actividad es **comparar la eficiencia y el comportamiento de este mismo despliegue en dos entornos distintos: una máquina virtual en VirtualBox y una instancia en AWS EC2**, analizando las diferencias y consideraciones específicas de cada plataforma.</p>'

LINK_WP_ZIP="https://wordpress.org/latest.zip"
LINK_WP_SHA1="https://wordpress.org/latest.zip.sha1"
LINK_WP_CLI_PHAR="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
RUTA_WP_CLI_BIN="/usr/local/bin/wp"

# Permisos estándar (directorios 0755, archivos 0644)
DIR_PERMISSIONS="0755"
FILE_PERMISSIONS="0644"
WP_CONFIG_PERMISSIONS="0640" # Permisos más restrictivos para wp-config.php

# Se guarda el log en la misma ubicación del script con el nombre especificado
LOG_FILE="$(dirname "$0")/tiempodeinstalacion.log"

# --- FUNCIONES AUXILIARES ---

# Función para manejar errores de forma concisa
handle_error() {
    echo "ERROR: $1. Saliendo..." >&2 # Redirige el error a stderr
    exit 1
}

# Reinicia el servicio Nginx
restart_nginx() {
    echo "Reiniciando Nginx..."
    sudo systemctl restart nginx || handle_error "Fallo al reiniciar Nginx"
}

# Reinicia el servicio PHP-FPM (php8.1-fpm para Ubuntu 22.04)
restart_phpfpm() {
    echo "Reiniciando PHP-FPM (php8.1-fpm)..."
    sudo systemctl restart php8.1-fpm || handle_error "Fallo al reiniciar PHP-FPM (php8.1-fpm)"
}

# Reinicia el servicio MySQL
restart_mysql() {
    echo "Reiniciando MySQL..."
    sudo systemctl restart mysql || handle_error "Fallo al reiniciar MySQL"
}

# Espera a que se liberen los bloqueos de APT
wait_for_apt_lock() {
    local max_attempts=30 # Esperar hasta 30 segundos
    local attempt=0
    echo "Esperando por la liberación de bloqueos de APT (máx. ${max_attempts}s)..."
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

START_TIME=$(date +%s) # Registro de tiempo de inicio
echo "--- Iniciando instalación y configuración de WordPress en Ubuntu 22.04 ---"

# Verificar que el script se ejecute como root
if [ "$EUID" -ne 0 ]; then
    handle_error "Por favor, ejecuta este script con sudo o como usuario root."
fi

# Operaciones APT
wait_for_apt_lock
echo "Actualizando lista de paquetes (apt update)..."
sudo apt update || handle_error "Fallo al actualizar la lista de paquetes"

wait_for_apt_lock
echo "Instalando paquetes necesarios: Nginx, PHP-FPM (8.1), MySQL, y otros..."
sudo apt install -y nginx php8.1-fpm ghostscript php8.1 php8.1-mysql php8.1-cli php8.1-curl php8.1-gd php8.1-mbstring php8.1-xml php8.1-xmlrpc php8.1-soap php8.1-bcmath php8.1-imagick php8.1-intl php8.1-zip mysql-server unzip lsof || handle_error "Fallo al instalar los paquetes"

# Detección de IP
SERVER_IP=$(hostname -I | awk '{print $1}') # Esto obtiene la IP privada
PUBLIC_IP=""

echo "Intentando detectar la IP pública de AWS..."
if command -v curl &> /dev/null; then
    PUBLIC_IP_CANDIDATE=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    if [[ "$PUBLIC_IP_CANDIDATE" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        PUBLIC_IP="$PUBLIC_IP_CANDIDATE"
    fi
else
    echo "Advertencia: 'curl' no está disponible para detectar la IP pública de AWS metadata."
fi

# Define SITIO_URL: Prioriza la IP pública si está disponible, de lo contrario usa la IP privada.
if [ -n "$PUBLIC_IP" ]; then
    SITIO_URL="http://${PUBLIC_IP}"
    echo "¡ATENCIÓN! Se detectó una IP pública de AWS: ${PUBLIC_IP}. El sitio se configurará con esta IP."
else
    SITIO_URL="http://${SERVER_IP}"
    echo "ADVERTENCIA: No se pudo obtener una IP pública de AWS. El sitio se configurará con la IP privada: ${SERVER_IP}."
    echo "Si estás en AWS y esperas acceso público, asegúrate de que la instancia tenga una IP pública y que los grupos de seguridad (Security Groups) lo permitan."
fi
echo "IP del servidor detectada (usada para la URL del sitio): ${SITIO_URL}"

# Configuración de servicios
echo "Asegurando que MySQL esté iniciado y habilitado..."
sudo systemctl start mysql && sudo systemctl enable mysql || handle_error "Fallo al gestionar MySQL"

echo "Asegurando que PHP-FPM (php8.1-fpm) esté iniciado y habilitado..."
sudo systemctl start php8.1-fpm && sudo systemctl enable php8.1-fpm || handle_error "Fallo al gestionar PHP-FPM"

# Preparación de directorios
echo "Creando y configurando permisos para /srv/www y $WP_DIR..."
sudo mkdir -p /srv/www "$WP_DIR" || handle_error "Fallo al crear directorios principales"
sudo chown -R www-data:www-data /srv/www "$WP_DIR" || handle_error "Fallo al establecer propietario de directorios"
sudo chmod "$DIR_PERMISSIONS" /srv/www "$WP_DIR" || handle_error "Fallo al establecer permisos de directorios"

# Descarga y verificación de WordPress
echo "Descargando checksum de WordPress..."
WP_CHECKSUM=$(curl -s "$LINK_WP_SHA1" | awk '{print $1}') || handle_error "Fallo al obtener el checksum de WordPress."
echo "Checksum obtenido: $WP_CHECKSUM"

echo "Descargando WordPress a $WP_ZIP_PATH..."
sudo curl -sSL "$LINK_WP_ZIP" -o "$WP_ZIP_PATH" || handle_error "Fallo al descargar WordPress"

echo "Verificando checksum de WordPress..."
DOWNLOADED_SHA1=$(sha1sum "$WP_ZIP_PATH" | awk '{print $1}')
if [ "$DOWNLOADED_SHA1" != "$WP_CHECKSUM" ]; then
    handle_error "El checksum de WordPress no coincide. Archivo corrupto o alterado."
fi
echo "Checksum de WordPress verificado correctamente."

# Descompresión y movimiento de WordPress
echo "Limpiando y preparando el directorio $WP_DIR para la nueva instalación..."
sudo rm -rf "$WP_DIR" || handle_error "Fallo al limpiar el directorio $WP_DIR"
sudo mkdir -p "$WP_DIR" || handle_error "Fallo al recrear el directorio $WP_DIR"

echo "Creando directorio temporal de extracción $WP_EXTRACT_TEMP_DIR..."
sudo mkdir -p "$WP_EXTRACT_TEMP_DIR" || handle_error "Fallo al crear directorio temporal"

echo "Descomprimiendo WordPress en $WP_EXTRACT_TEMP_DIR..."
sudo unzip -q "$WP_ZIP_PATH" -d "$WP_EXTRACT_TEMP_DIR" || handle_error "Fallo al descomprimir WordPress"

echo "Moviendo archivos de WordPress al directorio final ($WP_DIR)..."
sudo mv "$WP_EXTRACT_TEMP_DIR"/wordpress/* "$WP_DIR"/ || handle_error "Fallo al mover los archivos de WordPress"

echo "Eliminando archivos y directorios temporales..."
sudo rm -f "$WP_ZIP_PATH" || handle_error "Fallo al eliminar ZIP"
sudo rm -rf "$WP_EXTRACT_TEMP_DIR" || handle_error "Fallo al eliminar directorio temporal"

# Asegurar permisos de WordPress finales
echo "Asegurando permisos finales para WordPress en $WP_DIR..."
sudo chown -R www-data:www-data "$WP_DIR" || handle_error "Fallo al cambiar propietario de $WP_DIR"
sudo find "$WP_DIR" -type d -exec chmod "$DIR_PERMISSIONS" {} \; || handle_error "Fallo al cambiar permisos de directorios"
sudo find "$WP_DIR" -type f -exec chmod "$FILE_PERMISSIONS" {} \; || handle_error "Fallo al cambiar permisos de archivos"

# Descargar e instalar WP-CLI
echo "Descargando e instalando WP-CLI..."
sudo curl -sSL "$LINK_WP_CLI_PHAR" -o "$RUTA_WP_CLI_BIN" || handle_error "Fallo al descargar WP-CLI"
sudo chmod "$DIR_PERMISSIONS" "$RUTA_WP_CLI_BIN" || handle_error "Fallo al dar permisos a WP-CLI"

# Crear Base de Datos y Usuario WordPress
echo "Creando base de datos y usuario de WordPress..."
# ADVERTENCIA: La contraseña de MySQL 'root' se asume igual a DB_PASS.
# Para producción, es CRÍTICO que la contraseña de 'root' sea única y muy segura.
MYSQL_ROOT_PASS="$DB_PASS"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_SERVER' IDENTIFIED BY '$DB_PASS';" || handle_error "Fallo al crear usuario MySQL"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;" || handle_error "Fallo al crear base de datos MySQL"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'$DB_SERVER';" || handle_error "Fallo al conceder privilegios MySQL"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;" || handle_error "Fallo al recargar privilegios MySQL"
restart_mysql # Reinicia MySQL después de cambios en la base de datos.

# Limpieza de Apache (si existe)
echo "Deteniendo y purgando Apache (si está activo)..."
sudo systemctl stop apache2 2>/dev/null
sudo systemctl disable apache2 2>/dev/null

wait_for_apt_lock # Espera de nuevo antes de purgar paquetes
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
        if sudo lsof -t -i :80 &> /dev/null; then
            echo "Advertencia: Algunos procesos aún usan el puerto 80. Esto podría causar problemas."
        fi
    else
        echo "No se encontraron procesos usando el puerto 80."
    fi
else
    echo "Advertencia: 'lsof' no está instalado. No se puede verificar si el puerto 80 está en uso."
fi

# Configuración de Nginx
echo "Eliminando sitio Nginx por defecto (si existe)..."
if [ -f /etc/nginx/sites-enabled/default ]; then
    sudo rm /etc/nginx/sites-enabled/default || handle_error "Fallo al eliminar el sitio Nginx por defecto"
    restart_nginx
fi

echo "Copiando y adaptando configuración de Nginx..."
# Reemplaza el marcador de posición en nginx.conf con la SITIO_URL (pública o privada)
sed "s|{{SERVER_IP_PLACEHOLDER}}|$SITIO_URL|g" ./data/nginx.conf | sudo tee /etc/nginx/sites-available/wordpress.conf > /dev/null || handle_error "Fallo al copiar y adecuar nginx.conf"

sudo chmod "$FILE_PERMISSIONS" /etc/nginx/sites-available/wordpress.conf || handle_error "Fallo al ajustar permisos de nginx.conf"
sudo nginx -t || handle_error "Error de sintaxis en la configuración de Nginx."

echo "Creando link simbólico para Nginx de WordPress..."
sudo ln -sf /etc/nginx/sites-available/wordpress.conf /etc/nginx/sites-enabled/wordpress.conf || handle_error "Fallo al crear link simbólico de Nginx"
restart_nginx # Reinicia Nginx con la nueva configuración activa

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
else
    echo "WordPress core ya instalado. Saltando este paso."
fi

# Post-instalación de WordPress (plugins, temas, posts)
echo "Actualizando plugins de WordPress..."
sudo -u www-data "$RUTA_WP_CLI_BIN" plugin update --all --path="$WP_DIR" || handle_error "Fallo al actualizar plugins"

echo "Actualizando temas de WordPress..."
sudo -u www-data "$RUTA_WP_CLI_BIN" theme update --all --path="$WP_DIR" || handle_error "Fallo al actualizar temas"

echo "Eliminando post por defecto (ID 1)..."
sudo -u www-data "$RUTA_WP_CLI_BIN" post delete 1 --force --path="$WP_DIR" || echo "Advertencia: Fallo al eliminar post 1 (podría no existir)."

echo "Eliminando página de ejemplo (ID 2)..."
sudo -u www-data "$RUTA_WP_CLI_BIN" post delete 2 --force --path="$WP_DIR" || echo "Advertencia: Fallo al eliminar página 2 (podría no existir)."

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
echo "Tiempo de ejecución guardado en: $LOG_FILE"
