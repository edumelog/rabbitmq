#!/bin/bash

# =============================================================================
# generate_definitions.sh - Gerador Interativo de definitions.json
# =============================================================================
# Este script cria um arquivo definitions.json personalizado para o RabbitMQ
# através de perguntas interativas ao usuário.
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Funções de log
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Verificar se estamos no diretório correto
if [ ! -f "docker-compose.yml" ]; then
    print_error "docker-compose.yml não encontrado!"
    print_error "Execute este script na raiz do projeto RabbitMQ"
    exit 1
fi

# Criar diretório se não existir
mkdir -p rabbit_definitions

DEFINITIONS_FILE="rabbit_definitions/definitions.json"

# =============================================================================
# Explicação sobre definitions.json
# =============================================================================
print_header "🐰 Gerador de definitions.json para RabbitMQ"
echo ""
print_info "O que é definitions.json?"
echo ""
echo "  O arquivo definitions.json é usado pelo RabbitMQ para pré-configurar:"
echo "  • Usuários e suas credenciais"
echo "  • Exchanges (roteadores de mensagens)"
echo "  • Filas (armazenamento de mensagens)"
echo "  • Bindings (vinculações entre exchanges e filas)"
echo "  • Políticas (regras globais como Dead Letter Exchange)"
echo ""
echo "  Este arquivo é carregado automaticamente quando o RabbitMQ inicia,"
echo "  permitindo que você tenha uma configuração inicial pronta."
echo ""
print_warning "⚠️  ATENÇÃO: O arquivo gerado substituirá o definitions.json existente!"
echo ""

# Perguntar se deseja criar definitions.json
read -p "Deseja criar/atualizar o definitions.json? (s/N): " -r CREATE_DEFINITIONS
echo ""

if [[ ! "$CREATE_DEFINITIONS" =~ ^[Ss]$ ]]; then
    print_info "Operação cancelada pelo usuário."
    exit 0
fi

# =============================================================================
# Coletar informações do usuário
# =============================================================================
print_header "📝 Configuração do Usuário Administrador"

read -p "Nome do usuário administrador [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -sp "Senha do usuário administrador: " ADMIN_PASSWORD
echo ""
if [ -z "$ADMIN_PASSWORD" ]; then
    print_error "A senha não pode estar vazia!"
    exit 1
fi

# =============================================================================
# Coletar informações das filas
# =============================================================================
print_header "📬 Configuração das Filas"

echo ""
print_info "Você pode criar múltiplas filas. Digite o nome de cada fila."
print_info "Pressione Enter sem digitar nada para finalizar."
echo ""

QUEUES=()
QUEUES_DLX=()
EXCHANGES=()

QUEUE_COUNT=0

