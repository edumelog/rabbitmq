#!/bin/bash

# =============================================================================
# start_stack.sh - Script de Inicialização do Ambiente RabbitMQ
# =============================================================================
# Este script inicia o ambiente RabbitMQ usando Docker Swarm
# 
# Funcionalidades:
# - Verifica se Docker Swarm está inicializado
# - Carrega variáveis de ambiente do arquivo .env
# - Cria a stack RabbitMQ
# - Verifica status dos serviços
# - Exibe logs em tempo real
#
# Uso: ./start_stack.sh
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para log com timestamp e cor
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $1${NC}"
}

# Função para verificar se Docker está rodando
check_docker() {
    log "Verificando se Docker está rodando..."
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker não está rodando. Inicie o Docker primeiro."
        exit 1
    fi
    log_success "Docker está rodando"
}

# Função para verificar se Docker Swarm está inicializado
check_swarm() {
    log "Verificando se Docker Swarm está inicializado..."
    if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        log_warning "Docker Swarm não está inicializado. Inicializando..."
        docker swarm init --advertise-addr 127.0.0.1
        log_success "Docker Swarm inicializado"
    else
        log_success "Docker Swarm já está ativo"
    fi
}

# Função para verificar se o arquivo .env existe
check_env_file() {
    log "Verificando arquivo de configuração .env..."
    if [ ! -f ".env" ]; then
        log_error "Arquivo .env não encontrado!"
        log "Crie um arquivo .env na raiz do projeto com as variáveis necessárias:"
        log "  RABBITMQ_DEFAULT_USER=admin"
        log "  RABBITMQ_DEFAULT_PASS=secret"
        log "  RABBITMQ_DEFAULT_VHOST=/"
        log "  RABBITMQ_ERLANG_COOKIE=secret_cookie"
        log "  STACK_NAME=rabbitmq (opcional)"
        exit 1
    fi
    log_success "Arquivo .env encontrado"
}

# Função para carregar variáveis de ambiente
load_env() {
    log "Carregando variáveis de ambiente..."
    set -a
    source .env
    set +a
    
    # Carregar variáveis de scripts se existir
    if [ -f ".env.scripts" ]; then
        log "Carregando variáveis de scripts..."
        set -a
        source .env.scripts
        set +a
    fi
    
    log_success "Variáveis de ambiente carregadas"
}

# Obter nome do serviço principal a partir do docker-compose.yml
get_service_name() {
    if [ -n "$SERVICE_NAME" ]; then
        echo "$SERVICE_NAME"
        return
    fi
    if [ -f "docker-compose.yml" ]; then
        local name=$(grep -E "^\s*[a-zA-Z0-9_-]+:" docker-compose.yml | grep -v "^\s*#" | grep -v "^\s*services:" | head -1 | sed 's/://' | xargs)
        if [ -n "$name" ]; then
            echo "$name"
            return
        fi
    fi
    echo "rabbitmq"
}

# Definir variáveis derivadas
set_stack_defaults() {
    SERVICE_NAME=$(get_service_name)
    # Permite override via variável de ambiente STACK_NAME; senão usa nome do serviço
    STACK_NAME="${STACK_NAME:-$SERVICE_NAME}"
}

# Função para verificar se a imagem oficial existe
check_image() {
    log "Verificando se a imagem oficial do RabbitMQ está disponível..."
    
    # Extrair nome da imagem do docker-compose.yml
    IMAGE_NAME=$(grep -E "^\s*image:" docker-compose.yml | head -1 | sed 's/.*image:\s*//' | xargs)
    
    if [ -z "$IMAGE_NAME" ]; then
        IMAGE_NAME="rabbitmq:3.13.3-management"
    fi
    
    # Tentar fazer pull se a imagem não existir localmente
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${IMAGE_NAME}$"; then
        log_warning "Imagem ${IMAGE_NAME} não encontrada localmente."
        log_info "Fazendo pull da imagem oficial..."
        if docker pull "${IMAGE_NAME}"; then
            log_success "Imagem ${IMAGE_NAME} baixada com sucesso!"
        else
            log_error "Erro ao baixar imagem ${IMAGE_NAME}"
            log_info "Verifique sua conexão com a internet e tente novamente"
            exit 1
        fi
    else
        log_success "Imagem ${IMAGE_NAME} encontrada localmente"
    fi
}

# Função para verificar se os diretórios de dados existem
check_data_directories() {
    log "Verificando diretórios de dados..."
    
    if [ ! -d "rabbit_data" ]; then
        log_warning "Diretório rabbit_data não encontrado. Criando..."
        mkdir -p rabbit_data
        log_success "Diretório rabbit_data criado"
    else
        log_success "Diretório rabbit_data encontrado"
    fi
    
    if [ ! -d "rabbit_logs" ]; then
        log_warning "Diretório rabbit_logs não encontrado. Criando..."
        mkdir -p rabbit_logs
        log_success "Diretório rabbit_logs criado"
    else
        log_success "Diretório rabbit_logs encontrado"
    fi
    
    if [ ! -d "rabbit_definitions" ]; then
        log_warning "Diretório rabbit_definitions não encontrado. Criando..."
        mkdir -p rabbit_definitions
        log_success "Diretório rabbit_definitions criado"
    else
        log_success "Diretório rabbit_definitions encontrado"
    fi
}

