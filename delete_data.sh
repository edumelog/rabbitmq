#!/bin/bash

# =============================================================================
# delete_data.sh - Script para Apagar Dados do RabbitMQ
# =============================================================================
# Este script apaga todos os dados persistentes do RabbitMQ, permitindo
# começar do zero.
# 
# Funcionalidades:
# - Para o RabbitMQ se estiver rodando
# - Apaga o conteúdo de rabbit_data/ (dados do mnesia)
# - Apaga o conteúdo de rabbit_logs/ (logs)
# - Opcionalmente pode limpar definitions.json
# - Exibe avisos claros sobre a operação destrutiva
#
# Uso: ./delete_data.sh
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Verificar se estamos no diretório correto
if [ ! -f "docker-compose.yml" ]; then
    log_error "docker-compose.yml não encontrado!"
    log_error "Execute este script na raiz do projeto RabbitMQ"
    exit 1
fi

# Diretórios que serão limpos
RABBIT_DATA_DIR="./rabbit_data"
RABBIT_LOGS_DIR="./rabbit_logs"
RABBIT_DEFINITIONS_DIR="./rabbit_definitions"
DEFINITIONS_FILE="${RABBIT_DEFINITIONS_DIR}/definitions.json"

# Função para verificar se Docker está rodando
check_docker() {
    log "Verificando se Docker está rodando..."
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker não está rodando."
        exit 1
    fi
    log_success "Docker está rodando"
}

# Função para verificar se há containers RabbitMQ rodando
check_rabbitmq_running() {
    log "Verificando se há containers RabbitMQ rodando..."
    
    # Verificar containers do docker-compose
    COMPOSE_CONTAINERS=$(docker ps --format "{{.Names}}" | grep -i rabbitmq | wc -l)
    
    # Verificar serviços do Docker Swarm
    SWARM_SERVICES=$(docker service ls --format "{{.Name}}" | grep -i rabbitmq | wc -l)
    
    if [ "$COMPOSE_CONTAINERS" -gt 0 ] || [ "$SWARM_SERVICES" -gt 0 ]; then
        log_warning "RabbitMQ está rodando!"
        echo ""
        if [ "$COMPOSE_CONTAINERS" -gt 0 ]; then
            log_info "Containers encontrados:"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -i rabbitmq
        fi
        if [ "$SWARM_SERVICES" -gt 0 ]; then
            log_info "Serviços encontrados:"
            docker service ls --format "table {{.Name}}\t{{.Replicas}}" | grep -i rabbitmq
        fi
        echo ""
        log_warning "É necessário parar o RabbitMQ antes de apagar os dados."
        echo ""
        read -p "Deseja parar o RabbitMQ agora? (s/N): " -r STOP_RABBITMQ
        echo ""
        
        if [[ "$STOP_RABBITMQ" =~ ^[Ss]$ ]]; then
            log "Parando RabbitMQ..."
            
            # Tentar parar via docker-compose
            if [ -f "docker-compose.yml" ]; then
                docker compose -f docker-compose.yml down 2>/dev/null || true
            fi
            
            # Tentar parar via stack (se existir stop_stack.sh)
            if [ -f "stop_stack.sh" ] && [ -x "stop_stack.sh" ]; then
                ./stop_stack.sh || true
            fi
            
            # Aguardar um pouco para garantir que os containers foram parados
            sleep 3
            
            log_success "RabbitMQ parado"
        else
            log_error "Operação cancelada. Pare o RabbitMQ manualmente antes de continuar."
            exit 1
        fi
    else
        log_success "Nenhum container RabbitMQ em execução"
    fi
}

# Função para calcular tamanho dos diretórios
get_dir_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

