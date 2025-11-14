#!/bin/bash

# =============================================================================
# stop_stack.sh - Script para Parar o Ambiente RabbitMQ
# =============================================================================
# Este script para o ambiente RabbitMQ usando Docker Swarm
# 
# Funcionalidades:
# - Para a stack RabbitMQ
# - Remove serviços e redes
# - Limpa recursos não utilizados
# - Exibe status final
#
# Uso: ./stop_stack.sh
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

# Carregar .env se existir (para permitir STACK_NAME definido pelo usuário)
load_env_if_exists() {
    if [ -f ".env" ]; then
        set -a
        source .env
        set +a
    fi
    if [ -f ".env.scripts" ]; then
        set -a
        source .env.scripts
        set +a
    fi
}

# Definir variáveis derivadas
set_stack_defaults() {
    SERVICE_NAME=$(get_service_name)
    # Permite override via variável de ambiente STACK_NAME; senão usa nome do serviço
    STACK_NAME="${STACK_NAME:-$SERVICE_NAME}"
}

# Detectar automaticamente o nome da stack caso não seja igual ao serviço
detect_stack_name_by_service() {
    if docker stack ls --format "{{.Name}}" | grep -q "^${STACK_NAME}$"; then
        return
    fi
    local candidate=""
    while read -r s; do
        if docker service ls --format "{{.Name}}" | grep -q "^${s}_${SERVICE_NAME}$"; then
            candidate="$s"
            break
        fi
    done < <(docker stack ls --format "{{.Name}}")

    if [ -n "$candidate" ]; then
        STACK_NAME="$candidate"
        log_info "Stack detectada automaticamente pelo serviço: ${STACK_NAME}"
        return
    fi

    # Tentativa 2: detectar pela imagem oficial do RabbitMQ
    if [ -f "docker-compose.yml" ]; then
        local image=$(grep -E "^\s*image:" docker-compose.yml | head -1 | sed 's/.*image:\s*//' | xargs)
        if [ -n "$image" ]; then
            local service_full=$(docker service ls -q | while read -r id; do
                local name=$(docker service inspect "$id" --format '{{.Spec.Name}}')
                local img=$(docker service inspect "$id" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}')
                if echo "$img" | grep -q "$image"; then
                    echo "$name"
                fi
            done | head -1)
            if [ -n "$service_full" ]; then
                STACK_NAME="${service_full%%_*}"
                log_info "Stack detectada pela imagem (${image}): ${STACK_NAME}"
                return
            fi
        fi
    fi
}

# Função para verificar se Docker está rodando
check_docker() {
    log "Verificando se Docker está rodando..."
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker não está rodando."
        exit 1
    fi
    log_success "Docker está rodando"
}

# Função para verificar se Docker Swarm está inicializado
check_swarm() {
    log "Verificando se Docker Swarm está inicializado..."
    if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        log_warning "Docker Swarm não está inicializado."
        exit 1
    fi
    log_success "Docker Swarm está ativo"
}

# Função para verificar se a stack existe
check_stack_exists() {
    log "Verificando se a stack de desenvolvimento existe..."
    if ! docker stack ls --format "{{.Name}}" | grep -q "^${STACK_NAME}$"; then
        log_warning "Stack de desenvolvimento não encontrada: ${STACK_NAME}"
        log_info "Stacks disponíveis:" && docker stack ls --format "table {{.Name}}\t{{.Services}}"
        log_info "Sugestão: exporte STACK_NAME=nome-da-stack e rode novamente este script."
        
        # Verificar se há containers do docker-compose.dev.yml rodando
        check_compose_containers
        exit 0
    fi
    log_success "Stack de desenvolvimento encontrada: ${STACK_NAME}"
}

# Função para verificar containers do docker-compose.yml
check_compose_containers() {
    log "Verificando containers do docker-compose.yml..."
    
    # Verificar se há containers com nome do serviço rodando
    SERVICE_NAME=$(get_service_name)
    COMPOSE_CONTAINERS=$(docker ps --format "{{.Names}}" | grep -E "${SERVICE_NAME}" | wc -l)
    
    if [ "$COMPOSE_CONTAINERS" -gt 0 ]; then
        log_warning "Containers do docker-compose.yml encontrados:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "${SERVICE_NAME}"
        echo ""
        log "Deseja parar esses containers do docker-compose? (y/n):"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            log "Parando containers do docker-compose.yml..."
            docker compose -f docker-compose.yml down
            log_success "Containers do docker-compose.yml foram parados"
        fi
    else
        log_success "Nenhum container do docker-compose.yml em execução"
    fi
}

