#!/bin/bash

# --- VARIABLES ---
# Ajusta estas variables si cambian en tu entorno.
DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASS="wordpress"
DB_SERVER="localhost" # Esto asume que MySQL está en el mismo servidor

WP_DIR="/srv/www/wordpress"

# Detecta la primera dirección IP del servidor para una URL dinámica.
SERVER_IP=$(hostname -I | awk '{print $1}')
SITIO_URL="http://${SERVER_IP}" # Construye la URL con la IP detectada

TITULO_SITIO="Actividad_3"
ADMIN_LOGIN="admin"
ADMIN_CLAVE="admin"
ADMIN_CORREO="jolrojasbo@gmail.com"
POST_TITULO="Actividad_3"
CONTENIDO_POST='<p style="text-align: justify;">Actividad 3 - Herramientas de Automatización de Despliegues - Jose Rojas: Este trabajo describe el desarrollo de un entorno de despliegue automatizado para la plataforma WordPress, basado en la operación conjunta de Vagrant, Ansible y WordPress. Vagrant aprovisiona una máquina virtual de VirtualBox, donde Ansible orquesta la instalación y configuración de Nginx, PHP-FPM y MySQL para WordPress. Finalmente, se utiliza WP-CLI para la creación automatizada del contenido inicial del sitio, ademas se incluyen reglas de seguridad en Nginx, para prevenir el ingreso a wp-admin.</p>'

LINK_WP_ZIP="https://wordpress.org/latest.zip"
LINK_WP_SHA1="https://wordpress.org/latest.zip.sha1"
LINK_WP_CLI_PHAR="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
RUTA_WP_CLI_BIN="/usr/local/bin/wp"

# Permisos
DIR_PERMISSIONS="0755"
FILE_PERMISSIONS="0644"
WP_CONFIG_PERMISSIONS="0640"

# --- FUNCIONES AUXILIARES ---

# Función para manejar errores
handle_error() {
    echo "Error: $1. Saliendo..."
    exit 1
}

# Función para reiniciar servicios (simulando los handlers de Ansible)
restart_nginx() {
    echo "Reiniciando Nginx..."
    sudo systemctl restart nginx || handle_error "Fallo al reiniciar Nginx"
}

# CAMBIO CLAVE: Nombre del servicio PHP-FPM para Ubuntu 22.04
restart_phpfpm() {
    echo "Reiniciando PHP-FPM (php8.1-fpm)..."
    sudo systemctl restart php8.1-fpm || handle_error "Fallo al reiniciar PHP-FPM (php8.1-fpm)"
}

restart_mysql() {
    echo "Reiniciando MySQL..."
    sudo systemctl restart mysql || handle_error "Fallo al reiniciar MySQL"
}

# --- INICIO DEL SCRIPT ---

echo "--- Iniciando el proceso de instalación y configuración de WordPress para Ubuntu 22.04 ---"

# Asegurarse de que el script se ejecute como root
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecuta este script con sudo o como usuario root."
    exit 1
fi

echo "Detectando IP del servidor: ${SERVER_IP}"
echo "La URL del sitio WordPress será: ${SITIO_URL}"

# Actualizar lista de paquetes
echo "Actualizando lista de paquetes..."
sudo apt update || handle_error "Fallo al actualizar los paquetes"

# Instalar paquetes
# CAMBIO CLAVE: Especificar php8.1-fpm y otros módulos PHP para 8.1
echo "Instalando paquetes necesarios: Nginx, PHP-FPM (8.1), MySQL, y otros..."
sudo apt install -y nginx \
php8.1-fpm \
ghostscript \
php8.1 \
php8.1-mysql \
php8.1-cli \
php8.1-curl \
php8.1-gd \
php8.1-mbstring \
php8.1-xml \
php8.1-xmlrpc \
php8.1-soap \
php8.1-bcmath \
php8.1-imagick \
php8.1-intl \
php8.1-zip \
mysql-server \
unzip \
lsof || handle_error "Fallo al instalar los paquetes"

