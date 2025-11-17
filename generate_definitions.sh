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
QUEUES_VHOST=()
QUEUES_DLX=()
EXCHANGES=()
EXCHANGES_VHOST=()
VHOSTS=()

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
    
    # Perguntar o virtualhost
    read -p "  Virtualhost para a fila '$QUEUE_NAME' [/]: " QUEUE_VHOST
    QUEUE_VHOST=${QUEUE_VHOST:-/}
    
    # Validar nome do vhost
    if [[ ! "$QUEUE_VHOST" =~ ^[a-zA-Z0-9/._-]+$ ]]; then
        print_error "Virtualhost inválido! Use apenas letras, números, barras, pontos, hífens e underscores."
        QUEUE_COUNT=$((QUEUE_COUNT - 1))
        continue
    fi
    
    QUEUES+=("$QUEUE_NAME")
    QUEUES_VHOST+=("$QUEUE_VHOST")
    
    # Adicionar vhost à lista de vhosts únicos
    if [[ ! " ${VHOSTS[@]} " =~ " ${QUEUE_VHOST} " ]]; then
        VHOSTS+=("$QUEUE_VHOST")
    fi
    
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
    
    # Verificar se a exchange já foi adicionada para este vhost
    EXCHANGE_KEY="${EXCHANGE_NAME}@${QUEUE_VHOST}"
    if [[ ! " ${EXCHANGES[@]} " =~ " ${EXCHANGE_KEY} " ]]; then
        EXCHANGES+=("$EXCHANGE_KEY")
        EXCHANGES_VHOST+=("$QUEUE_VHOST")
    fi
done

