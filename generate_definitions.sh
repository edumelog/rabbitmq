#!/bin/bash

# =============================================================================
# generate_definitions.sh - Gerenciador de Filas e Virtualhosts do RabbitMQ
# =============================================================================
# Este script permite gerenciar filas, virtualhosts, exchanges, bindings
# e políticas no definitions.json de forma não destrutiva, preservando
# usuários e outras configurações existentes.
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

# Verificar se Python está disponível
if ! command -v python3 &> /dev/null; then
    print_error "Python3 não está instalado!"
    print_error "Este script requer Python3 para manipular JSON de forma segura."
    exit 1
fi

# =============================================================================
# Script Python para manipular JSON
# =============================================================================
PYTHON_SCRIPT=$(cat << 'PYTHON_EOF'
import json
import sys
import os
import re

def load_definitions(filepath):
    """Carrega o definitions.json"""
    if not os.path.exists(filepath):
        return {
            "users": [],
            "vhosts": [{"name": "/"}],
            "permissions": [],
            "exchanges": [],
            "queues": [],
            "bindings": [],
            "policies": []
        }
    
    with open(filepath, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_definitions(filepath, data):
    """Salva o definitions.json com formatação"""
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    with open(filepath, 'a', encoding='utf-8') as f:
        f.write('\n')

# =============================================================================
# Funções para Virtualhosts
# =============================================================================

def list_vhosts(data):
    """Lista todos os virtualhosts"""
    vhosts = data.get("vhosts", [])
    if not vhosts:
        print("Nenhum virtualhost encontrado.")
        return []
    
    print("\nVirtualhosts existentes:")
    for i, vhost in enumerate(vhosts, 1):
        name = vhost.get("name", "/")
        print(f"  {i}. {name}")
    
    return [v.get("name", "/") for v in vhosts]

def add_vhost(data, vhost_name):
    """Adiciona um novo virtualhost"""
    vhosts = data.get("vhosts", [])
    
    # Verificar se já existe
    if any(v.get("name") == vhost_name for v in vhosts):
        print(f"ERRO: Virtualhost '{vhost_name}' já existe!")
        return False
    
    vhosts.append({"name": vhost_name})
    data["vhosts"] = vhosts
    return True

def remove_vhost(data, vhost_name):
    """Remove um virtualhost e todas as suas configurações"""
    vhosts = data.get("vhosts", [])
    queues = data.get("queues", [])
    exchanges = data.get("exchanges", [])
    bindings = data.get("bindings", [])
    permissions = data.get("permissions", [])
    policies = data.get("policies", [])
    
    # Não permitir remover o vhost padrão
    if vhost_name == "/":
        print("ERRO: Não é possível remover o virtualhost padrão '/'!")
        return False
    
    # Remover vhost
    original_count = len(vhosts)
    data["vhosts"] = [v for v in vhosts if v.get("name") != vhost_name]
    
    if len(data["vhosts"]) == original_count:
        print(f"ERRO: Virtualhost '{vhost_name}' não encontrado!")
        return False
    
    # Remover queues do vhost
    data["queues"] = [q for q in queues if q.get("vhost") != vhost_name]
    
    # Remover exchanges do vhost
    data["exchanges"] = [e for e in exchanges if e.get("vhost") != vhost_name]
    
    # Remover bindings do vhost
    data["bindings"] = [b for b in bindings if b.get("vhost") != vhost_name]
    
    # Remover permissions do vhost
    data["permissions"] = [p for p in permissions if p.get("vhost") != vhost_name]
    
    # Remover policies do vhost
    data["policies"] = [p for p in policies if p.get("vhost") != vhost_name]
    
    return True

# =============================================================================
# Funções para Filas
# =============================================================================

def list_queues(data):
    """Lista todas as filas"""
    queues = data.get("queues", [])
    if not queues:
        print("Nenhuma fila encontrada.")
        return []
    
    print("\nFilas existentes:")
    for i, queue in enumerate(queues, 1):
        name = queue.get("name", "N/A")
        vhost = queue.get("vhost", "/")
        has_dlx = "x-dead-letter-exchange" in queue.get("arguments", {})
        dlx_mark = " (com DLX)" if has_dlx else ""
        print(f"  {i}. {name} @ {vhost}{dlx_mark}")
    
    return queues

def get_queue(data, queue_name, vhost):
    """Obtém uma fila pelo nome e vhost"""
    queues = data.get("queues", [])
    for queue in queues:
        if queue.get("name") == queue_name and queue.get("vhost") == vhost:
            return queue
    return None

def add_queue(data, queue_name, vhost, use_dlx=False, dlx_exchange="dlx_exchange"):
    """Adiciona uma nova fila"""
    queues = data.get("queues", [])
    
    # Verificar se já existe
    if any(q.get("name") == queue_name and q.get("vhost") == vhost for q in queues):
        print(f"ERRO: Fila '{queue_name}' já existe no vhost '{vhost}'!")
        return False
    
    # Criar fila
    queue_data = {
        "name": queue_name,
        "vhost": vhost,
        "durable": True,
        "auto_delete": False,
        "arguments": {}
    }
    
    if use_dlx:
        queue_data["arguments"]["x-dead-letter-exchange"] = dlx_exchange
    
    queues.append(queue_data)
    data["queues"] = queues
    
    # Criar exchange se não existir
    exchange_name = queue_name.split('.')[0].replace('-', '_') + "_exchange"
    ensure_exchange(data, exchange_name, vhost)
    
    # Criar binding
    create_binding(data, exchange_name, queue_name, vhost, queue_name)
    
    # Criar fila dead se usar DLX
    if use_dlx:
        dead_queue_name = f"{queue_name}.dead"
        # Verificar se fila dead já existe
        if not any(q.get("name") == dead_queue_name and q.get("vhost") == vhost for q in queues):
            dead_queue = {
                "name": dead_queue_name,
                "vhost": vhost,
                "durable": True,
                "auto_delete": False,
                "arguments": {}
            }
            queues.append(dead_queue)
            data["queues"] = queues
            
            # Criar binding para fila dead
            ensure_exchange(data, dlx_exchange, vhost, "fanout")
            create_binding(data, dlx_exchange, dead_queue_name, vhost, "")
    
    return True

def update_queue(data, queue_name, vhost, new_name=None, new_vhost=None, use_dlx=None, dlx_exchange="dlx_exchange"):
    """Atualiza uma fila existente"""
    queues = data.get("queues", [])
    
    queue = get_queue(data, queue_name, vhost)
    if not queue:
        print(f"ERRO: Fila '{queue_name}' não encontrada no vhost '{vhost}'!")
        return False
    
    # Normalizar valores None para strings vazias ou manter valores originais
    final_name = new_name if new_name and new_name != "None" else queue_name
    final_vhost = new_vhost if new_vhost and new_vhost != "None" else vhost
    
    # Atualizar nome se fornecido e diferente
    if new_name and new_name != "None" and new_name != queue_name:
        # Verificar se novo nome já existe (excluindo a fila atual)
        if any(q.get("name") == new_name and q.get("vhost") == final_vhost 
               for q in queues 
               if not (q.get("name") == queue_name and q.get("vhost") == vhost)):
            print(f"ERRO: Fila '{new_name}' já existe no vhost '{final_vhost}'!")
            return False
        
        queue["name"] = new_name
        # Atualizar bindings relacionados
        update_bindings_for_queue(data, queue_name, vhost, new_name, final_vhost)
    
    # Atualizar vhost se fornecido e diferente
    if new_vhost and new_vhost != "None" and new_vhost != vhost:
        queue["vhost"] = new_vhost
        # Atualizar bindings relacionados
        update_bindings_for_queue(data, final_name, vhost, final_name, new_vhost)
    
    # Atualizar DLX
    if use_dlx is not None and use_dlx != "None":
        if use_dlx == "true" or use_dlx is True:
            if "arguments" not in queue:
                queue["arguments"] = {}
            queue["arguments"]["x-dead-letter-exchange"] = dlx_exchange
            
            # Criar fila dead se não existir
            dead_queue_name = f"{final_name}.dead"
            if not any(q.get("name") == dead_queue_name and q.get("vhost") == final_vhost for q in queues):
                dead_queue = {
                    "name": dead_queue_name,
                    "vhost": final_vhost,
                    "durable": True,
                    "auto_delete": False,
                    "arguments": {}
                }
                queues.append(dead_queue)
                data["queues"] = queues
                
                # Criar exchange DLX se não existir
                ensure_exchange(data, dlx_exchange, final_vhost, "fanout")
                
                # Criar binding para fila dead
                create_binding(data, dlx_exchange, dead_queue_name, final_vhost, "")
        elif use_dlx == "false" or use_dlx is False:
            if "arguments" in queue:
                queue["arguments"].pop("x-dead-letter-exchange", None)
                if not queue["arguments"]:
                    queue["arguments"] = {}
            
            # Remover fila dead se existir
            dead_queue_name = f"{final_name}.dead"
            queues = data.get("queues", [])
            data["queues"] = [q for q in queues if not (q.get("name") == dead_queue_name and q.get("vhost") == final_vhost)]
            
            # Remover bindings da fila dead
            bindings = data.get("bindings", [])
            data["bindings"] = [b for b in bindings if not (b.get("destination") == dead_queue_name and b.get("vhost") == final_vhost)]
    
    return True

def remove_queue(data, queue_name, vhost):
    """Remove uma fila e seus bindings relacionados"""
    queues = data.get("queues", [])
    bindings = data.get("bindings", [])
    
    # Remover fila
    original_count = len(queues)
    data["queues"] = [q for q in queues if not (q.get("name") == queue_name and q.get("vhost") == vhost)]
    
    if len(data["queues"]) == original_count:
        print(f"ERRO: Fila '{queue_name}' não encontrada no vhost '{vhost}'!")
        return False
    
    # Remover fila dead se existir
    dead_queue_name = f"{queue_name}.dead"
    data["queues"] = [q for q in data["queues"] if not (q.get("name") == dead_queue_name and q.get("vhost") == vhost)]
    
    # Remover bindings relacionados
    data["bindings"] = [
        b for b in bindings 
        if not (b.get("destination") == queue_name and b.get("vhost") == vhost) and
           not (b.get("destination") == dead_queue_name and b.get("vhost") == vhost)
    ]
    
    return True

# =============================================================================
# Funções auxiliares para Exchanges e Bindings
# =============================================================================

def ensure_exchange(data, exchange_name, vhost, exchange_type="direct"):
    """Garante que uma exchange existe"""
    exchanges = data.get("exchanges", [])
    
    if any(e.get("name") == exchange_name and e.get("vhost") == vhost for e in exchanges):
        return True  # Já existe
    
    exchanges.append({
        "name": exchange_name,
        "vhost": vhost,
        "type": exchange_type,
        "durable": True,
        "auto_delete": False,
        "internal": False,
        "arguments": {}
    })
    data["exchanges"] = exchanges
    return True

def create_binding(data, exchange_name, queue_name, vhost, routing_key):
    """Cria um binding entre exchange e fila"""
    bindings = data.get("bindings", [])
    
    # Verificar se já existe
    if any(b.get("source") == exchange_name and 
           b.get("destination") == queue_name and 
           b.get("vhost") == vhost for b in bindings):
        return True  # Já existe
    
    bindings.append({
        "source": exchange_name,
        "vhost": vhost,
        "destination": queue_name,
        "destination_type": "queue",
        "routing_key": routing_key,
        "arguments": {}
    })
    data["bindings"] = bindings
    return True

def update_bindings_for_queue(data, old_queue_name, old_vhost, new_queue_name, new_vhost):
    """Atualiza bindings quando uma fila é renomeada ou movida"""
    bindings = data.get("bindings", [])
    
    for binding in bindings:
        if binding.get("destination") == old_queue_name and binding.get("vhost") == old_vhost:
            binding["destination"] = new_queue_name
            binding["vhost"] = new_vhost
            # Atualizar routing_key se for o nome da fila
            if binding.get("routing_key") == old_queue_name:
                binding["routing_key"] = new_queue_name
    
    data["bindings"] = bindings

# =============================================================================
# Execução de comandos
# =============================================================================

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("ERRO: Comando não especificado")
        sys.exit(1)
    
    command = sys.argv[1]
    filepath = sys.argv[2] if len(sys.argv) > 2 else "rabbit_definitions/definitions.json"
    
    data = load_definitions(filepath)
    
    if command == "list_vhosts":
        list_vhosts(data)
    
    elif command == "add_vhost":
        if len(sys.argv) < 4:
            print("ERRO: Uso: add_vhost <vhost_name>")
            sys.exit(1)
        vhost_name = sys.argv[3]
        if add_vhost(data, vhost_name):
            save_definitions(filepath, data)
            print(f"SUCCESS: Virtualhost '{vhost_name}' adicionado com sucesso!")
        else:
            sys.exit(1)
    
    elif command == "remove_vhost":
        if len(sys.argv) < 4:
            print("ERRO: Uso: remove_vhost <vhost_name>")
            sys.exit(1)
        vhost_name = sys.argv[3]
        if remove_vhost(data, vhost_name):
            save_definitions(filepath, data)
            print(f"SUCCESS: Virtualhost '{vhost_name}' removido com sucesso!")
        else:
            sys.exit(1)
    
    elif command == "list_queues":
        list_queues(data)
    
    elif command == "add_queue":
        if len(sys.argv) < 5:
            print("ERRO: Uso: add_queue <queue_name> <vhost> <use_dlx>")
            sys.exit(1)
        queue_name = sys.argv[3]
        vhost = sys.argv[4]
        use_dlx_str = sys.argv[5] if len(sys.argv) > 5 else "false"
        use_dlx = use_dlx_str.lower() == "true"
        if add_queue(data, queue_name, vhost, use_dlx):
            save_definitions(filepath, data)
            print(f"SUCCESS: Fila '{queue_name}' adicionada com sucesso!")
        else:
            sys.exit(1)
    
    elif command == "update_queue":
        if len(sys.argv) < 5:
            print("ERRO: Uso: update_queue <queue_name> <vhost> <new_name> <new_vhost> <use_dlx>")
            sys.exit(1)
        queue_name = sys.argv[3]
        vhost = sys.argv[4]
        new_name = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] != "None" else None
        new_vhost = sys.argv[6] if len(sys.argv) > 6 and sys.argv[6] != "None" else None
        use_dlx = sys.argv[7].lower() == "true" if len(sys.argv) > 7 and sys.argv[7] != "None" else None
        if update_queue(data, queue_name, vhost, new_name, new_vhost, use_dlx):
            save_definitions(filepath, data)
            print(f"SUCCESS: Fila '{queue_name}' atualizada com sucesso!")
        else:
            sys.exit(1)
    
    elif command == "remove_queue":
        if len(sys.argv) < 5:
            print("ERRO: Uso: remove_queue <queue_name> <vhost>")
            sys.exit(1)
        queue_name = sys.argv[3]
        vhost = sys.argv[4]
        if remove_queue(data, queue_name, vhost):
            save_definitions(filepath, data)
            print(f"SUCCESS: Fila '{queue_name}' removida com sucesso!")
        else:
            sys.exit(1)
    
    else:
        print(f"ERRO: Comando desconhecido: {command}")
        sys.exit(1)
PYTHON_EOF
)

