#!/bin/bash

# Función para generar una contraseña de 16 caracteres alfanuméricos
generate_password() {
    # Genera una contraseña alfanumérica segura de 16 caracteres utilizando openssl y la almacena en una variable local
    local password=$(openssl rand -base64 12)
    # Devuelve la contraseña generada
    echo "$password"
}

# Función para verificar que todos los usuarios tengan una contraseña configurada
check_user_passwords() {
    echo "Verificando contraseñas de usuarios..."
    # Leer cada línea del archivo /etc/passwd, que contiene información de los usuarios
    while IFS=: read -r username _; do
        # Excluir los usuarios root y nobody de la verificación
        if [[ $username != "root" && $username != "nobody" ]]; then
            # Verifica el estado de la contraseña del usuario (NP indica que no tiene contraseña)
            password_status=$(sudo passwd -S "$username" | awk '{print $2}')
            if [[ "$password_status" == "NP" ]]; then
                echo "El usuario $username no tiene contraseña. Generando una contraseña segura..."
                # Genera una nueva contraseña segura para el usuario
                new_password=$(generate_password)
                
                # Verifica que la contraseña generada cumpla con los requisitos de longitud y complejidad
                if [[ ${#new_password} -ge 16 && "$new_password" =~ [A-Z] && "$new_password" =~ [a-z] && "$new_password" =~ [0-9] ]]; then
                    echo "Configurando la nueva contraseña para $username..."
                    # Configura la nueva contraseña para el usuario utilizando el comando chpasswd
                    echo "$username:$new_password" | sudo chpasswd
                    echo "Contraseña configurada correctamente para $username"
                else
                    echo "Error: La contraseña generada no cumple con los requisitos de seguridad."
                    exit 1
                fi
            fi
        fi
    # Leer el archivo /etc/passwd línea por línea
    done < /etc/passwd
}

# Llamar a la función para verificar contraseñas antes de continuar con el hardening
check_user_passwords

# Actualizar el sistema operativo a la última versión disponible
sudo dnf update -y

# Instalar los prerrequisitos necesarios para ejecutar el hardening RHEL9-CIS
sudo dnf install -y python3 python3-pip epel-release ansible libselinux-python3

# Instalar la librería jmespath para Ansible utilizando pip
pip3 install jmespath

# Clonar el repositorio oficial de RHEL9-CIS desde GitHub
git clone https://github.com/ansible-lockdown/RHEL9-CIS.git

# Cambiar al directorio del repositorio clonado
cd RHEL9-CIS

# Crear un archivo de inventario que especifica que el hardening se aplicará a la máquina local
cat <<EOL > inventario
[local]
127.0.0.1 ansible_connection=local
EOL

# Generar un hash de contraseña para proteger el bootloader
echo "Generando hash de la contraseña del bootloader..."
grub_password_hash=$(grub2-mkpasswd-pbkdf2 | grep pbkdf2 | awk '{ print $7 }')

# Configurar el hash generado en el archivo defaults/main.yml dentro del repositorio RHEL9-CIS
sed -i "s|^rhel9cis_bootloader_password_hash:.*|rhel9cis_bootloader_password_hash: \"grub.pbkdf2.sha512.10000.$grub_password_hash\"|" defaults/main.yml

# Ejecutar el playbook de Ansible para aplicar el hardening en el sistema
ansible-playbook -i inventario site.yml