while true; do
    QUEUE_COUNT=$((QUEUE_COUNT + 1))
    echo ""
    read -p "Nome da fila #${QUEUE_COUNT} (ou Enter para finalizar): " QUEUE_NAME
    
    if [ -z "$QUEUE_NAME" ]; then
        break
    fi
    
    # Validar nome da fila (sem espaços, caracteres especiais problemáticos)
    if [[ ! "$QUEUE_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        print_error "Nome inválido! Use apenas letras, números, pontos, hífens e underscores."
        QUEUE_COUNT=$((QUEUE_COUNT - 1))
        continue
    fi
    
    QUEUES+=("$QUEUE_NAME")
    
    # Perguntar sobre Dead Letter
    read -p "  Esta fila deve ter tratamento de Dead Letter? (s/N): " -r USE_DLX
    if [[ "$USE_DLX" =~ ^[Ss]$ ]]; then
        QUEUES_DLX+=("$QUEUE_NAME")
        print_success "  ✓ Dead Letter configurado para '$QUEUE_NAME'"
    else
        print_info "  Dead Letter não será configurado para '$QUEUE_NAME'"
    fi
    
    # Detectar exchange baseado no nome da fila
    # Exemplo: ocr.jobs -> ocr_exchange, elastic.status -> elastic_exchange
    EXCHANGE_NAME=$(echo "$QUEUE_NAME" | cut -d'.' -f1 | sed 's/-/_/g')"_exchange"
    
    # Verificar se a exchange já foi adicionada
    if [[ ! " ${EXCHANGES[@]} " =~ " ${EXCHANGE_NAME} " ]]; then
        EXCHANGES+=("$EXCHANGE_NAME")
    fi
done

if [ ${#QUEUES[@]} -eq 0 ]; then
    print_error "Nenhuma fila foi informada. Operação cancelada."
    exit 1
fi

# Adicionar DLX exchange se houver filas com DLX
if [ ${#QUEUES_DLX[@]} -gt 0 ]; then
    if [[ ! " ${EXCHANGES[@]} " =~ " dlx_exchange " ]]; then
        EXCHANGES+=("dlx_exchange")
    fi
fi

# =============================================================================
# Resumo da configuração
# =============================================================================
print_header "📋 Resumo da Configuração"

echo ""
echo "  👤 Usuário: ${CYAN}${ADMIN_USER}${NC}"
echo "  📬 Filas: ${CYAN}${#QUEUES[@]}${NC}"
for queue in "${QUEUES[@]}"; do
    if [[ " ${QUEUES_DLX[@]} " =~ " ${queue} " ]]; then
        echo "    • $queue ${GREEN}(com Dead Letter)${NC}"
    else
        echo "    • $queue"
    fi
done
echo "  🔄 Exchanges: ${CYAN}${#EXCHANGES[@]}${NC}"
for exchange in "${EXCHANGES[@]}"; do
    echo "    • $exchange"
done
echo ""

read -p "Confirma a criação do definitions.json com essas configurações? (s/N): " -r CONFIRM
echo ""

if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
    print_info "Operação cancelada pelo usuário."
    exit 0
fi

# =============================================================================
# Gerar o arquivo JSON
# =============================================================================
print_header "🔨 Gerando definitions.json"

# Criar backup se arquivo existir
if [ -f "$DEFINITIONS_FILE" ]; then
    BACKUP_FILE="${DEFINITIONS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$DEFINITIONS_FILE" "$BACKUP_FILE"
    print_info "Backup criado: $BACKUP_FILE"
fi

# Iniciar JSON
JSON="{"

# Users
JSON+="\n  \"users\": [\n    {\n      \"name\": \"${ADMIN_USER}\",\n      \"password\": \"${ADMIN_PASSWORD}\",\n      \"tags\": \"administrator\"\n    }\n  ],"

# Vhosts
JSON+="\n  \"vhosts\": [\n    { \"name\": \"/\" }\n  ],"

# Permissions
JSON+="\n  \"permissions\": [\n    {\n      \"user\": \"${ADMIN_USER}\",\n      \"vhost\": \"/\",\n      \"configure\": \".*\",\n      \"write\": \".*\",\n      \"read\": \".*\"\n    }\n  ],"

# Exchanges
JSON+="\n  \"exchanges\": ["
for i in "${!EXCHANGES[@]}"; do
    EXCHANGE="${EXCHANGES[$i]}"
    if [ "$EXCHANGE" = "dlx_exchange" ]; then
        EXCHANGE_TYPE="fanout"
    else
        EXCHANGE_TYPE="direct"
    fi
    
    JSON+="\n    {"
    JSON+="\n      \"name\": \"${EXCHANGE}\","
    JSON+="\n      \"vhost\": \"/\","
    JSON+="\n      \"type\": \"${EXCHANGE_TYPE}\","
    JSON+="\n      \"durable\": true,"
    JSON+="\n      \"auto_delete\": false,"
    JSON+="\n      \"internal\": false,"
    JSON+="\n      \"arguments\": {}"
    JSON+="\n    }"
    
    if [ $i -lt $((${#EXCHANGES[@]} - 1)) ]; then
        JSON+=","
    fi
done
JSON+="\n  ],"

# Queues
JSON+="\n  \"queues\": ["
for i in "${!QUEUES[@]}"; do
    QUEUE="${QUEUES[$i]}"
    
    JSON+="\n    {"
    JSON+="\n      \"name\": \"${QUEUE}\","
    JSON+="\n      \"vhost\": \"/\","
    JSON+="\n      \"durable\": true,"
    JSON+="\n      \"auto_delete\": false,"
    
    # Adicionar DLX se configurado
    if [[ " ${QUEUES_DLX[@]} " =~ " ${QUEUE} " ]]; then
        JSON+="\n      \"arguments\": {"
        JSON+="\n        \"x-dead-letter-exchange\": \"dlx_exchange\""
        JSON+="\n      }"
    else
        JSON+="\n      \"arguments\": {}"
    fi
    
    JSON+="\n    }"
    
    if [ $i -lt $((${#QUEUES[@]} - 1)) ]; then
        JSON+=","
    fi
done

# Adicionar filas dead se houver DLX
if [ ${#QUEUES_DLX[@]} -gt 0 ]; then
    JSON+=","
    for i in "${!QUEUES_DLX[@]}"; do
        QUEUE="${QUEUES_DLX[$i]}"
        DEAD_QUEUE="${QUEUE}.dead"
        
        JSON+="\n    {"
        JSON+="\n      \"name\": \"${DEAD_QUEUE}\","
        JSON+="\n      \"vhost\": \"/\","
        JSON+="\n      \"durable\": true,"
        JSON+="\n      \"auto_delete\": false,"
        JSON+="\n      \"arguments\": {}"
        JSON+="\n    }"
        
        if [ $i -lt $((${#QUEUES_DLX[@]} - 1)) ]; then
            JSON+=","
        fi
    done
fi
JSON+="\n  ],"

# Bindings
JSON+="\n  \"bindings\": ["
BINDING_COUNT=0

# Bindings das filas principais para suas exchanges
for QUEUE in "${QUEUES[@]}"; do
    EXCHANGE_NAME=$(echo "$QUEUE" | cut -d'.' -f1 | sed 's/-/_/g')"_exchange"
    
    if [ $BINDING_COUNT -gt 0 ]; then
        JSON+=","
    fi
    
    JSON+="\n    {"
    JSON+="\n      \"source\": \"${EXCHANGE_NAME}\","
    JSON+="\n      \"vhost\": \"/\","
    JSON+="\n      \"destination\": \"${QUEUE}\","
    JSON+="\n      \"destination_type\": \"queue\","
    JSON+="\n      \"routing_key\": \"${QUEUE}\","
    JSON+="\n      \"arguments\": {}"
    JSON+="\n    }"
    
    BINDING_COUNT=$((BINDING_COUNT + 1))
done

# Bindings das filas dead para dlx_exchange
if [ ${#QUEUES_DLX[@]} -gt 0 ]; then
    for QUEUE in "${QUEUES_DLX[@]}"; do
        DEAD_QUEUE="${QUEUE}.dead"
        
        JSON+=","
        JSON+="\n    {"
        JSON+="\n      \"source\": \"dlx_exchange\","
        JSON+="\n      \"vhost\": \"/\","
        JSON+="\n      \"destination\": \"${DEAD_QUEUE}\","
        JSON+="\n      \"destination_type\": \"queue\","
        JSON+="\n      \"routing_key\": \"\","
        JSON+="\n      \"arguments\": {}"
        JSON+="\n    }"
    done
fi
JSON+="\n  ],"

# Policies (DLX policy se houver filas com DLX)
if [ ${#QUEUES_DLX[@]} -gt 0 ]; then
    JSON+="\n  \"policies\": ["
    JSON+="\n    {"
    JSON+="\n      \"vhost\": \"/\","
    JSON+="\n      \"name\": \"DLX-policy\","
    JSON+="\n      \"pattern\": \".*\","
    JSON+="\n      \"definition\": {"
    JSON+="\n        \"dead-letter-exchange\": \"dlx_exchange\""
    JSON+="\n      },"
    JSON+="\n      \"priority\": 0,"
    JSON+="\n      \"apply-to\": \"queues\""
    JSON+="\n    }"
    JSON+="\n  ]"
else
    JSON+="\n  \"policies\": []"
fi

JSON+="\n}"

# Escrever arquivo
echo -e "$JSON" > "$DEFINITIONS_FILE"

# Validar JSON
if command -v python3 &> /dev/null; then
    if python3 -m json.tool "$DEFINITIONS_FILE" > /dev/null 2>&1; then
        print_success "JSON válido gerado com sucesso!"
    else
        print_error "Erro ao validar JSON! Verifique o arquivo gerado."
        exit 1
    fi
else
    print_warning "Python3 não encontrado. Não foi possível validar o JSON."
    print_info "Valide manualmente em: https://jsonlint.com/"
fi

# =============================================================================
# Finalização
# =============================================================================
print_header "✅ Concluído!"

echo ""
print_success "Arquivo gerado: ${DEFINITIONS_FILE}"
echo ""
print_info "Próximos passos:"
echo "  1. Revise o arquivo gerado: cat ${DEFINITIONS_FILE}"
echo "  2. Reinicie a stack para aplicar as mudanças:"
echo "     ./stop_stack.sh"
echo "     ./start_stack.sh"
echo ""
print_info "Ou recarregue as definições sem reiniciar:"
echo "  docker exec -it \$(docker ps -q -f name=rabbitmq) rabbitmqctl load_definitions /etc/rabbitmq/definitions.json"
echo ""