# Função para exibir status atual dos serviços
show_current_status() {
    log "Status atual dos serviços:"
    echo ""
    docker service ls | grep "${STACK_NAME}_" || log_warning "Nenhum serviço da stack encontrado"
    echo ""
}

# Função para parar a stack
stop_stack() {
    log "Parando stack de desenvolvimento..."
    
    # Reduzir serviço a zero réplicas (acelera desligamento dos tasks)
    if docker service ls --format "{{.Name}}" | grep -q "^${STACK_NAME}_${SERVICE_NAME}$"; then
        log "Reduzindo serviço ${STACK_NAME}_${SERVICE_NAME} para 0 réplicas..."
        docker service scale ${STACK_NAME}_${SERVICE_NAME}=0 >/dev/null 2>&1 || true
        sleep 3
    fi

    # Remover a stack
    docker stack rm "${STACK_NAME}"
    
    log "Aguardando stack ser removida..."
    
    # Aguardar até que a stack seja completamente removida
    while docker stack ls --format "{{.Name}}" | grep -q "^${STACK_NAME}$"; do
        echo -n "."
        sleep 2
    done

    # Remover serviços remanescentes com o prefixo da stack (defensivo)
    REMAIN_SVCS=$(docker service ls --format "{{.Name}}" | grep -E "^${STACK_NAME}_" || true)
    if [ -n "$REMAIN_SVCS" ]; then
        log_warning "Serviços ainda encontrados após remover stack. Removendo..."
        echo "$REMAIN_SVCS" | xargs -r docker service rm >/dev/null 2>&1 || true
    fi

    # Aguardar containers órfãos sumirem; se persistirem, remover à força
    TRIES=10
    while [ $TRIES -gt 0 ]; do
        ORPHANS=$(docker ps -q -f "name=^${STACK_NAME}_${SERVICE_NAME}\\.")
        if [ -z "$ORPHANS" ]; then
            break
        fi
        sleep 2
        TRIES=$((TRIES-1))
    done

    ORPHANS=$(docker ps -q -f "name=^${STACK_NAME}_${SERVICE_NAME}\\.")
    if [ -n "$ORPHANS" ]; then
        log_warning "Containers órfãos ainda em execução. Removendo à força..."
        docker rm -f $ORPHANS >/dev/null 2>&1 || true
    fi
    
    echo ""
    log_success "Stack removida com sucesso"
}

# Função para limpar recursos específicos do desenvolvimento
cleanup_dev_resources() {
    log "Limpando recursos específicos do desenvolvimento..."
    
    # Remover apenas containers órfãos relacionados ao desenvolvimento
    log "Removendo containers órfãos do desenvolvimento..."
    docker container prune -f --filter "label=com.docker.compose.project=dev" >/dev/null 2>&1 || true
    
    # Remover apenas redes não utilizadas relacionadas ao desenvolvimento
    log "Removendo redes não utilizadas do desenvolvimento..."
    docker network prune -f --filter "label=com.docker.compose.project=dev" >/dev/null 2>&1 || true
    
    # Não remover redes específicas pois são redes fixas
    log "Redes específicas são mantidas (redes fixas)"
    
    # Remover apenas volumes não utilizados relacionados ao desenvolvimento
    log "Removendo volumes não utilizados do desenvolvimento..."
    docker volume prune -f --filter "label=com.docker.compose.project=dev" >/dev/null 2>&1 || true
    
    log_success "Recursos do desenvolvimento limpos"
}

