#!/bin/bash

# Parar qualquer servidor VNC ou Xvfb em execução
vncserver -kill :1 &>/dev/null
killall Xtightvnc &>/dev/null

# Matar qualquer processo Xvfb ou X server em execução
pkill Xvfb
pkill X

# Remover arquivos de bloqueio se existirem
rm -f /tmp/.X1-lock
rm -f /tmp/.X11-unix/X1

# Iniciar o servidor Xvfb
Xvfb :1 -screen 0 1024x768x16 &
XVFB_PID=$!

# Esperar alguns segundos para garantir que o Xvfb foi iniciado corretamente
sleep 5

# Exportar a variável DISPLAY
export DISPLAY=:1

# Verificar se o Wine está instalado
if ! command -v wine &>/dev/null; then
    echo "Wine não está instalado. Instalando Wine..."
    sudo dpkg --add-architecture i386
    sudo apt update
    sudo apt install -y wine32
fi

# Recriar o diretório Wine
rm -rf ~/.wine
winecfg &>/dev/null

# Instalar o MetaTrader 5
wine /root/mt5setup.exe /silent

# Verificar a instalação do MetaTrader 5
if [ -d "$HOME/.wine/drive_c/Program Files/MetaTrader 5" ]; then
    echo "MetaTrader 5 instalado com sucesso!"
else
    echo "Erro na instalação do MetaTrader 5."
    kill $XVFB_PID
    exit 1
fi

# Mantenha o Xvfb rodando
wait $XVFB_PID