# Função para exibir informações sobre os dados que serão apagados
show_data_info() {
    print_header "📊 Informações dos Dados"
    
    echo ""
    log_info "Diretórios que serão limpos:"
    echo ""
    
    if [ -d "$RABBIT_DATA_DIR" ]; then
        DATA_SIZE=$(get_dir_size "$RABBIT_DATA_DIR")
        FILE_COUNT=$(find "$RABBIT_DATA_DIR" -type f 2>/dev/null | wc -l)
        echo -e "  📁 ${CYAN}${RABBIT_DATA_DIR}${NC}"
        echo -e "     Tamanho: ${YELLOW}${DATA_SIZE}${NC}"
        echo -e "     Arquivos: ${YELLOW}${FILE_COUNT}${NC}"
    else
        echo -e "  📁 ${CYAN}${RABBIT_DATA_DIR}${NC} - ${GREEN}(não existe)${NC}"
    fi
    
    echo ""
    
    if [ -d "$RABBIT_LOGS_DIR" ]; then
        LOGS_SIZE=$(get_dir_size "$RABBIT_LOGS_DIR")
        LOG_COUNT=$(find "$RABBIT_LOGS_DIR" -type f 2>/dev/null | wc -l)
        echo -e "  📁 ${CYAN}${RABBIT_LOGS_DIR}${NC}"
        echo -e "     Tamanho: ${YELLOW}${LOGS_SIZE}${NC}"
        echo -e "     Arquivos: ${YELLOW}${LOG_COUNT}${NC}"
    else
        echo -e "  📁 ${CYAN}${RABBIT_LOGS_DIR}${NC} - ${GREEN}(não existe)${NC}"
    fi
    
    echo ""
    
    if [ -f "$DEFINITIONS_FILE" ]; then
        DEF_SIZE=$(du -sh "$DEFINITIONS_FILE" 2>/dev/null | cut -f1)
        echo -e "  📄 ${CYAN}${DEFINITIONS_FILE}${NC}"
        echo -e "     Tamanho: ${YELLOW}${DEF_SIZE}${NC}"
    else
        echo -e "  📄 ${CYAN}${DEFINITIONS_FILE}${NC} - ${GREEN}(não existe)${NC}"
    fi
    
    echo ""
}

# Função para confirmar exclusão
confirm_deletion() {
    print_header "⚠️  AVISO CRÍTICO - OPERAÇÃO DESTRUTIVA"
    
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                                              ║${NC}"
    echo -e "${RED}║  🚨 ATENÇÃO: TODOS OS REGISTROS SERÃO APAGADOS! 🚨                          ║${NC}"
    echo -e "${RED}║                                                                              ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Esta operação irá:${NC}"
    echo -e "  ❌ Apagar ${RED}TODOS${NC} os dados do RabbitMQ (filas, mensagens, exchanges, bindings)"
    echo -e "  ❌ Apagar ${RED}TODOS${NC} os logs do RabbitMQ"
    echo -e "  ❌ Remover ${RED}TODAS${NC} as configurações persistentes"
    echo ""
    echo -e "${YELLOW}Esta operação ${RED}NÃO PODE${NC} ser desfeita!${NC}"
    echo ""
    echo -e "${YELLOW}Após esta operação, você precisará:${NC}"
    echo -e "  • Recriar todas as filas, exchanges e bindings"
    echo -e "  • Reconfigurar usuários e permissões (ou usar generate_definitions.sh)"
    echo -e "  • Reiniciar o RabbitMQ do zero"
    echo ""
    
    show_data_info
    
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}Você tem CERTEZA ABSOLUTA que deseja continuar?${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Digite ${RED}'APAGAR TUDO'${YELLOW} (exatamente assim) para confirmar:${NC}"
    read -r CONFIRMATION
    
    if [ "$CONFIRMATION" != "APAGAR TUDO" ]; then
        log_info "Operação cancelada. Confirmação não correspondeu."
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Última confirmação: Digite ${RED}'SIM'${YELLOW} para continuar:${NC}"
    read -r FINAL_CONFIRM
    
    if [ "$FINAL_CONFIRM" != "SIM" ]; then
        log_info "Operação cancelada."
        exit 0
    fi
}