# Função para obter nome da rede do projeto do docker-compose.yml
get_project_network() {
    # Tentar usar variável de ambiente se disponível
    if [ -n "$NETWORK_NAME" ]; then
        echo "$NETWORK_NAME"
        return
    fi
    
    # Procurar no arquivo docker-compose.yml
    local network_name=$(grep -E "^\s*[a-zA-Z0-9_-]+_network:" docker-compose.yml | head -1 | sed 's/:.*//' | xargs)
    
    if [ -z "$network_name" ]; then
        # Fallback para padrão
        network_name="rabbitmq_network"
    fi
    
    echo "$network_name"
}

# Função para verificar se a rede específica do projeto existe e criar se necessário
check_project_network() {
    log "Verificando rede específica do projeto..."
    
    PROJECT_NETWORK=$(get_project_network)
    
    # Nome da rede como será criada pelo Docker Swarm (com prefixo da stack)
    STACK_NETWORK="${STACK_NAME}_${PROJECT_NETWORK}"
    
    # Verificar se alguma das redes existe (com ou sem prefixo da stack)
    EXISTING_NETWORK=""
    
    # Verificar rede com prefixo da stack primeiro
    if docker network ls --format "{{.Name}}" | grep -q "^${STACK_NETWORK}$"; then
        EXISTING_NETWORK="${STACK_NETWORK}"
    # Verificar rede sem prefixo (criada manualmente)
    elif docker network ls --format "{{.Name}}" | grep -q "^${PROJECT_NETWORK}$"; then
        EXISTING_NETWORK="${PROJECT_NETWORK}"
    fi
    
    if [ -n "$EXISTING_NETWORK" ]; then
        log_success "Rede específica do projeto encontrada: ${EXISTING_NETWORK}"
        
        # Verificar configurações da rede
        NETWORK_INFO=$(docker network inspect "${EXISTING_NETWORK}" 2>/dev/null || echo "")
        if [ -n "$NETWORK_INFO" ]; then
            NETWORK_DRIVER=$(echo "$NETWORK_INFO" | grep -o '"Driver": "[^"]*"' | cut -d'"' -f4 | head -1)
            NETWORK_ATTACHABLE=$(echo "$NETWORK_INFO" | grep -o '"Attachable": [^,}]*' | cut -d: -f2 | xargs | head -1)
            
            if [ "$NETWORK_DRIVER" != "overlay" ]; then
                log_warning "Rede ${EXISTING_NETWORK} existe mas tem driver diferente (${NETWORK_DRIVER} vs overlay)"
                log_info "A rede será usada pelo Docker Swarm se compatível"
            elif [ "$NETWORK_ATTACHABLE" != "true" ] && [ "$NETWORK_ATTACHABLE" != "True" ]; then
                log_info "Rede ${EXISTING_NETWORK} encontrada (driver: ${NETWORK_DRIVER}, attachable: ${NETWORK_ATTACHABLE})"
            fi
        fi
    else
        # A rede não existe - será criada automaticamente pelo Docker Swarm durante o stack deploy
        log_info "Rede ${PROJECT_NETWORK} não encontrada"
        log_info "A rede será criada automaticamente pelo Docker Swarm durante o deploy da stack"
        log_success "Rede será criada como: ${STACK_NETWORK}"
    fi
}

# Função para verificar se a rede externa existe
check_external_network() {
    log "Verificando rede externa net_nginx_pm..."
    if ! docker network ls | grep -q "net_nginx_pm"; then
        log_warning "Rede externa net_nginx_pm não encontrada. Criando..."
        docker network create --driver overlay --attachable net_nginx_pm
        log_success "Rede externa criada"
    else
        log_success "Rede externa encontrada"
    fi
}