# Asegurar que MySQL esté iniciado y habilitado
echo "Asegurando que MySQL esté iniciado y habilitado..."
sudo systemctl start mysql || handle_error "Fallo al iniciar MySQL"
sudo systemctl enable mysql || handle_error "Fallo al habilitar MySQL"

# Asegurar que PHP-FPM esté iniciado y habilitado
# CAMBIO CLAVE: Servicio php8.1-fpm
echo "Asegurando que PHP-FPM (php8.1-fpm) esté iniciado y habilitado..."
sudo systemctl start php8.1-fpm || handle_error "Fallo al iniciar PHP-FPM (php8.1-fpm)"
sudo systemctl enable php8.1-fpm || handle_error "Fallo al habilitar PHP-FPM (php8.1-fpm)"

# Crear directorio www
echo "Creando directorio $WP_DIR..."
sudo mkdir -p /srv/www || handle_error "Fallo al crear /srv/www"
sudo chown www-data:www-data /srv/www || handle_error "Fallo al cambiar propietario de /srv/www"
sudo chmod "$DIR_PERMISSIONS" /srv/www || handle_error "Fallo al cambiar permisos de /srv/www"

# Descargar checksum de WordPress
echo "Descargando checksum de WordPress..."
WP_CHECKSUM=$(curl -s "$LINK_WP_SHA1" | awk '{print $1}')
if [ -z "$WP_CHECKSUM" ]; then
    handle_error "Fallo al obtener el checksum de WordPress"
fi
echo "Checksum obtenido: $WP_CHECKSUM"

# Descargar WordPress
echo "Descargando WordPress..."
sudo curl -sSL "$LINK_WP_ZIP" -o /srv/www/wordpress.zip || handle_error "Fallo al descargar WordPress"

# Verificar checksum de WordPress
echo "Verificando checksum de WordPress..."
DOWNLOADED_SHA1=$(sha1sum /srv/www/wordpress.zip | awk '{print $1}')
if [ "$DOWNLOADED_SHA1" != "$WP_CHECKSUM" ]; then
    handle_error "El checksum de WordPress no coincide. Archivo corrupto o alterado."
fi
echo "Checksum de WordPress verificado correctamente."