# =============================================================================
# Funções auxiliares do script bash
# =============================================================================

# Executar comando Python
run_python() {
    echo "$PYTHON_SCRIPT" | python3 - "$@"
}

# Listar virtualhosts
list_vhosts_interactive() {
    print_header "🌐 Lista de Virtualhosts"
    echo ""
    run_python "list_vhosts" "$DEFINITIONS_FILE"
    echo ""
}

# Adicionar virtualhost
add_vhost_interactive() {
    print_header "➕ Adicionar Virtualhost"
echo ""
    print_info "Digite '.' (ponto) para voltar ao menu."
echo ""

    read -p "Nome do virtualhost (ou '.' para voltar): " VHOST_NAME
    if [ -z "$VHOST_NAME" ] || [ "$VHOST_NAME" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Validar nome
    if [[ ! "$VHOST_NAME" =~ ^[a-zA-Z0-9/._-]+$ ]]; then
        print_error "Nome inválido! Use apenas letras, números, barras, pontos, hífens e underscores."
        return 1
    fi
    
    if run_python "add_vhost" "$DEFINITIONS_FILE" "$VHOST_NAME"; then
        print_success "Virtualhost '$VHOST_NAME' adicionado com sucesso!"
        return 0
    else
        return 1
    fi
}

# Remover virtualhost
remove_vhost_interactive() {
    print_header "➖ Remover Virtualhost"
    echo ""
    
    list_vhosts_interactive
    
    echo ""
    read -p "Nome do virtualhost a remover (ou '.' para voltar): " VHOST_NAME
    if [ -z "$VHOST_NAME" ] || [ "$VHOST_NAME" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    if [ "$VHOST_NAME" = "/" ]; then
        print_error "Não é possível remover o virtualhost padrão '/'!"
        return 1
    fi
    
    print_warning "⚠️  Esta operação removerá:"
    print_warning "   - O virtualhost '$VHOST_NAME'"
    print_warning "   - Todas as filas neste virtualhost"
    print_warning "   - Todas as exchanges neste virtualhost"
    print_warning "   - Todos os bindings neste virtualhost"
    print_warning "   - Todas as permissões neste virtualhost"
    print_warning "   - Todas as políticas neste virtualhost"
    echo ""
    
    read -p "Confirma a remoção? (digite 'SIM' para confirmar ou '.' para voltar): " -r CONFIRM
    if [ "$CONFIRM" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    if [ "$CONFIRM" != "SIM" ]; then
        print_info "Operação cancelada."
        return 1
    fi
    
    if run_python "remove_vhost" "$DEFINITIONS_FILE" "$VHOST_NAME"; then
        print_success "Virtualhost '$VHOST_NAME' removido com sucesso!"
        return 0
    else
        return 1
    fi
}

# Selecionar virtualhost
select_vhost() {
    local prompt="$1"
    local default="$2"
    local selected_vhost=""
    
    VHOSTS=$(run_python "list_vhosts" "$DEFINITIONS_FILE" 2>/dev/null | grep -E "^\s*[0-9]+\." | sed 's/^[^.]*\. //' || echo "")
    
    if [ -z "$VHOSTS" ]; then
        print_warning "Nenhum virtualhost encontrado. Usando padrão '/'" >&2
        echo "/"
        return 0
    fi
    
    # Mostrar lista no stderr para não interferir no retorno
    echo "" >&2
    echo "Virtualhosts disponíveis:" >&2
    echo "$VHOSTS" | nl -w2 -s'. ' >&2
    echo "" >&2
    print_info "Digite '.' (ponto) para voltar ao menu anterior." >&2
    echo "" >&2
    
    # Ler do usuário (read sempre vai para o terminal, não precisa redirecionar)
    if [ -n "$default" ]; then
        read -p "${prompt} [${default}]: " SELECTED
        SELECTED=${SELECTED:-$default}
    else
        read -p "${prompt}: " SELECTED
    fi
    
    # Verificar se quer voltar
    if [ "$SELECTED" = "." ]; then
        echo "."
        return 1
    fi
    
    # Verificar se é um número (índice)
    if [[ "$SELECTED" =~ ^[0-9]+$ ]]; then
        SELECTED=$(echo "$VHOSTS" | sed -n "${SELECTED}p")
    fi
    
    # Validar se o vhost existe
    if echo "$VHOSTS" | grep -q "^${SELECTED}$"; then
        # Retornar apenas o vhost selecionado no stdout
        echo "$SELECTED"
        return 0
    else
        print_error "Virtualhost '$SELECTED' não encontrado!" >&2
        echo "" >&2
        return 1
    fi
}

# Listar filas
list_queues_interactive() {
    print_header "📬 Lista de Filas"
    echo ""
    run_python "list_queues" "$DEFINITIONS_FILE"
echo ""
}

# Adicionar fila
add_queue_interactive() {
    print_header "➕ Adicionar Nova Fila"
    echo ""
    print_info "Digite '.' (ponto) a qualquer momento para voltar ao menu."
echo ""

    read -p "Nome da fila (ou '.' para voltar): " QUEUE_NAME
    if [ -z "$QUEUE_NAME" ] || [ "$QUEUE_NAME" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Validar nome
    if [[ ! "$QUEUE_NAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        print_error "Nome inválido! Use apenas letras, números, pontos, hífens e underscores."
        return 1
    fi
    
    # Selecionar virtualhost
    echo ""
    VHOST=$(select_vhost "Virtualhost para a fila (ou '.' para voltar)" "/")
    if [ $? -ne 0 ] || [ -z "$VHOST" ] || [ "$VHOST" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    echo ""
    read -p "Esta fila deve ter tratamento de Dead Letter? (s/N/'.' para voltar): " -r USE_DLX
    if [ "$USE_DLX" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    USE_DLX_VAL="false"
    if [[ "$USE_DLX" =~ ^[Ss]$ ]]; then
        USE_DLX_VAL="true"
        print_success "Dead Letter será configurado para '$QUEUE_NAME'"
    fi
    
    echo ""
    print_info "Resumo da fila a ser criada:"
    echo "  Nome: $QUEUE_NAME"
    echo "  Virtualhost: $VHOST"
    echo "  Dead Letter: $([ "$USE_DLX_VAL" = "true" ] && echo "Sim" || echo "Não")"
    echo ""
    read -p "Confirma a criação da fila? (s/N/'.' para voltar): " -r CONFIRM
    if [ "$CONFIRM" = "." ] || [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
        if [ "$CONFIRM" = "." ]; then
            print_info "Voltando ao menu..."
        else
            print_info "Operação cancelada."
        fi
        return 0
    fi
    
    if run_python "add_queue" "$DEFINITIONS_FILE" "$QUEUE_NAME" "$VHOST" "$USE_DLX_VAL"; then
        print_success "Fila '$QUEUE_NAME' adicionada com sucesso no vhost '$VHOST'!"
        echo ""
        print_info "Verificando fila criada..."
        # Listar todas as filas e destacar a recém-criada
        QUEUES_OUTPUT=$(run_python "list_queues" "$DEFINITIONS_FILE" 2>/dev/null)
        echo "$QUEUES_OUTPUT"
        return 0
    else
        return 1
    fi
}

# Editar fila
edit_queue_interactive() {
    print_header "✏️  Editar Fila"
    echo ""
    print_info "Digite '.' (ponto) a qualquer momento para voltar ao menu."
    echo ""
    
    # Obter lista de filas
    QUEUES_LIST=$(run_python "list_queues" "$DEFINITIONS_FILE" 2>/dev/null)
    echo "$QUEUES_LIST"
    
    echo ""
    read -p "Número ou nome da fila a editar (ou '.' para voltar): " QUEUE_INPUT
    if [ -z "$QUEUE_INPUT" ] || [ "$QUEUE_INPUT" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Verificar se é um número (índice)
    if [[ "$QUEUE_INPUT" =~ ^[0-9]+$ ]]; then
        # Extrair nome da fila pelo índice
        QUEUE_INFO=$(echo "$QUEUES_LIST" | grep -E "^\s*${QUEUE_INPUT}\." | head -1)
        if [ -z "$QUEUE_INFO" ]; then
            print_error "Índice '$QUEUE_INPUT' não encontrado na lista!"
            return 1
        fi
        # Extrair nome da fila (tudo entre o número e o @, removendo espaços)
        QUEUE_NAME=$(echo "$QUEUE_INFO" | sed -E 's/^\s*[0-9]+\.\s+([^@]+)\s+@.*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
        QUEUE_NAME="$QUEUE_INPUT"
        # Obter vhost da fila pelo nome
        QUEUE_INFO=$(echo "$QUEUES_LIST" | grep -E "^\s*[0-9]+\. $QUEUE_NAME" | head -1)
    fi
    
    if [ -z "$QUEUE_INFO" ]; then
        print_error "Fila '$QUEUE_NAME' não encontrada!"
        return 1
    fi
    
    CURRENT_VHOST=$(echo "$QUEUE_INFO" | grep -oP '@ \K[^ ]+' || echo "/")
    
    echo ""
    print_info "Fila atual: $QUEUE_NAME @ $CURRENT_VHOST"
    echo ""
    
    read -p "Novo nome da fila (ou Enter para manter '$QUEUE_NAME', '.' para voltar): " NEW_NAME
    if [ "$NEW_NAME" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    # Se vazio ou igual ao nome atual, usar "None" para indicar que não deve alterar
    if [ -z "$NEW_NAME" ] || [ "$NEW_NAME" = "$QUEUE_NAME" ]; then
        NEW_NAME="None"
    fi
    
    # Selecionar novo vhost
    NEW_VHOST=$(select_vhost "Novo virtualhost (ou Enter para manter '$CURRENT_VHOST', '.' para voltar)" "$CURRENT_VHOST")
    if [ $? -ne 0 ] || [ -z "$NEW_VHOST" ] || [ "$NEW_VHOST" = "." ]; then
        if [ "$NEW_VHOST" = "." ]; then
            print_info "Voltando ao menu..."
            return 0
        fi
        NEW_VHOST="None"
    elif [ "$NEW_VHOST" = "$CURRENT_VHOST" ]; then
        NEW_VHOST="None"
    fi
    
    echo ""
    read -p "Esta fila deve ter tratamento de Dead Letter? (s/N/u para não alterar/'.' para voltar): " -r USE_DLX
    if [ "$USE_DLX" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    USE_DLX_VAL="None"
    if [[ "$USE_DLX" =~ ^[Ss]$ ]]; then
        USE_DLX_VAL="true"
    elif [[ "$USE_DLX" =~ ^[Nn]$ ]]; then
        USE_DLX_VAL="false"
    fi
    
    if run_python "update_queue" "$DEFINITIONS_FILE" "$QUEUE_NAME" "$CURRENT_VHOST" "$NEW_NAME" "$NEW_VHOST" "$USE_DLX_VAL"; then
        print_success "Fila atualizada com sucesso!"
        echo ""
        print_info "Verificando fila atualizada..."
        # Listar todas as filas para mostrar a atualização
        QUEUES_OUTPUT=$(run_python "list_queues" "$DEFINITIONS_FILE" 2>/dev/null)
        echo "$QUEUES_OUTPUT"
        return 0
    else
        return 1
    fi
}

# Remover fila
remove_queue_interactive() {
    print_header "➖ Remover Fila"
    echo ""
    print_info "Digite '.' (ponto) a qualquer momento para voltar ao menu."
    echo ""
    
    # Obter lista de filas
    QUEUES_LIST=$(run_python "list_queues" "$DEFINITIONS_FILE" 2>/dev/null)
    echo "$QUEUES_LIST"
    
    echo ""
    read -p "Número ou nome da fila a remover (ou '.' para voltar): " QUEUE_INPUT
    if [ -z "$QUEUE_INPUT" ] || [ "$QUEUE_INPUT" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Verificar se é um número (índice)
    if [[ "$QUEUE_INPUT" =~ ^[0-9]+$ ]]; then
        # Extrair nome da fila pelo índice
        QUEUE_INFO=$(echo "$QUEUES_LIST" | grep -E "^\s*${QUEUE_INPUT}\." | head -1)
        if [ -z "$QUEUE_INFO" ]; then
            print_error "Índice '$QUEUE_INPUT' não encontrado na lista!"
            return 1
        fi
        # Extrair nome da fila (tudo entre o número e o @, removendo espaços)
        QUEUE_NAME=$(echo "$QUEUE_INFO" | sed -E 's/^\s*[0-9]+\.\s+([^@]+)\s+@.*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
        QUEUE_NAME="$QUEUE_INPUT"
        # Obter vhost da fila pelo nome
        QUEUE_INFO=$(echo "$QUEUES_LIST" | grep -E "^\s*[0-9]+\. $QUEUE_NAME" | head -1)
    fi
    
    if [ -z "$QUEUE_INFO" ]; then
        print_error "Fila '$QUEUE_NAME' não encontrada!"
        return 1
    fi
    
    VHOST=$(echo "$QUEUE_INFO" | grep -oP '@ \K[^ ]+' || echo "/")
    
    print_warning "⚠️  Esta operação removerá:"
    print_warning "   - A fila '$QUEUE_NAME' do vhost '$VHOST'"
    print_warning "   - A fila dead associada (se existir)"
    print_warning "   - Todos os bindings relacionados"
    echo ""
    
    read -p "Confirma a remoção? (s/N/'.' para voltar): " -r CONFIRM
    if [ "$CONFIRM" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
        print_info "Operação cancelada."
        return 1
    fi
    
    if run_python "remove_queue" "$DEFINITIONS_FILE" "$QUEUE_NAME" "$VHOST"; then
        print_success "Fila '$QUEUE_NAME' removida com sucesso!"
        return 0
    else
        return 1
    fi
}

# Menu principal
show_menu() {
    echo ""
    print_header "🐰 Gerenciador de Filas e Virtualhosts RabbitMQ"
    echo ""
    echo "  📬 FILAS:"
    echo "    1. Listar filas"
    echo "    2. Adicionar fila"
    echo "    3. Editar fila"
    echo "    4. Remover fila"
    echo ""
    echo "  🌐 VIRTUALHOSTS:"
    echo "    5. Listar virtualhosts"
    echo "    6. Adicionar virtualhost"
    echo "    7. Remover virtualhost"
    echo ""
    echo "  ℹ️  INFORMAÇÕES:"
    echo "    8. Ver resumo completo"
    echo ""
    echo "    0. Sair"
    echo ""
}

# Mostrar resumo
show_summary() {
    print_header "📋 Resumo Completo"
    echo ""
    
    echo -e "${CYAN}Virtualhosts:${NC}"
    run_python "list_vhosts" "$DEFINITIONS_FILE"
    echo ""
    
    echo -e "${CYAN}Filas:${NC}"
    run_python "list_queues" "$DEFINITIONS_FILE"
    echo ""
}

# Função principal
main() {
    # Criar backup antes de qualquer modificação
    if [ -f "$DEFINITIONS_FILE" ]; then
        BACKUP_FILE="${DEFINITIONS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$DEFINITIONS_FILE" "$BACKUP_FILE"
        print_info "Backup criado: $BACKUP_FILE"
    fi
    
    # Garantir que o arquivo existe
    if [ ! -f "$DEFINITIONS_FILE" ]; then
        print_warning "Arquivo definitions.json não encontrado. Criando arquivo vazio..."
        echo '{"users":[],"vhosts":[{"name":"/"}],"permissions":[],"exchanges":[],"queues":[],"bindings":[],"policies":[]}' > "$DEFINITIONS_FILE"
    fi
    
    print_info "ℹ️  NOTA: Usuários devem ser gerenciados usando o script manage_users.sh"
    print_info "   Execute './manage_users.sh' para criar/gerenciar usuários."
echo ""

    while true; do
        show_menu
        read -p "Escolha uma opção: " OPTION
        
        case "$OPTION" in
            1)
                list_queues_interactive
                ;;
            2)
                add_queue_interactive
                ;;
            3)
                edit_queue_interactive
                ;;
            4)
                remove_queue_interactive
                ;;
            5)
                list_vhosts_interactive
                ;;
            6)
                add_vhost_interactive
                ;;
            7)
                remove_vhost_interactive
                ;;
            8)
                show_summary
                ;;
            0)
                print_info "Saindo..."
                exit 0
                ;;
            *)
                print_error "Opção inválida!"
                ;;
        esac
        
        echo ""
        read -p "Pressione Enter para continuar..."
    done
}

# Executar função principal
main "$@"