# Função para verificar se há outras stacks relacionadas ao desenvolvimento
check_dev_related_stacks() {
    log "Verificando outras stacks relacionadas ao desenvolvimento..."
    
    # Verificar stacks que podem ter sido criadas pelo docker-compose.dev.yml
    DEV_RELATED_STACKS=$(docker stack ls --format "{{.Name}}" | grep -E "(dev-|development)" | grep -v "^${STACK_NAME}$" | wc -l)
    
    if [ "$DEV_RELATED_STACKS" -gt 0 ]; then
        log_warning "Outras stacks de desenvolvimento encontradas:"
        docker stack ls | grep -E "(dev-|development)" | grep -v "^${STACK_NAME}$"
        echo ""
        log "Deseja parar essas stacks de desenvolvimento também? (y/n):"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            log "Parando stacks de desenvolvimento relacionadas..."
            docker stack ls --format "{{.Name}}" | grep -E "(dev-|development)" | grep -v "^${STACK_NAME}$" | xargs -r docker stack rm
            log_success "Stacks de desenvolvimento relacionadas foram paradas"
        fi
    else
        log_success "Nenhuma outra stack de desenvolvimento em execução"
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

# Função para verificar se a rede está em uso
check_network_in_use() {
    local network_name="$1"
    local in_use=0
    
    # Verificar se há containers conectados à rede (standalone containers)
    local containers_connected=$(docker network inspect "$network_name" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "")
    if [ -n "$containers_connected" ] && [ "$containers_connected" != " " ]; then
        local container_count=$(echo "$containers_connected" | tr ' ' '\n' | grep -v '^$' | wc -l)
        if [ "$container_count" -gt 0 ]; then
            log_info "Rede ${network_name} está conectada a ${container_count} container(s)"
            in_use=1
        fi
    fi
    
    # Verificar se há serviços do Docker Swarm usando a rede
    local services_count=0
    for service in $(docker service ls --format "{{.Name}}" 2>/dev/null); do
        local service_networks=$(docker service inspect "$service" --format '{{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}' 2>/dev/null || echo "")
        if echo "$service_networks" | grep -q "${network_name}"; then
            services_count=$((services_count + 1))
            log_info "Serviço ${service} está usando a rede ${network_name}"
        fi
    done
    
    if [ "$services_count" -gt 0 ]; then
        log_info "Rede ${network_name} está sendo usada por ${services_count} serviço(s)"
        in_use=1
    fi
    
    # Verificar se há outras stacks (que não sejam dev-stack) usando a rede
    local other_stacks=0
    for stack in $(docker stack ls --format "{{.Name}}" 2>/dev/null | grep -v "^dev-stack$"); do
        for service in $(docker stack services "$stack" --format "{{.Name}}" 2>/dev/null); do
            local full_service_name="${stack}_${service}"
            local stack_networks=$(docker service inspect "$full_service_name" --format '{{range .Spec.TaskTemplate.Networks}}{{.Target}} {{end}}' 2>/dev/null || echo "")
            if echo "$stack_networks" | grep -q "${network_name}"; then
                other_stacks=$((other_stacks + 1))
                log_info "Stack ${stack} (serviço ${service}) está usando a rede ${network_name}"
            fi
        done
    done
    
    if [ "$other_stacks" -gt 0 ]; then
        log_info "Rede ${network_name} está sendo usada por outras stacks"
        in_use=1
    fi
    
    # Retornar código de saída baseado no uso
    if [ "$in_use" -eq 1 ]; then
        return 0  # Rede está em uso
    else
        return 1  # Rede não está em uso
    fi
}

# Função para gerenciar a rede do projeto
manage_project_network() {
    log "Verificando rede específica do projeto..."
    
    PROJECT_NETWORK=$(get_project_network)
    STACK_NETWORK="${STACK_NAME}_${PROJECT_NETWORK}"
    
    # Verificar qual rede existe (com ou sem prefixo)
    EXISTING_NETWORK=""
    if docker network ls --format "{{.Name}}" | grep -q "^${STACK_NETWORK}$"; then
        EXISTING_NETWORK="${STACK_NETWORK}"
    elif docker network ls --format "{{.Name}}" | grep -q "^${PROJECT_NETWORK}$"; then
        EXISTING_NETWORK="${PROJECT_NETWORK}"
    fi
    
    if [ -z "$EXISTING_NETWORK" ]; then
        log_info "Rede do projeto não encontrada. Nada a fazer."
        return
    fi
    
    log_success "Rede encontrada: ${EXISTING_NETWORK}"
    
    # Verificar se está em uso
    if check_network_in_use "$EXISTING_NETWORK"; then
        echo ""
        log_warning "A rede ${EXISTING_NETWORK} está em uso por outros containers, serviços ou stacks"
        log_info "A rede será mantida automaticamente para evitar interrupções"
        log_success "Rede preservada: ${EXISTING_NETWORK}"
        return
    else
        echo ""
        log_info "A rede ${EXISTING_NETWORK} não está em uso"
        echo ""
        log_warning "O que deseja fazer com a rede ${EXISTING_NETWORK}?"
        echo ""
        log_info "   [M]anter (padrão) - Mantém a rede para uso futuro"
        log_info "   [R]emover - Remove a rede (disponível pois não está em uso)"
        echo ""
        
        while true; do
            read -p "Escolha (M/R) [M]: " response
            response=${response:-M}  # Default para M se vazio
            
            case "${response^^}" in
                M|MANTER|KEEP|YES|Y)
                    log_success "Rede ${EXISTING_NETWORK} será mantida"
                    break
                    ;;
                R|REMOVER|REMOVE|DELETE|D)
                    log "Removendo rede ${EXISTING_NETWORK}..."
                    if docker network rm "$EXISTING_NETWORK" 2>/dev/null; then
                        log_success "Rede ${EXISTING_NETWORK} removida com sucesso"
                    else
                        log_error "Erro ao remover rede ${EXISTING_NETWORK}"
                        log_info "A rede pode estar sendo usada ou já foi removida"
                    fi
                    break
                    ;;
                *)
                    log_error "Opção inválida. Escolha M (Manter) ou R (Remover)"
                    ;;
            esac
        done
    fi
}