# Função para perguntar sobre definitions.json
confirm_definitions_deletion() {
    if [ -f "$DEFINITIONS_FILE" ]; then
        echo ""
        log_warning "O arquivo definitions.json existe."
        read -p "Deseja também apagar o definitions.json? (s/N): " -r DELETE_DEFINITIONS
        echo ""
        
        if [[ "$DELETE_DEFINITIONS" =~ ^[Ss]$ ]]; then
            return 0  # true - apagar
        else
            return 1  # false - manter
        fi
    fi
    return 1  # false - não existe, não precisa apagar
}

# Função para limpar diretório
clean_directory() {
    local dir="$1"
    local dir_name="$2"
    
    if [ ! -d "$dir" ]; then
        log_info "${dir_name} não existe. Criando diretório vazio..."
        mkdir -p "$dir"
        return
    fi
    
    log "Limpando ${dir_name}..."
    
    # Contar arquivos antes
    FILE_COUNT=$(find "$dir" -type f 2>/dev/null | wc -l)
    
    if [ "$FILE_COUNT" -eq 0 ]; then
        log_info "${dir_name} já está vazio."
        return
    fi
    
    # Remover todo o conteúdo, mas manter o diretório
    find "$dir" -mindepth 1 -delete 2>/dev/null || {
        # Se find falhar, tentar rm -rf
        rm -rf "${dir}"/* "${dir}"/.* 2>/dev/null || true
    }
    
    log_success "${dir_name} limpo (${FILE_COUNT} arquivo(s) removido(s))"
}

# Função para apagar definitions.json
delete_definitions() {
    if [ -f "$DEFINITIONS_FILE" ]; then
        log "Removendo definitions.json..."
        rm -f "$DEFINITIONS_FILE"
        log_success "definitions.json removido"
    fi
}

# Função principal de limpeza
perform_cleanup() {
    print_header "🧹 Limpando Dados do RabbitMQ"
    
    echo ""
    
    # Limpar rabbit_data
    clean_directory "$RABBIT_DATA_DIR" "rabbit_data"
    
    # Limpar rabbit_logs
    clean_directory "$RABBIT_LOGS_DIR" "rabbit_logs"
    
    # Perguntar sobre definitions.json
    if confirm_definitions_deletion; then
        delete_definitions
    else
        log_info "definitions.json será mantido"
    fi
    
    echo ""
    log_success "Limpeza concluída!"
}

# Função para exibir informações finais
show_final_info() {
    print_header "✅ Concluído!"
    
    echo ""
    log_success "Todos os dados do RabbitMQ foram apagados!"
    echo ""
    echo -e "${GREEN}📋 Status Final:${NC}"
    echo -e "  📁 ${CYAN}rabbit_data/${NC} - ${GREEN}LIMPO${NC}"
    echo -e "  📁 ${CYAN}rabbit_logs/${NC} - ${GREEN}LIMPO${NC}"
    if [ -f "$DEFINITIONS_FILE" ]; then
        echo -e "  📄 ${CYAN}definitions.json${NC} - ${GREEN}MANTIDO${NC}"
    else
        echo -e "  📄 ${CYAN}definitions.json${NC} - ${YELLOW}REMOVIDO${NC}"
    fi
    echo ""
    echo -e "${GREEN}🔧 Próximos Passos:${NC}"
    echo -e "  1. Configure o RabbitMQ novamente:"
    echo -e "     ${BLUE}./generate_definitions.sh${NC}"
    echo -e "  2. Inicie o RabbitMQ:"
    echo -e "     ${BLUE}./start_stack.sh${NC}"
    echo ""
    log_warning "⚠️  Lembre-se: Todas as filas, exchanges e mensagens foram perdidas!"
    echo ""
}

# Função principal
main() {
    print_header "🗑️  Apagar Dados do RabbitMQ"
    
    echo ""
    
    # Verificações iniciais
    check_docker
    check_rabbitmq_running
    
    # Confirmar exclusão
    confirm_deletion
    
    # Realizar limpeza
    perform_cleanup
    
    # Exibir informações finais
    show_final_info
}

# Executar função principal
main "$@"