# Função para verificar/criar rede externa compartilhada para comunicação entre stacks
check_shared_network() {
    # Nome da rede compartilhada pode ser parametrizado via SHARED_NETWORK_NAME
    SHARED_NETWORK_NAME="${SHARED_NETWORK_NAME:-shared_dev_net}"
    log "Verificando rede externa compartilhada ${SHARED_NETWORK_NAME}..."
    if ! docker network ls | grep -q "${SHARED_NETWORK_NAME}"; then
        log_warning "Rede externa ${SHARED_NETWORK_NAME} não encontrada. Criando..."
        docker network create --driver overlay --attachable "${SHARED_NETWORK_NAME}"
        log_success "Rede externa compartilhada criada"
    else
        log_success "Rede externa compartilhada encontrada"
    fi
}
# Verificar se já existe uma stack com o mesmo nome e alertar o usuário (sem derrubar)
check_existing_stack_conflict() {
    log "Verificando existência da stack '${STACK_NAME}'..."
    if docker stack ls --format "{{.Name}}" | grep -q "^${STACK_NAME}$"; then
        echo ""
        log_warning "Já existe uma stack ativa com o nome: ${STACK_NAME}"
        log_info "Defina STACK_NAME no .env para escolher explicitamente o nome da stack ou ajuste o nome do serviço no compose."
        log_info "Exemplos: STACK_NAME=rabbitmq-dev ou renomeie o serviço no docker-compose.yml"
        echo ""
        log_error "Conflito de nome de stack. Operação cancelada para evitar derrubar a stack existente."
        exit 1
    fi
}

# Função para verificar se o docker-compose.yml existe
check_compose_file() {
    log "Verificando arquivo docker-compose.yml..."
    
    if [ ! -f "docker-compose.yml" ]; then
        log_error "Arquivo docker-compose.yml não encontrado!"
        log "O arquivo docker-compose.yml deve estar na raiz do projeto"
        exit 1
    fi
    log_success "Arquivo docker-compose.yml encontrado"
}

# Função para criar a stack
create_stack() {
    log "Criando stack RabbitMQ..."
    
    # Verificar se o arquivo existe
    check_compose_file
    
    # Deploy da stack usando o arquivo docker-compose.yml
    docker stack deploy -c docker-compose.yml "${STACK_NAME}"
    
    log_success "Stack criada"
}

# Função para verificar status dos serviços
check_services_status() {
    log "Verificando status dos serviços..."
    
    # Aguardar serviços iniciarem
    log "Aguardando serviços iniciarem..."
    sleep 10
    
    # Verificar se os serviços estão rodando
    SERVICE_NAME=$(get_service_name)
    if docker service ls | grep -q "${STACK_NAME}_${SERVICE_NAME}.*1/1"; then
        log_success "Serviços iniciados com sucesso!"
    else
        log_warning "Aguardando serviços iniciarem..."
        sleep 10
        if docker service ls | grep -q "${STACK_NAME}_${SERVICE_NAME}.*1/1"; then
            log_success "Serviços iniciados com sucesso!"
        else
            log_error "Falha ao iniciar serviços"
            docker service ls
            exit 1
        fi
    fi
}

# Função para exibir informações de acesso
show_access_info() {
    log_success "Ambiente RabbitMQ iniciado com sucesso!"
    echo ""
    echo -e "${GREEN}📋 Informações de Acesso:${NC}"
    echo -e "  🐰 RabbitMQ Management: ${BLUE}http://localhost:15672${NC} (se portas estiverem expostas)"
    echo -e "  🔌 AMQP Port: ${BLUE}5672${NC} (se portas estiverem expostas)"
    echo -e "  🐳 Container: ${BLUE}${STACK_NAME}_${SERVICE_NAME}${NC}"
    echo ""
    echo -e "${GREEN}🔧 Comandos Úteis:${NC}"
    echo -e "  📊 Status: ${BLUE}docker service ls${NC}"
    echo -e "  📝 Logs: ${BLUE}docker service logs ${STACK_NAME}_${SERVICE_NAME} -f${NC}"
    echo -e "  🚪 Acessar: ${BLUE}docker exec -it \$(docker ps -q -f name=${STACK_NAME}_${SERVICE_NAME}) bash${NC}"
    echo -e "  🛑 Parar: ${BLUE}./stop_stack.sh${NC}"
    echo ""
}

# Função para exibir logs em tempo real
show_logs() {
    log "Exibindo logs em tempo real (Ctrl+C para sair)..."
    echo ""
    SERVICE_NAME=$(get_service_name)
    docker service logs ${STACK_NAME}_${SERVICE_NAME} -f
}

# Função principal
main() {
    log "🚀 Iniciando ambiente RabbitMQ com Docker Swarm..."
    echo ""
    
    # Verificações iniciais
    check_docker
    check_swarm
    check_env_file
    load_env
    set_stack_defaults
    check_image
    check_data_directories
    check_external_network
    check_shared_network
    check_project_network
    
    # Verificar conflito de nome de stack e não derrubar a existente
    check_existing_stack_conflict
    
    # Criar nova stack
    create_stack
    
    # Verificar status
    check_services_status
    
    # Exibir informações
    show_access_info
    
    # Perguntar se quer ver logs
    echo -e "${YELLOW}Deseja visualizar os logs em tempo real? (y/n):${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        show_logs
    else
        log "Ambiente iniciado! Use './stop_stack.sh' para parar."
    fi
}

# Executar função principal
main "$@"