if [ ${#QUEUES[@]} -eq 0 ]; then
    print_error "Nenhuma fila foi informada. Operação cancelada."
    exit 1
fi

# Garantir que o vhost padrão "/" esteja sempre na lista
if [[ ! " ${VHOSTS[@]} " =~ " / " ]]; then
    VHOSTS+=("/")
fi

# Adicionar DLX exchange para cada vhost que tiver filas com DLX
if [ ${#QUEUES_DLX[@]} -gt 0 ]; then
    for i in "${!QUEUES[@]}"; do
        QUEUE="${QUEUES[$i]}"
        if [[ " ${QUEUES_DLX[@]} " =~ " ${QUEUE} " ]]; then
            QUEUE_VHOST="${QUEUES_VHOST[$i]}"
            DLX_KEY="dlx_exchange@${QUEUE_VHOST}"
            if [[ ! " ${EXCHANGES[@]} " =~ " ${DLX_KEY} " ]]; then
                EXCHANGES+=("$DLX_KEY")
                EXCHANGES_VHOST+=("$QUEUE_VHOST")
            fi
        fi
    done
fi

# =============================================================================
# Resumo da configuração
# =============================================================================
print_header "📋 Resumo da Configuração"

echo ""
echo "  👤 Usuário: ${CYAN}${ADMIN_USER}${NC}"
echo "  📬 Filas: ${CYAN}${#QUEUES[@]}${NC}"
for i in "${!QUEUES[@]}"; do
    QUEUE="${QUEUES[$i]}"
    QUEUE_VHOST="${QUEUES_VHOST[$i]}"
    if [[ " ${QUEUES_DLX[@]} " =~ " ${QUEUE} " ]]; then
        echo "    • ${QUEUE} @ ${CYAN}${QUEUE_VHOST}${NC} ${GREEN}(com Dead Letter)${NC}"
    else
        echo "    • ${QUEUE} @ ${CYAN}${QUEUE_VHOST}${NC}"
    fi
done
echo "  🔄 Exchanges: ${CYAN}${#EXCHANGES[@]}${NC}"
for i in "${!EXCHANGES[@]}"; do
    EXCHANGE_KEY="${EXCHANGES[$i]}"
    EXCHANGE_VHOST="${EXCHANGES_VHOST[$i]}"
    EXCHANGE_NAME=$(echo "$EXCHANGE_KEY" | cut -d'@' -f1)
    echo "    • $EXCHANGE_NAME @ ${CYAN}${EXCHANGE_VHOST}${NC}"
done
echo "  🌐 Virtualhosts: ${CYAN}${#VHOSTS[@]}${NC}"
for vhost in "${VHOSTS[@]}"; do
    echo "    • $vhost"
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
JSON+="\n  \"vhosts\": ["
for i in "${!VHOSTS[@]}"; do
    VHOST="${VHOSTS[$i]}"
    JSON+="\n    { \"name\": \"${VHOST}\" }"
    if [ $i -lt $((${#VHOSTS[@]} - 1)) ]; then
        JSON+=","
    fi
done
JSON+="\n  ],"

# Permissions
JSON+="\n  \"permissions\": ["
for i in "${!VHOSTS[@]}"; do
    VHOST="${VHOSTS[$i]}"
    JSON+="\n    {"
    JSON+="\n      \"user\": \"${ADMIN_USER}\","
    JSON+="\n      \"vhost\": \"${VHOST}\","
    JSON+="\n      \"configure\": \".*\","
    JSON+="\n      \"write\": \".*\","
    JSON+="\n      \"read\": \".*\""
    JSON+="\n    }"
    if [ $i -lt $((${#VHOSTS[@]} - 1)) ]; then
        JSON+=","
    fi
done
JSON+="\n  ],"

# Exchanges
JSON+="\n  \"exchanges\": ["
for i in "${!EXCHANGES[@]}"; do
    EXCHANGE_KEY="${EXCHANGES[$i]}"
    EXCHANGE_NAME=$(echo "$EXCHANGE_KEY" | cut -d'@' -f1)
    EXCHANGE_VHOST="${EXCHANGES_VHOST[$i]}"
    
    if [ "$EXCHANGE_NAME" = "dlx_exchange" ]; then
        EXCHANGE_TYPE="fanout"
    else
        EXCHANGE_TYPE="direct"
    fi
    
    JSON+="\n    {"
    JSON+="\n      \"name\": \"${EXCHANGE_NAME}\","
    JSON+="\n      \"vhost\": \"${EXCHANGE_VHOST}\","
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
    QUEUE_VHOST="${QUEUES_VHOST[$i]}"
    
    JSON+="\n    {"
    JSON+="\n      \"name\": \"${QUEUE}\","
    JSON+="\n      \"vhost\": \"${QUEUE_VHOST}\","
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
        # Encontrar o índice da fila no array principal para obter o vhost
        for j in "${!QUEUES[@]}"; do
            if [ "${QUEUES[$j]}" = "$QUEUE" ]; then
                QUEUE_VHOST="${QUEUES_VHOST[$j]}"
                break
            fi
        done
        DEAD_QUEUE="${QUEUE}.dead"
        
        JSON+="\n    {"
        JSON+="\n      \"name\": \"${DEAD_QUEUE}\","
        JSON+="\n      \"vhost\": \"${QUEUE_VHOST}\","
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
for i in "${!QUEUES[@]}"; do
    QUEUE="${QUEUES[$i]}"
    QUEUE_VHOST="${QUEUES_VHOST[$i]}"
    EXCHANGE_NAME=$(echo "$QUEUE" | cut -d'.' -f1 | sed 's/-/_/g')"_exchange"
    
    if [ $BINDING_COUNT -gt 0 ]; then
        JSON+=","
    fi
    
    JSON+="\n    {"
    JSON+="\n      \"source\": \"${EXCHANGE_NAME}\","
    JSON+="\n      \"vhost\": \"${QUEUE_VHOST}\","
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
        # Encontrar o índice da fila no array principal para obter o vhost
        for j in "${!QUEUES[@]}"; do
            if [ "${QUEUES[$j]}" = "$QUEUE" ]; then
                QUEUE_VHOST="${QUEUES_VHOST[$j]}"
                break
            fi
        done
        DEAD_QUEUE="${QUEUE}.dead"
        
        JSON+=","
        JSON+="\n    {"
        JSON+="\n      \"source\": \"dlx_exchange\","
        JSON+="\n      \"vhost\": \"${QUEUE_VHOST}\","
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
    # Coletar vhosts únicos que têm filas com DLX
    DLX_VHOSTS=()
    for QUEUE in "${QUEUES_DLX[@]}"; do
        for j in "${!QUEUES[@]}"; do
            if [ "${QUEUES[$j]}" = "$QUEUE" ]; then
                QUEUE_VHOST="${QUEUES_VHOST[$j]}"
                if [[ ! " ${DLX_VHOSTS[@]} " =~ " ${QUEUE_VHOST} " ]]; then
                    DLX_VHOSTS+=("$QUEUE_VHOST")
                fi
                break
            fi
        done
    done
    
    JSON+="\n  \"policies\": ["
    for i in "${!DLX_VHOSTS[@]}"; do
        DLX_VHOST="${DLX_VHOSTS[$i]}"
        JSON+="\n    {"
        JSON+="\n      \"vhost\": \"${DLX_VHOST}\","
        JSON+="\n      \"name\": \"DLX-policy\","
        JSON+="\n      \"pattern\": \".*\","
        JSON+="\n      \"definition\": {"
        JSON+="\n        \"dead-letter-exchange\": \"dlx_exchange\""
        JSON+="\n      },"
        JSON+="\n      \"priority\": 0,"
        JSON+="\n      \"apply-to\": \"queues\""
        JSON+="\n    }"
        if [ $i -lt $((${#DLX_VHOSTS[@]} - 1)) ]; then
            JSON+=","
        fi
    done
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

