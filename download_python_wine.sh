#!/bin/bash

# Função para verificar se um comando falhou
function check_command {
    if [ $? -ne 0 ]; then
        echo "Erro: $1 falhou."
        exit 1
    fi
}

# Função para matar processos em uma porta específica
function kill_processes_on_port {
    PORT=$1
    if sudo lsof -i :$PORT &>/dev/null; then
        echo "A porta $PORT está em uso. Matando processos..."
        sudo lsof -t -i :$PORT | xargs -r sudo kill -9
        if sudo lsof -i :$PORT &>/dev/null; then
            echo "Erro: Liberar porta $PORT falhou."
            exit 1
        fi
    fi
}

# Função para configurar o Wine
function configure_wine {
    echo "Configurando o Wine..."
    winecfg &> /dev/null
    check_command "Configurar Wine"
}

# Parando servidores em execução
echo "Parando servidores Xvfb, Fluxbox, x11vnc e noVNC em execução..."
pkill Xvfb
pkill fluxbox
pkill websockify
pkill x11vnc

# Removendo arquivos de bloqueio, se existirem
echo "Removendo arquivos de bloqueio, se existirem..."
rm -f /tmp/.X1-lock
rm -f /tmp/.X11-unix/X1

# Verificando se as portas estão em uso
echo "Verificando se as portas 8080 e 5900 estão em uso..."
kill_processes_on_port 8080
kill_processes_on_port 5900

# Verifica se as dependências estão instaladas
DEPENDENCIES=(xvfb fluxbox websockify nginx wine curl x11vnc)
echo "Verificando dependências..."
for DEP in "${DEPENDENCIES[@]}"; do
    if ! dpkg -s $DEP &> /dev/null; then
        echo "Dependência $DEP não está instalada. Instalando $DEP..."
        sudo apt-get install -y $DEP
        check_command "Instalar $DEP"
    fi
done

# Configurando o Wine
configure_wine

# Iniciando o servidor Xvfb
echo "Iniciando o servidor Xvfb..."
Xvfb :1 -screen 0 1024x768x16 &
XVFB_PID=$!
sleep 5
export DISPLAY=:1
check_command "Iniciar Xvfb"

# Iniciando o Fluxbox
echo "Iniciando o Fluxbox..."
fluxbox &
FLUXBOX_PID=$!
sleep 5
check_command "Iniciar Fluxbox"

# Iniciando o servidor x11vnc sem senha
echo "Iniciando o servidor x11vnc..."
x11vnc -display :1 -forever -rfbport 5900 -shared &
X11VNC_PID=$!
sleep 5
check_command "Iniciar x11vnc"

# Baixando noVNC se necessário
NOVNC_DIR="/opt/novnc"
if [ ! -d "$NOVNC_DIR" ]; then
    echo "Baixando noVNC..."
    mkdir -p /opt/novnc
    curl -L https://github.com/novnc/noVNC/archive/refs/tags/v1.3.0.tar.gz | tar -xz -C /opt/novnc --strip-components=1
    check_command "Baixar noVNC"
else
    echo "noVNC já está baixado."
fi

# Gerando certificado SSL autoassinado
echo "Gerando certificado SSL autoassinado..."
if [ ! -f /root/self.pem ] || [ ! -f /root/self.key ]; then
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /root/self.key -out /root/self.pem -subj "/CN=195.200.0.240"
    check_command "Gerar certificado SSL"
else
    echo "Certificado SSL já existe."
fi

# Configurando NGINX para proxy reverso
echo "Configurando NGINX para proxy reverso..."
sudo bash -c 'cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 8080 ssl;
    server_name 195.200.0.240;

    ssl_certificate /root/self.pem;
    ssl_certificate_key /root/self.key;

    location / {
        root /opt/novnc;
        index vnc.html;
    }

    location /websockify {
        proxy_pass http://localhost:8081;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF'
check_command "Configurar NGINX"

# Reiniciando NGINX
echo "Reiniciando NGINX..."
sudo systemctl restart nginx
if [ $? -ne 0 ]; then
    echo "Erro: Reiniciar NGINX falhou."
    sudo systemctl status nginx.service
    sudo journalctl -xeu nginx.service
    exit 1
fi

# Iniciando o servidor noVNC
echo "Iniciando o servidor noVNC..."
/opt/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 8081 --cert /root/self.pem --key /root/self.key &
NOVNC_PID=$!
sleep 5
check_command "Iniciar noVNC"

# Verificando logs do noVNC
echo "Verificando logs do noVNC..."
ps aux | grep novnc_proxy

# Baixando e instalando o Python no Wine
echo "Baixando e instalando o Python no Wine..."
wget https://www.python.org/ftp/python/3.10.0/python-3.10.0.exe -O python-3.10.0.exe
WINEARCH=win32 WINEPREFIX=~/.wine32 wine python-3.10.0.exe /quiet InstallAllUsers=1 PrependPath=1
check_command "Instalar Python no Wine"

# Instalando pip no ambiente Wine
echo "Instalando pip no Wine..."
WINEARCH=win32 WINEPREFIX=~/.wine32 wine C:\\Python310\\python.exe get-pip.py
check_command "Instalar pip no Wine"

# Instalando o TA-Lib usando pip no Wine
echo "Instalando TA-Lib no Wine..."
WINEARCH=win32 WINEPREFIX=~/.wine32 wine C:\\Python310\\python.exe -m pip install TA-Lib
check_command "Instalar TA-Lib no Wine"

# Verifica se o MetaTrader 5 está instalado
MT5_PATH="$HOME/.wine32/drive_c/Program Files/MetaTrader 5/terminal64.exe"
if [ ! -f "$MT5_PATH" ];then
    echo "Erro: MetaTrader 5 não encontrado no caminho especificado."
    exit 1
fi

echo "Iniciando o MetaTrader 5..."
DISPLAY=:1 wine "$MT5_PATH" &> /tmp/mt5_install.log &
MT5_PID=$!
sleep 10
check_command "Iniciar MetaTrader 5"

echo "Verificando logs do MetaTrader 5..."
cat /tmp/mt5_install.log

# Função para capturar sinais e encerrar processos corretamente
cleanup() {
    echo "Encerrando processos..."
    kill $XVFB_PID $FLUXBOX_PID $NOVNC_PID $X11VNC_PID $MT5_PID
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "Verificando se o MetaTrader 5 está em execução..."
ps aux | grep terminal64.exe

echo "Verificando se o servidor noVNC está em execução..."
ps aux | grep novnc_proxy

echo "Verificando se o servidor x11vnc está em execução..."
ps 