# Descomprimir WordPress
echo "Descomprimiendo WordPress en /srv/www/..."
sudo unzip -q /srv/www/wordpress.zip -d /srv/www/ || handle_error "Fallo al descomprimir WordPress"
sudo mv /srv/www/wordpress/* "$WP_DIR"/ || handle_error "Fallo al mover archivos de WordPress"
sudo rmdir /srv/www/wordpress || handle_error "Fallo al eliminar directorio temporal de WordPress"

# Eliminar archivo zip de WordPress
echo "Eliminando archivo zip de WordPress..."
sudo rm -f /srv/www/wordpress.zip || handle_error "Fallo al eliminar wordpress.zip"

# Asegurar permisos de WordPress
echo "Asegurando permisos para WordPress en $WP_DIR..."
sudo chown -R www-data:www-data "$WP_DIR" || handle_error "Fallo al cambiar propietario de $WP_DIR"
sudo find "$WP_DIR" -type d -exec chmod "$DIR_PERMISSIONS" {} \; || handle_error "Fallo al cambiar permisos de directorios en $WP_DIR"
sudo find "$WP_DIR" -type f -exec chmod "$FILE_PERMISSIONS" {} \; || handle_error "Fallo al cambiar permisos de archivos en $WP_DIR"

# Descargar e instalar WP-CLI
echo "Descargando e instalando WP-CLI..."
sudo curl -sSL "$LINK_WP_CLI_PHAR" -o "$RUTA_WP_CLI_BIN" || handle_error "Fallo al descargar WP-CLI"
sudo chmod "$DIR_PERMISSIONS" "$RUTA_WP_CLI_BIN" || handle_error "Fallo al dar permisos a WP-CLI"

# Crear Base de Datos y Usuario WordPress
echo "Creando base de datos y usuario de WordPress..."
MYSQL_ROOT_PASS="$DB_PASS" # Usando la misma contraseña que db_pass para root, según tu playbook.
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "CREATE USER IF NOT EXISTS '$DB_USER'@'$DB_SERVER' IDENTIFIED BY '$DB_PASS';" || handle_error "Fallo al crear usuario de MySQL"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;" || handle_error "Fallo al crear base de datos MySQL"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "GRANT ALL ON $DB_NAME.* TO '$DB_USER'@'$DB_SERVER';" || handle_error "Fallo al conceder privilegios en MySQL"
sudo mysql -uroot -p"$MYSQL_ROOT_PASS" -e "FLUSH PRIVILEGES;" || handle_error "Fallo al recargar privilegios en MySQL"
restart_mysql # Reinicia MySQL después de cambios en la base de datos.

# Detener y deshabilitar el servicio Apache (si está activo)
echo "Deteniendo y deshabilitando Apache (si está activo)..."
sudo systemctl stop apache2 2>/dev/null
sudo systemctl disable apache2 2>/dev/null

# Purgar paquetes de Apache y PHP-Apache si están instalados
echo "Purgando paquetes de Apache y PHP-Apache (si están instalados)..."
sudo apt purge -y apache2 libapache2-mod-php 2>/dev/null
sudo apt autoremove -y --purge 2>/dev/null

# Asegurar que el puerto 80 esté libre
echo "Asegurando que el puerto 80 esté libre..."
if command -v lsof &> /dev/null; then
    PIDS=$(sudo lsof -t -i :80 2>/dev/null)
    if [ -n "$PIDS" ]; then
        echo "Procesos usando el puerto 80 encontrados: $PIDS. Intentando terminarlos..."
        sudo kill -9 $PIDS 2>/dev/null
        sleep 2 # Dar tiempo para que los procesos terminen
        if sudo lsof -t -i :80 &> /dev/null; then
            echo "Advertencia: Algunos procesos aún usan el puerto 80. Esto podría causar problemas."
        else
            echo "Puerto 80 liberado."
        fi
    else
        echo "No se encontraron procesos usando el puerto 80."
    fi
else
    echo "lsof no está instalado. No se puede verificar si el puerto 80 está en uso."
fi

# Eliminar sitio Nginx por defecto (si existe)
echo "Eliminando sitio Nginx por defecto..."
if [ -f /etc/nginx/sites-enabled/default ]; then
    sudo rm /etc/nginx/sites-enabled/default || handle_error "Fallo al eliminar el sitio Nginx por defecto"
    restart_nginx
fi

# Copiar archivo wordpress.conf y reemplazar la IP dinámica
echo "Copiando archivo nginx.conf al destino y reemplazando IP dinámica..."
sed "s|{{SERVER_IP_PLACEHOLDER}}|$SERVER_IP|g" ./data/nginx.conf | sudo tee /etc/nginx/sites-available/wordpress.conf > /dev/null || handle_error "Fallo al copiar y adecuar nginx.conf"

sudo chmod "$FILE_PERMISSIONS" /etc/nginx/sites-available/wordpress.conf || handle_error "Fallo al ajustar permisos de nginx.conf"
restart_nginx

# Crear link simbólico para Nginx de WordPress
echo "Creando link simbólico para Nginx de WordPress..."
sudo ln -sf /etc/nginx/sites-available/wordpress.conf /etc/nginx/sites-enabled/wordpress.conf || handle_error "Fallo al crear link simbólico de Nginx"
restart_nginx

# Asegurar que Nginx esté iniciado y habilitado
echo "Asegurando que Nginx esté iniciado y habilitado..."
sudo systemctl start nginx || handle_error "Fallo al iniciar Nginx"
sudo systemctl enable nginx || handle_error "Fallo al habilitar Nginx"

# Copiar archivo wp-config.php (con claves de seguridad integradas)
echo "Copiando archivo wp-config.php al directorio de WordPress..."
sudo cp ./data/wp-config.php "$WP_DIR"/wp-config.php || handle_error "Fallo al copiar wp-config.php"
sudo chown www-data:www-data "$WP_DIR"/wp-config.php || handle_error "Fallo al cambiar propietario de wp-config.php"
sudo chmod "$WP_CONFIG_PERMISSIONS" "$WP_DIR"/wp-config.php || handle_error "Fallo al ajustar permisos de wp-config.php"

# Comprobar si WordPress ya está instalado con WP-CLI
echo "Comprobando si WordPress ya está instalado..."
WP_INSTALLED_CHECK=$(sudo -u www-data "$RUTA_WP_CLI_BIN" core is-installed --path="$WP_DIR" --allow-root 2>&1)
if echo "$WP_INSTALLED_CHECK" | grep -q "Success: WordPress is installed."; then
    echo "WordPress ya está instalado. Saltando la instalación core."
    WP_IS_INSTALLED=true
else
    echo "WordPress no está instalado. Procediendo con la instalación core."
    WP_IS_INSTALLED=false
fi

# Instalar WordPress core si no está instalado
if [ "$WP_IS_INSTALLED" = false ]; then
    echo "Instalando WordPress core..."
    sudo -u www-data "$RUTA_WP_CLI_BIN" core install \
        --path="$WP_DIR" \
        --url="$SITIO_URL" \
        --title="$TITULO_SITIO" \
        --admin_user="$ADMIN_LOGIN" \
        --admin_password="$ADMIN_CLAVE" \
        --admin_email="$ADMIN_CORREO" \
        --skip-email --allow-root || handle_error "Fallo al instalar WordPress core"
else
    echo "WordPress core ya instalado. Saltando este paso."
fi

# Actualizar plugins de WordPress
echo "Actualizando plugins de WordPress..."
sudo -u www-data "$RUTA_WP_CLI_BIN" plugin update --all \
    --path="$WP_DIR" \
    --allow-root || handle_error "Fallo al actualizar plugins de WordPress"

# Actualizar temas de WordPress
echo "Actualizando temas de WordPress..."
sudo -u www-data "$RUTA_WP_CLI_BIN" theme update --all \
    --path="$WP_DIR" \
    --allow-root || handle_error "Fallo al actualizar temas de WordPress"

# Eliminar post por defecto de WordPress (ID 1)
echo "Eliminando post por defecto de WordPress (ID 1)..."
sudo -u www-data "$RUTA_WP_CLI_BIN" post delete 1 --force \
    --path="$WP_DIR" \
    --allow-root || handle_error "Fallo al eliminar post por defecto ID 1"

# Eliminar página de ejemplo de WordPress (ID 2)
echo "Eliminando página de ejemplo de WordPress (ID 2)..."
sudo -u www-data "$RUTA_WP_CLI_BIN" post delete 2 --force \
    --path="$WP_DIR" \
    --allow-root || handle_error "Fallo al eliminar página de ejemplo ID 2"

# Crear post personalizado
echo "Creando post personalizado en WordPress..."
sudo -u www-data "$RUTA_WP_CLI_BIN" post create \
    --post_status=publish \
    --post_title="$POST_TITULO" \
    --post_content="$CONTENIDO_POST" \
    --path="$WP_DIR" \
    --allow-root || handle_error "Fallo al crear post personalizado"

echo "--- Instalación y configuración de WordPress completada con éxito ---"
echo "Ahora puedes acceder a tu sitio WordPress en: ${SITIO_URL}"
echo "Usuario administrador: ${ADMIN_LOGIN}"
echo "Contraseña administrador: ${ADMIN_CLAVE}"