# Função para exibir informações finais
show_final_info() {
    log_success "Ambiente RabbitMQ parado com sucesso!"
    echo ""
    echo -e "${GREEN}📋 Status Final:${NC}"
    echo -e "  🐳 Stack: ${BLUE}${STACK_NAME}${NC} - ${RED}PARADA${NC}"
    echo -e "  🐰 RabbitMQ: ${RED}INDISPONÍVEL${NC}"
    echo -e "  📁 Dados: ${BLUE}./rabbit_data/${NC} - ${GREEN}PRESERVADO${NC}"
    echo -e "  📁 Logs: ${BLUE}./rabbit_logs/${NC} - ${GREEN}PRESERVADO${NC}"
    echo ""
    echo -e "${GREEN}🔧 Comandos Úteis:${NC}"
    echo -e "  📊 Status: ${BLUE}docker stack ls${NC}"
    echo -e "  🚀 Reiniciar: ${BLUE}./start_stack.sh${NC}"
    echo -e "  🧹 Limpeza completa: ${BLUE}docker system prune -a${NC}"
    echo ""
}

# Função para confirmar parada
confirm_stop() {
    echo -e "${YELLOW}⚠️  Você está prestes a parar o ambiente RabbitMQ.${NC}"
    echo -e "${YELLOW}   Isso irá:${NC}"
    echo -e "   • Parar apenas a stack '${STACK_NAME}' (criada pelo start_stack.sh)"
    echo -e "   • Parar containers do docker-compose.yml (se existirem)"
    echo -e "   • Limpar apenas recursos relacionados ao RabbitMQ"
    echo -e "   • Preservar outras stacks e containers em execução"
    echo ""
    echo -e "${YELLOW}   Os dados em ./rabbit_data/ e ./rabbit_logs/ serão preservados.${NC}"
    echo ""
    echo -e "${YELLOW}Deseja continuar? (y/n):${NC}"
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "Operação cancelada pelo usuário."
        exit 0
    fi
}

# Função principal
main() {
    log "🛑 Parando ambiente RabbitMQ..."
    echo ""
    
    # Verificações iniciais
    check_docker
    check_swarm
    load_env_if_exists
    set_stack_defaults
    detect_stack_name_by_service
    check_stack_exists
    
    # Confirmar parada
    confirm_stop
    
    # Exibir status atual
    show_current_status
    
    # Parar stack
    stop_stack
    
    # Gerenciar rede do projeto (perguntar se quer manter ou remover)
    manage_project_network
    
    # Limpar recursos específicos do desenvolvimento
    cleanup_dev_resources
    
    # Verificar outras stacks relacionadas ao desenvolvimento
    check_dev_related_stacks
    
    # Exibir informações finais
    show_final_info
}

# Executar função principal
main "$@"
