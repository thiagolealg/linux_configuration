#!/bin/bash

# Função para exibir mensagens de status
status_msg() {
    if [ $? -eq 0 ]; then
        echo "[OK] $1"
    else
        echo "[ERROR] $1"
        exit 1
    fi
}

# Atualizar e instalar dependências necessárias para o script
sudo apt update && sudo apt upgrade -y
status_msg "Atualização do sistema"
sudo apt install -y jq ca-certificates openssl python3-venv
status_msg "Instalação de dependências"

# Caminho para o diretório do Jupyter
JUPYTER_DIR=~/.jupyter

# Criar diretório para os certificados SSL
mkdir -p $JUPYTER_DIR/ssl
status_msg "Criação do diretório para certificados SSL"

# Gerar um novo certificado SSL autoassinado
cd $JUPYTER_DIR/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout mycert.key -out mycert.pem -subj "/C=BR/ST=Estado/L=Cidade/O=Organizacao/OU=Unidade/CN=195.200.0.240"
status_msg "Geração do certificado SSL autoassinado"

# Configurar Jupyter Notebook para usar SSL e desativar a senha
cd $JUPYTER_DIR
if [ ! -f jupyter_notebook_config.py ]; then
    jupyter notebook --generate-config
    status_msg "Geração do arquivo de configuração do Jupyter Notebook"
fi

# Adicionar configurações ao arquivo de configuração
SSL_CONFIG="
c.NotebookApp.certfile = u'$JUPYTER_DIR/ssl/mycert.pem'
c.NotebookApp.keyfile = u'$JUPYTER_DIR/ssl/mycert.key'
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 8888
c.NotebookApp.open_browser = False
c.NotebookApp.allow_root = True
c.NotebookApp.trust_xheaders = True
c.NotebookApp.disable_check_xsrf = True
c.NotebookApp.token = ''
c.NotebookApp.password = ''
"

# Remover qualquer configuração duplicada existente
sed -i '/c.NotebookApp.certfile/d' jupyter_notebook_config.py
sed -i '/c.NotebookApp.keyfile/d' jupyter_notebook_config.py
sed -i '/c.NotebookApp.ip/d' jupyter_notebook_config.py
sed -i '/c.NotebookApp.port/d' jupyter_notebook_config.py
sed -i '/c.NotebookApp.open_browser/d' jupyter_notebook_config.py
sed -i '/c.NotebookApp.allow_root/d' jupyter_notebook_config.py
sed -i '/c.NotebookApp.trust_xheaders/d' jupyter_notebook_config.py
sed -i '/c.NotebookApp.disable_check_xsrf/d' jupyter_notebook_config.py
sed -i '/c.NotebookApp.token/d' jupyter_notebook_config.py
sed -i '/c.NotebookApp.password/d' jupyter_notebook_config.py

# Adicionar nova configuração
echo "$SSL_CONFIG" >> jupyter_notebook_config.py
status_msg "Configuração do Jupyter Notebook para usar SSL e desativar a senha"

# Importar o certificado SSL autoassinado para o sistema operacional
sudo cp $JUPYTER_DIR/ssl/mycert.pem /usr/local/share/ca-certificates/mycert.crt
status_msg "Cópia do certificado SSL para o diretório de certificados do sistema"
sudo update-ca-certificates
status_msg "Atualização dos certificados do sistema"

# Verificar se o certificado foi instalado corretamente
if openssl x509 -noout -in /usr/local/share/ca-certificates/mycert.crt; then
    status_msg "Verificação do certificado SSL instalado com sucesso"
else
    echo "[ERROR] O certificado SSL não foi instalado corretamente"
    exit 1
fi

# Configurar a extensão Jupyter no VS Code
VSCODE_SETTINGS_DIR=~/.config/Code/User
VSCODE_SETTINGS_FILE=$VSCODE_SETTINGS_DIR/settings.json

# Criar diretório de configurações do VS Code, se não existir
mkdir -p $VSCODE_SETTINGS_DIR
status_msg "Criação do diretório de configurações do VS Code"

# Criar arquivo de configurações do VS Code, se não existir
if [ ! -f $VSCODE_SETTINGS_FILE ]; then
    echo "{}" > $VSCODE_SETTINGS_FILE
    status_msg "Criação do arquivo de configurações do VS Code"
fi

# Adicionar configuração de URL do servidor Jupyter ao settings.json
jq '. += {"jupyter.jupyterServer.remote.url": "https://195.200.0.240:8888"}' $VSCODE_SETTINGS_FILE > $VSCODE_SETTINGS_FILE.tmp && mv $VSCODE_SETTINGS_FILE.tmp $VSCODE_SETTINGS_FILE
status_msg "Configuração do VS Code para se conectar ao servidor Jupyter"

# Adicionar configuração de certificação ao settings.json
jq '. += {"http.proxyStrictSSL": false}' $VSCODE_SETTINGS_FILE > $VSCODE_SETTINGS_FILE.tmp && mv $VSCODE_SETTINGS_FILE.tmp $VSCODE_SETTINGS_FILE
status_msg "Configuração do VS Code para ignorar erros de certificação SSL"

# Verificação final das configurações
CONFIG_CHECK=$(jq '.["jupyter.jupyterServer.remote.url"], .["http.proxyStrictSSL"]' $VSCODE_SETTINGS_FILE)
if [[ $CONFIG_CHECK == *"https://195.200.0.240:8888"* ]] && [[ $CONFIG_CHECK == *"false"* ]]; then
    echo "[OK] As configurações foram aplicadas corretamente."
else
    echo "[ERROR] Houve um problema ao aplicar as configurações. Verificação do settings.json: $CONFIG_CHECK"
    exit 1
fi

echo "Configuração do VS Code concluída. Certifique-se de reiniciar o VS Code para que as configurações sejam aplicadas."

# Criar e ativar um ambiente virtual
python3 -m venv $JUPYTER_DIR/myenv
status_msg "Criação do ambiente virtual"
source $JUPYTER_DIR/myenv/bin/activate
status_msg "Ativação do ambiente virtual"

# Instalar pacotes necessários no ambiente virtual
pip install --upgrade pip
pip install jupyter pandas
status_msg "Instalação de pacotes no ambiente virtual"

# Parar qualquer instância do Jupyter Notebook que esteja rodando
pkill -f jupyter-notebook
if [ $? -eq 0 ]; then
    status_msg "Parada de instâncias existentes do Jupyter Notebook"
else
    echo "[WARNING] Nenhuma instância existente do Jupyter Notebook encontrada para parar."
fi

# Iniciar o Jupyter Notebook no ambiente virtual
echo "Iniciando o Jupyter Notebook..."
$JUPYTER_DIR/myenv/bin/jupyter notebook --allow-root --certfile=$JUPYTER_DIR/ssl/mycert.pem --keyfile=$JUPYTER_DIR/ssl/mycert.key --port=8888 --ip=0.0.0.0
status_msg "Jupyter Notebook iniciado com SSL e sem senha"
