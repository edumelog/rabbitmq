#!/bin/bash

# =============================================================================
# manage_users.sh - Gerenciador de Usuários do RabbitMQ
# =============================================================================
# Este script permite gerenciar usuários no definitions.json de forma
# não destrutiva, sem alterar filas, exchanges, bindings e outras configurações.
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
# Função Python para manipular o JSON
# =============================================================================
PYTHON_SCRIPT=$(cat << 'PYTHON_EOF'
import json
import sys
import os

def load_definitions(filepath):
    """Carrega o definitions.json"""
    if not os.path.exists(filepath):
        # Criar arquivo vazio se não existir
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
    # Adicionar newline no final
    with open(filepath, 'a', encoding='utf-8') as f:
        f.write('\n')

def list_users(data):
    """Lista todos os usuários"""
    users = data.get("users", [])
    if not users:
        print("Nenhum usuário encontrado.")
        return []
    
    print("\nUsuários existentes:")
    for i, user in enumerate(users, 1):
        tags = user.get("tags", "")
        print(f"  {i}. {user['name']} (tags: {tags})")
    
    return users

def get_user(data, username):
    """Obtém um usuário pelo nome"""
    users = data.get("users", [])
    for user in users:
        if user.get("name") == username:
            return user
    return None

def add_user(data, username, password, tags):
    """Adiciona um novo usuário"""
    users = data.get("users", [])
    
    # Verificar se usuário já existe
    if any(u.get("name") == username for u in users):
        print(f"ERRO: Usuário '{username}' já existe!")
        return False
    
    users.append({
        "name": username,
        "password": password,
        "tags": tags
    })
    data["users"] = users
    return True

def update_user(data, username, new_password=None, new_tags=None):
    """Atualiza senha e/ou tags de um usuário"""
    users = data.get("users", [])
    
    user = get_user(data, username)
    if not user:
        print(f"ERRO: Usuário '{username}' não encontrado!")
        return False
    
    # Atualizar senha se fornecida
    if new_password is not None and new_password != "None":
        user["password"] = new_password
    
    # Atualizar tags se fornecidas
    if new_tags is not None and new_tags != "None":
        user["tags"] = new_tags
    
    return True

def remove_user(data, username):
    """Remove um usuário e suas permissões"""
    users = data.get("users", [])
    permissions = data.get("permissions", [])
    
    # Remover usuário
    original_count = len(users)
    data["users"] = [u for u in users if u.get("name") != username]
    
    if len(data["users"]) == original_count:
        print(f"ERRO: Usuário '{username}' não encontrado!")
        return False
    
    # Remover permissões do usuário
    data["permissions"] = [p for p in permissions if p.get("user") != username]
    
    return True

def add_permission(data, username, vhost, configure, write, read):
    """Adiciona permissão para um usuário em um virtualhost"""
    permissions = data.get("permissions", [])
    
    # Verificar se permissão já existe
    for perm in permissions:
        if perm.get("user") == username and perm.get("vhost") == vhost:
            # Atualizar permissão existente
            perm["configure"] = configure
            perm["write"] = write
            perm["read"] = read
            return True
    
    # Adicionar nova permissão
    permissions.append({
        "user": username,
        "vhost": vhost,
        "configure": configure,
        "write": write,
        "read": read
    })
    data["permissions"] = permissions
    return True

def remove_permission(data, username, vhost):
    """Remove permissão de um usuário em um virtualhost específico"""
    permissions = data.get("permissions", [])
    original_count = len(permissions)
    
    data["permissions"] = [
        p for p in permissions 
        if not (p.get("user") == username and p.get("vhost") == vhost)
    ]
    
    if len(data["permissions"]) == original_count:
        print(f"ERRO: Permissão não encontrada para '{username}' no vhost '{vhost}'!")
        return False
    
    return True

def get_permission(data, username, vhost):
    """Obtém permissão de um usuário em um virtualhost específico"""
    permissions = data.get("permissions", [])
    for perm in permissions:
        if perm.get("user") == username and perm.get("vhost") == vhost:
            return perm
    return None

def list_permissions(data, username):
    """Lista permissões de um usuário"""
    permissions = data.get("permissions", [])
    user_perms = [p for p in permissions if p.get("user") == username]
    
    if not user_perms:
        print(f"Nenhuma permissão encontrada para o usuário '{username}'.")
        return []
    
    print(f"\nPermissões do usuário '{username}':")
    for perm in user_perms:
        vhost = perm.get("vhost", "/")
        print(f"  Virtualhost: {vhost}")
        print(f"    Configure: {perm.get('configure', 'N/A')}")
        print(f"    Write: {perm.get('write', 'N/A')}")
        print(f"    Read: {perm.get('read', 'N/A')}")
        print()
    
    return user_perms

def get_vhosts(data):
    """Obtém lista de virtualhosts"""
    vhosts = data.get("vhosts", [])
    return [v.get("name", "/") for v in vhosts]

def ensure_admin_user(data):
    """Garante que o usuário admin existe"""
    users = data.get("users", [])
    
    # Verificar se admin já existe
    if any(u.get("name") == "admin" for u in users):
        return False  # Já existe
    
    # Criar usuário admin padrão
    print("Criando usuário admin padrão...")
    users.append({
        "name": "admin",
        "password": "admin",
        "tags": "administrator"
    })
    data["users"] = users
    
    # Adicionar permissões para todos os vhosts
    vhosts = get_vhosts(data)
    permissions = data.get("permissions", [])
    
    for vhost in vhosts:
        # Verificar se já existe permissão
        if not any(p.get("user") == "admin" and p.get("vhost") == vhost for p in permissions):
            permissions.append({
                "user": "admin",
                "vhost": vhost,
                "configure": ".*",
                "write": ".*",
                "read": ".*"
            })
    
    data["permissions"] = permissions
    return True

# Executar comando
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("ERRO: Comando não especificado")
        sys.exit(1)
    
    command = sys.argv[1]
    filepath = sys.argv[2] if len(sys.argv) > 2 else "rabbit_definitions/definitions.json"
    
    data = load_definitions(filepath)
    
    if command == "list":
        list_users(data)
    
    elif command == "add":
        if len(sys.argv) < 5:
            print("ERRO: Uso: add <username> <password> <tags>")
            sys.exit(1)
        username = sys.argv[3]
        password = sys.argv[4]
        tags = sys.argv[5] if len(sys.argv) > 5 else ""
        if add_user(data, username, password, tags):
            save_definitions(filepath, data)
            print(f"SUCCESS: Usuário '{username}' adicionado com sucesso!")
        else:
            sys.exit(1)
    
    elif command == "update":
        if len(sys.argv) < 4:
            print("ERRO: Uso: update <username> [new_password] [new_tags]")
            sys.exit(1)
        username = sys.argv[3]
        new_password = sys.argv[4] if len(sys.argv) > 4 else None
        new_tags = sys.argv[5] if len(sys.argv) > 5 else None
        if update_user(data, username, new_password, new_tags):
            save_definitions(filepath, data)
            print(f"SUCCESS: Usuário '{username}' atualizado com sucesso!")
        else:
            sys.exit(1)
    
    elif command == "remove":
        if len(sys.argv) < 4:
            print("ERRO: Uso: remove <username>")
            sys.exit(1)
        username = sys.argv[3]
        if remove_user(data, username):
            save_definitions(filepath, data)
            print(f"SUCCESS: Usuário '{username}' removido com sucesso!")
        else:
            sys.exit(1)
    
    elif command == "remove_permission":
        if len(sys.argv) < 5:
            print("ERRO: Uso: remove_permission <username> <vhost>")
            sys.exit(1)
        username = sys.argv[3]
        vhost = sys.argv[4]
        if remove_permission(data, username, vhost):
            save_definitions(filepath, data)
            print(f"SUCCESS: Permissão removida para '{username}' no vhost '{vhost}'!")
        else:
            sys.exit(1)
    
    elif command == "get_permission":
        if len(sys.argv) < 5:
            print("ERRO: Uso: get_permission <username> <vhost>")
            sys.exit(1)
        username = sys.argv[3]
        vhost = sys.argv[4]
        perm = get_permission(data, username, vhost)
        if perm:
            # Retornar em formato fácil de parsear
            print(f"VHOST={perm.get('vhost', '/')}")
            print(f"CONFIGURE={perm.get('configure', 'N/A')}")
            print(f"WRITE={perm.get('write', 'N/A')}")
            print(f"READ={perm.get('read', 'N/A')}")
        else:
            print("ERRO: Nenhuma permissão encontrada.")
            sys.exit(1)
    
    elif command == "permissions":
        if len(sys.argv) < 4:
            print("ERRO: Uso: permissions <username>")
            sys.exit(1)
        username = sys.argv[3]
        list_permissions(data, username)
    
    elif command == "add_permission":
        if len(sys.argv) < 8:
            print("ERRO: Uso: add_permission <username> <vhost> <configure> <write> <read>")
            sys.exit(1)
        username = sys.argv[3]
        vhost = sys.argv[4]
        configure = sys.argv[5]
        write = sys.argv[6]
        read = sys.argv[7]
        if add_permission(data, username, vhost, configure, write, read):
            save_definitions(filepath, data)
            print(f"SUCCESS: Permissão adicionada para '{username}' no vhost '{vhost}'!")
        else:
            sys.exit(1)
    
    elif command == "ensure_admin":
        if ensure_admin_user(data):
            save_definitions(filepath, data)
            print("SUCCESS: Usuário admin criado com sucesso!")
        else:
            print("INFO: Usuário admin já existe.")
    
    elif command == "get_vhosts":
        vhosts = get_vhosts(data)
        for vhost in vhosts:
            print(vhost)
    
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

# Listar usuários
list_users() {
    print_header "👥 Lista de Usuários"
    echo ""
    run_python "list" "$DEFINITIONS_FILE"
    echo ""
}

# Adicionar usuário
add_user_interactive() {
    print_header "➕ Adicionar Novo Usuário"
    echo ""
    print_info "Digite '.' (ponto) a qualquer momento para voltar ao menu."
    echo ""
    
    read -p "Nome do usuário (ou '.' para voltar): " USERNAME
    if [ -z "$USERNAME" ] || [ "$USERNAME" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Verificar se usuário já existe
    if run_python "list" "$DEFINITIONS_FILE" | grep -q "  .* $USERNAME "; then
        print_error "Usuário '$USERNAME' já existe!"
        return 1
    fi
    
    read -sp "Senha do usuário (ou '.' para voltar): " PASSWORD
    echo ""
    if [ "$PASSWORD" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    if [ -z "$PASSWORD" ]; then
        print_error "Senha não pode estar vazia!"
        return 1
    fi
    
    echo ""
    print_info "Tags padrão do RabbitMQ:"
    echo "  1. administrator (acesso administrativo completo)"
    echo "  2. monitoring (acesso para monitoramento e estatísticas)"
    echo "  3. policymaker (pode criar e gerenciar políticas)"
    echo "  4. management (acesso à API de gerenciamento)"
    echo "  0. Nenhuma tag (usuário normal)"
    echo ""
    read -p "Selecione as tags pelo número (separados por vírgula, ex: 1,3 ou Enter para nenhuma, '.' para voltar): " TAGS_INPUT
    if [ "$TAGS_INPUT" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Processar seleção de tags
    TAGS=""
    if [ -n "$TAGS_INPUT" ]; then
        # Separar por vírgula e processar cada número
        IFS=',' read -ra TAG_NUMBERS <<< "$TAGS_INPUT"
        TAG_ARRAY=()
        HAS_ZERO=false
        
        # Primeiro, verificar se há "0" na seleção
        for TAG_NUM in "${TAG_NUMBERS[@]}"; do
            TAG_NUM=$(echo "$TAG_NUM" | tr -d '[:space:]')
            if [ "$TAG_NUM" = "0" ]; then
                HAS_ZERO=true
                break
            fi
        done
        
        # Se "0" foi selecionado, ignorar todas as outras tags
        if [ "$HAS_ZERO" = true ]; then
            TAG_ARRAY=()
        else
            # Processar outras tags
            for TAG_NUM in "${TAG_NUMBERS[@]}"; do
                TAG_NUM=$(echo "$TAG_NUM" | tr -d '[:space:]')  # Remover espaços
                case "$TAG_NUM" in
                    1)
                        TAG_ARRAY+=("administrator")
                        ;;
                    2)
                        TAG_ARRAY+=("monitoring")
                        ;;
                    3)
                        TAG_ARRAY+=("policymaker")
                        ;;
                    4)
                        TAG_ARRAY+=("management")
                        ;;
                    0)
                        # Nenhuma tag - limpar array (não deveria chegar aqui se HAS_ZERO=true)
                        TAG_ARRAY=()
                        ;;
                    *)
                        print_warning "Número '$TAG_NUM' ignorado (inválido)"
                        ;;
                esac
            done
        fi
        
        # Remover duplicatas e juntar com vírgula
        if [ ${#TAG_ARRAY[@]} -gt 0 ]; then
            # Usar Python para remover duplicatas e ordenar
            TAGS=$(printf '%s\n' "${TAG_ARRAY[@]}" | python3 -c "
import sys
tags = [line.strip() for line in sys.stdin if line.strip()]
# Remover duplicatas mantendo ordem
seen = set()
unique_tags = []
for tag in tags:
    if tag not in seen:
        seen.add(tag)
        unique_tags.append(tag)
print(','.join(unique_tags))
")
        fi
    fi
    
    # Mostrar tags selecionadas
    if [ -n "$TAGS" ]; then
        echo ""
        print_info "Tags selecionadas: $TAGS"
    else
        echo ""
        print_info "Nenhuma tag selecionada (usuário normal)"
    fi
    echo ""
    
    # Adicionar usuário
    if run_python "add" "$DEFINITIONS_FILE" "$USERNAME" "$PASSWORD" "$TAGS"; then
        print_success "Usuário '$USERNAME' adicionado com sucesso!"
        
        # Perguntar sobre permissões
        echo ""
        read -p "Deseja configurar permissões para este usuário? (s/N/'.' para voltar): " -r CONFIG_PERMS
        if [ "$CONFIG_PERMS" = "." ]; then
            print_info "Voltando ao menu..."
            return 0
        fi
        if [[ "$CONFIG_PERMS" =~ ^[Ss]$ ]]; then
            configure_permissions "$USERNAME"
        fi
        
        return 0
    else
        return 1
    fi
}

# Remover usuário
remove_user_interactive() {
    print_header "➖ Remover Usuário"
    echo ""
    print_info "Digite '.' (ponto) a qualquer momento para voltar ao menu."
    echo ""
    
    # Obter lista de usuários
    USERS_LIST=$(run_python "list" "$DEFINITIONS_FILE" 2>/dev/null)
    echo "$USERS_LIST"
    
    echo ""
    read -p "Número ou nome do usuário a remover (ou '.' para voltar): " USER_INPUT
    if [ -z "$USER_INPUT" ] || [ "$USER_INPUT" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Verificar se é um número (índice)
    if [[ "$USER_INPUT" =~ ^[0-9]+$ ]]; then
        # Extrair nome do usuário pelo índice
        USER_INFO=$(echo "$USERS_LIST" | grep -E "^\s*${USER_INPUT}\." | head -1)
        if [ -z "$USER_INFO" ]; then
            print_error "Índice '$USER_INPUT' não encontrado na lista!"
            return 1
        fi
        # Extrair nome do usuário (tudo entre o número e o parêntese)
        USERNAME=$(echo "$USER_INFO" | sed -E 's/^\s*[0-9]+\.\s+([^(]+)\s+\(.*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
        USERNAME="$USER_INPUT"
    fi
    
    # Verificar se é o admin
    if [ "$USERNAME" = "admin" ]; then
        print_warning "⚠️  Você está prestes a remover o usuário administrador!"
        read -p "Tem certeza? (digite 'SIM' para confirmar ou '.' para voltar): " -r CONFIRM
        if [ "$CONFIRM" = "." ]; then
            print_info "Voltando ao menu..."
            return 0
        fi
        if [ "$CONFIRM" != "SIM" ]; then
            print_info "Operação cancelada."
            return 1
        fi
    fi
    
    # Mostrar permissões que serão removidas
    echo ""
    print_info "Permissões que serão removidas:"
    run_python "permissions" "$DEFINITIONS_FILE" "$USERNAME"
    
    echo ""
    read -p "Confirma a remoção do usuário '$USERNAME'? (s/N/'.' para voltar): " -r CONFIRM
    if [ "$CONFIRM" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
        print_info "Operação cancelada."
        return 1
    fi
    
    if run_python "remove" "$DEFINITIONS_FILE" "$USERNAME"; then
        print_success "Usuário '$USERNAME' removido com sucesso!"
        return 0
    else
        return 1
    fi
}

# Configurar permissões
configure_permissions() {
    local username="$1"
    
    print_header "🔐 Configurar Permissões para '$username'"
    echo ""
    print_info "Digite '.' (ponto) a qualquer momento para voltar ao menu."
    echo ""
    
    # Obter lista de virtualhosts
    VHOSTS=$(run_python "get_vhosts" "$DEFINITIONS_FILE")
    
    if [ -z "$VHOSTS" ]; then
        print_warning "Nenhum virtualhost encontrado. Criando virtualhost padrão '/'..."
        VHOSTS="/"
    fi
    
    echo "Virtualhosts disponíveis:"
    VHOST_ARRAY=()
    i=1
    while IFS= read -r vhost; do
        if [ -n "$vhost" ]; then
            echo "  $i. $vhost"
            VHOST_ARRAY+=("$vhost")
            i=$((i+1))
        fi
    done <<< "$VHOSTS"
    echo ""
    
    read -p "Número ou nome do virtualhost (ou '.' para voltar): " VHOST_INPUT
    if [ "$VHOST_INPUT" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Verificar se é número
    if [[ "$VHOST_INPUT" =~ ^[0-9]+$ ]]; then
        VHOST_INDEX=$((VHOST_INPUT - 1))
        if [ $VHOST_INDEX -ge 0 ] && [ $VHOST_INDEX -lt ${#VHOST_ARRAY[@]} ]; then
            VHOST="${VHOST_ARRAY[$VHOST_INDEX]}"
        else
            print_error "Número inválido!"
            return 1
        fi
    else
        VHOST="$VHOST_INPUT"
    fi
    VHOST=${VHOST:-/}
    
    echo ""
    print_info "Padrões de permissão:"
    echo "  - .* (todas as permissões)"
    echo "  - ^$ (nenhuma permissão)"
    echo "  - ^nome_especifico$ (permissão específica)"
    echo ""
    
    read -p "Configure pattern [.*] (ou '.' para voltar): " CONFIGURE
    if [ "$CONFIGURE" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    CONFIGURE=${CONFIGURE:-.*}
    
    read -p "Write pattern [.*] (ou '.' para voltar): " WRITE
    if [ "$WRITE" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    WRITE=${WRITE:-.*}
    
    read -p "Read pattern [.*] (ou '.' para voltar): " READ
    if [ "$READ" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    READ=${READ:-.*}
    
    if run_python "add_permission" "$DEFINITIONS_FILE" "$username" "$VHOST" "$CONFIGURE" "$WRITE" "$READ"; then
        print_success "Permissões configuradas com sucesso!"
        return 0
    else
        return 1
    fi
}

# Ver permissões de um usuário
view_permissions() {
    print_header "🔍 Ver Permissões de Usuário"
    echo ""
    print_info "Digite '.' (ponto) para voltar ao menu."
    echo ""
    
    # Obter lista de usuários
    USERS_LIST=$(run_python "list" "$DEFINITIONS_FILE" 2>/dev/null)
    echo "$USERS_LIST"
    
    echo ""
    read -p "Número ou nome do usuário (ou '.' para voltar): " USER_INPUT
    if [ -z "$USER_INPUT" ] || [ "$USER_INPUT" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Verificar se é um número (índice)
    if [[ "$USER_INPUT" =~ ^[0-9]+$ ]]; then
        # Extrair nome do usuário pelo índice
        USER_INFO=$(echo "$USERS_LIST" | grep -E "^\s*${USER_INPUT}\." | head -1)
        if [ -z "$USER_INFO" ]; then
            print_error "Índice '$USER_INPUT' não encontrado na lista!"
            return 1
        fi
        # Extrair nome do usuário (tudo entre o número e o parêntese)
        USERNAME=$(echo "$USER_INFO" | sed -E 's/^\s*[0-9]+\.\s+([^(]+)\s+\(.*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
        USERNAME="$USER_INPUT"
    fi
    
    echo ""
    run_python "permissions" "$DEFINITIONS_FILE" "$USERNAME"
}

# Editar usuário
edit_user_interactive() {
    print_header "✏️  Editar Usuário"
    echo ""
    print_info "Digite '.' (ponto) a qualquer momento para voltar ao menu."
    echo ""
    
    # Obter lista de usuários
    USERS_LIST=$(run_python "list" "$DEFINITIONS_FILE" 2>/dev/null)
    echo "$USERS_LIST"
    
    echo ""
    read -p "Número ou nome do usuário a editar (ou '.' para voltar): " USER_INPUT
    if [ -z "$USER_INPUT" ] || [ "$USER_INPUT" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Verificar se é um número (índice)
    if [[ "$USER_INPUT" =~ ^[0-9]+$ ]]; then
        USER_INFO=$(echo "$USERS_LIST" | grep -E "^\s*${USER_INPUT}\." | head -1)
        if [ -z "$USER_INFO" ]; then
            print_error "Índice '$USER_INPUT' não encontrado na lista!"
            return 1
        fi
        USERNAME=$(echo "$USER_INFO" | sed -E 's/^\s*[0-9]+\.\s+([^(]+)\s+\(.*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
        USERNAME="$USER_INPUT"
    fi
    
    # Obter informações atuais do usuário
    CURRENT_USER=$(run_python "list" "$DEFINITIONS_FILE" 2>/dev/null | grep -E "^\s*[0-9]+\.\s+${USERNAME}\s+" | head -1)
    if [ -z "$CURRENT_USER" ]; then
        print_error "Usuário '$USERNAME' não encontrado!"
        return 1
    fi
    
    echo ""
    print_info "Usuário atual: $CURRENT_USER"
    echo ""
    
    # Editar senha
    read -p "Nova senha (Enter para manter atual, '.' para voltar): " NEW_PASSWORD
    if [ "$NEW_PASSWORD" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Editar tags
    echo ""
    print_info "Tags padrão do RabbitMQ:"
    echo "  1. administrator (acesso administrativo completo)"
    echo "  2. monitoring (acesso para monitoramento e estatísticas)"
    echo "  3. policymaker (pode criar e gerenciar políticas)"
    echo "  4. management (acesso à API de gerenciamento)"
    echo "  0. Nenhuma tag (usuário normal)"
    echo ""
    read -p "Selecione as tags pelo número (separados por vírgula, Enter para manter atual, '.' para voltar): " TAGS_INPUT
    if [ "$TAGS_INPUT" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Processar seleção de tags (mesma lógica de add_user_interactive)
    NEW_TAGS="None"
    if [ -n "$TAGS_INPUT" ]; then
        IFS=',' read -ra TAG_NUMBERS <<< "$TAGS_INPUT"
        TAG_ARRAY=()
        HAS_ZERO=false
        
        for TAG_NUM in "${TAG_NUMBERS[@]}"; do
            TAG_NUM=$(echo "$TAG_NUM" | tr -d '[:space:]')
            if [ "$TAG_NUM" = "0" ]; then
                HAS_ZERO=true
                break
            fi
        done
        
        if [ "$HAS_ZERO" = true ]; then
            TAG_ARRAY=()
        else
            for TAG_NUM in "${TAG_NUMBERS[@]}"; do
                TAG_NUM=$(echo "$TAG_NUM" | tr -d '[:space:]')
                case "$TAG_NUM" in
                    1) TAG_ARRAY+=("administrator") ;;
                    2) TAG_ARRAY+=("monitoring") ;;
                    3) TAG_ARRAY+=("policymaker") ;;
                    4) TAG_ARRAY+=("management") ;;
                esac
            done
        fi
        
        if [ ${#TAG_ARRAY[@]} -gt 0 ]; then
            NEW_TAGS=$(printf '%s\n' "${TAG_ARRAY[@]}" | python3 -c "
import sys
tags = [line.strip() for line in sys.stdin if line.strip()]
seen = set()
unique_tags = []
for tag in tags:
    if tag not in seen:
        seen.add(tag)
        unique_tags.append(tag)
print(','.join(unique_tags))
")
        else
            NEW_TAGS=""
        fi
    fi
    
    # Preparar parâmetros
    PASSWORD_PARAM="None"
    if [ -n "$NEW_PASSWORD" ]; then
        PASSWORD_PARAM="$NEW_PASSWORD"
    fi
    
    TAGS_PARAM="None"
    if [ "$NEW_TAGS" != "None" ]; then
        TAGS_PARAM="$NEW_TAGS"
    fi
    
    # Atualizar usuário
    if run_python "update" "$DEFINITIONS_FILE" "$USERNAME" "$PASSWORD_PARAM" "$TAGS_PARAM"; then
        print_success "Usuário '$USERNAME' atualizado com sucesso!"
        return 0
    else
        return 1
    fi
}

# Gerenciar permissões de um usuário por virtualhost
manage_user_permissions() {
    print_header "🔐 Gerenciar Permissões por Virtualhost"
    echo ""
    print_info "Digite '.' (ponto) a qualquer momento para voltar ao menu."
    echo ""
    
    # Obter lista de usuários
    USERS_LIST=$(run_python "list" "$DEFINITIONS_FILE" 2>/dev/null)
    echo "$USERS_LIST"
    
    echo ""
    read -p "Número ou nome do usuário (ou '.' para voltar): " USER_INPUT
    if [ -z "$USER_INPUT" ] || [ "$USER_INPUT" = "." ]; then
        print_info "Voltando ao menu..."
        return 0
    fi
    
    # Verificar se é um número (índice)
    if [[ "$USER_INPUT" =~ ^[0-9]+$ ]]; then
        USER_INFO=$(echo "$USERS_LIST" | grep -E "^\s*${USER_INPUT}\." | head -1)
        if [ -z "$USER_INFO" ]; then
            print_error "Índice '$USER_INPUT' não encontrado na lista!"
            return 1
        fi
        USERNAME=$(echo "$USER_INFO" | sed -E 's/^\s*[0-9]+\.\s+([^(]+)\s+\(.*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    else
        USERNAME="$USER_INPUT"
    fi
    
    while true; do
        echo ""
        print_header "🔐 Permissões de '$USERNAME'"
        echo ""
        
        # Listar permissões atuais
        run_python "permissions" "$DEFINITIONS_FILE" "$USERNAME"
        
        echo ""
        echo "  1. Adicionar permissão em um virtualhost"
        echo "  2. Editar permissão em um virtualhost"
        echo "  3. Remover permissão de um virtualhost"
        echo "  0. Voltar ao menu principal"
        echo ""
        read -p "Escolha uma opção: " PERM_OPTION
        
        case "$PERM_OPTION" in
            1)
                # Adicionar permissão
                VHOSTS=$(run_python "get_vhosts" "$DEFINITIONS_FILE")
                if [ -z "$VHOSTS" ]; then
                    print_warning "Nenhum virtualhost encontrado."
                    continue
                fi
                
                echo ""
                echo "Virtualhosts disponíveis:"
                VHOST_ARRAY=()
                i=1
                while IFS= read -r vhost; do
                    if [ -n "$vhost" ]; then
                        echo "  $i. $vhost"
                        VHOST_ARRAY+=("$vhost")
                        i=$((i+1))
                    fi
                done <<< "$VHOSTS"
                echo ""
                
                read -p "Número ou nome do virtualhost (ou '.' para voltar): " VHOST_INPUT
                if [ "$VHOST_INPUT" = "." ]; then
                    continue
                fi
                
                # Verificar se é número
                if [[ "$VHOST_INPUT" =~ ^[0-9]+$ ]]; then
                    VHOST_INDEX=$((VHOST_INPUT - 1))
                    if [ $VHOST_INDEX -ge 0 ] && [ $VHOST_INDEX -lt ${#VHOST_ARRAY[@]} ]; then
                        VHOST="${VHOST_ARRAY[$VHOST_INDEX]}"
                    else
                        print_error "Número inválido!"
                        continue
                    fi
                else
                    VHOST="$VHOST_INPUT"
                fi
                VHOST=${VHOST:-/}
                
                echo ""
                print_info "Padrões de permissão:"
                echo "  - .* (todas as permissões)"
                echo "  - ^$ (nenhuma permissão)"
                echo ""
                
                read -p "Configure pattern [.*] (ou '.' para voltar): " CONFIGURE
                if [ "$CONFIGURE" = "." ]; then
                    continue
                fi
                CONFIGURE=${CONFIGURE:-.*}
                
                read -p "Write pattern [.*] (ou '.' para voltar): " WRITE
                if [ "$WRITE" = "." ]; then
                    continue
                fi
                WRITE=${WRITE:-.*}
                
                read -p "Read pattern [.*] (ou '.' para voltar): " READ
                if [ "$READ" = "." ]; then
                    continue
                fi
                READ=${READ:-.*}
                
                if run_python "add_permission" "$DEFINITIONS_FILE" "$USERNAME" "$VHOST" "$CONFIGURE" "$WRITE" "$READ"; then
                    print_success "Permissão adicionada com sucesso!"
                fi
                ;;
            2)
                # Editar permissão
                PERMS_LIST=$(run_python "permissions" "$DEFINITIONS_FILE" "$USERNAME" 2>/dev/null)
                VHOSTS_WITH_PERMS=$(echo "$PERMS_LIST" | grep -E "^\s+Virtualhost:" | sed 's/^\s+Virtualhost: //')
                
                if [ -z "$VHOSTS_WITH_PERMS" ]; then
                    print_warning "Nenhuma permissão encontrada para editar."
                    continue
                fi
                
                echo ""
                echo "Virtualhosts com permissões:"
                i=1
                while IFS= read -r vhost; do
                    if [ -n "$vhost" ]; then
                        echo "  $i. $vhost"
                        i=$((i+1))
                    fi
                done <<< "$VHOSTS_WITH_PERMS"
                echo ""
                
                read -p "Número ou nome do virtualhost (ou '.' para voltar): " VHOST_INPUT
                if [ "$VHOST_INPUT" = "." ]; then
                    continue
                fi
                
                # Verificar se é número
                if [[ "$VHOST_INPUT" =~ ^[0-9]+$ ]]; then
                    VHOST=$(echo "$VHOSTS_WITH_PERMS" | sed -n "${VHOST_INPUT}p")
                else
                    VHOST="$VHOST_INPUT"
                fi
                
                # Obter permissão atual
                PERM_INFO=$(run_python "get_permission" "$DEFINITIONS_FILE" "$USERNAME" "$VHOST" 2>/dev/null)
                if [ $? -ne 0 ]; then
                    print_error "Permissão não encontrada para '$USERNAME' no vhost '$VHOST'!"
                    continue
                fi
                
                CURRENT_CONFIGURE=$(echo "$PERM_INFO" | grep "^CONFIGURE=" | cut -d= -f2-)
                CURRENT_WRITE=$(echo "$PERM_INFO" | grep "^WRITE=" | cut -d= -f2-)
                CURRENT_READ=$(echo "$PERM_INFO" | grep "^READ=" | cut -d= -f2-)
                
                echo ""
                print_info "Permissões atuais no vhost '$VHOST':"
                echo "  Configure: $CURRENT_CONFIGURE"
                echo "  Write: $CURRENT_WRITE"
                echo "  Read: $CURRENT_READ"
                echo ""
                
                read -p "Novo Configure pattern [$CURRENT_CONFIGURE] (ou '.' para voltar): " CONFIGURE
                if [ "$CONFIGURE" = "." ]; then
                    continue
                fi
                CONFIGURE=${CONFIGURE:-$CURRENT_CONFIGURE}
                
                read -p "Novo Write pattern [$CURRENT_WRITE] (ou '.' para voltar): " WRITE
                if [ "$WRITE" = "." ]; then
                    continue
                fi
                WRITE=${WRITE:-$CURRENT_WRITE}
                
                read -p "Novo Read pattern [$CURRENT_READ] (ou '.' para voltar): " READ
                if [ "$READ" = "." ]; then
                    continue
                fi
                READ=${READ:-$CURRENT_READ}
                
                if run_python "add_permission" "$DEFINITIONS_FILE" "$USERNAME" "$VHOST" "$CONFIGURE" "$WRITE" "$READ"; then
                    print_success "Permissão atualizada com sucesso!"
                fi
                ;;
            3)
                # Remover permissão
                PERMS_LIST=$(run_python "permissions" "$DEFINITIONS_FILE" "$USERNAME" 2>/dev/null)
                VHOSTS_WITH_PERMS=$(echo "$PERMS_LIST" | grep -E "^\s+Virtualhost:" | sed 's/^\s+Virtualhost: //')
                
                if [ -z "$VHOSTS_WITH_PERMS" ]; then
                    print_warning "Nenhuma permissão encontrada para remover."
                    continue
                fi
                
                echo ""
                echo "Virtualhosts com permissões:"
                i=1
                while IFS= read -r vhost; do
                    if [ -n "$vhost" ]; then
                        echo "  $i. $vhost"
                        i=$((i+1))
                    fi
                done <<< "$VHOSTS_WITH_PERMS"
                echo ""
                
                read -p "Número ou nome do virtualhost (ou '.' para voltar): " VHOST_INPUT
                if [ "$VHOST_INPUT" = "." ]; then
                    continue
                fi
                
                # Verificar se é número
                if [[ "$VHOST_INPUT" =~ ^[0-9]+$ ]]; then
                    VHOST=$(echo "$VHOSTS_WITH_PERMS" | sed -n "${VHOST_INPUT}p")
                else
                    VHOST="$VHOST_INPUT"
                fi
                
                echo ""
                read -p "Confirma remoção da permissão no vhost '$VHOST'? (s/N/'.' para voltar): " CONFIRM
                if [ "$CONFIRM" = "." ]; then
                    continue
                fi
                if [[ "$CONFIRM" =~ ^[Ss]$ ]]; then
                    if run_python "remove_permission" "$DEFINITIONS_FILE" "$USERNAME" "$VHOST"; then
                        print_success "Permissão removida com sucesso!"
                    fi
                fi
                ;;
            0)
                return 0
                ;;
            *)
                print_error "Opção inválida!"
                ;;
        esac
    done
}

# Menu principal
show_menu() {
    echo ""
    print_header "👥 Gerenciador de Usuários RabbitMQ"
    echo ""
    echo "  1. Listar usuários"
    echo "  2. Adicionar usuário"
    echo "  3. Editar usuário (senha e tags)"
    echo "  4. Remover usuário"
    echo "  5. Ver permissões de um usuário"
    echo "  6. Gerenciar permissões por virtualhost"
    echo "  7. Configurar permissões de um usuário (legado)"
    echo "  8. Criar usuário admin padrão (se não existir)"
    echo "  0. Sair"
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
    
    while true; do
        show_menu
        read -p "Escolha uma opção: " OPTION
        
        case "$OPTION" in
            1)
                list_users
                ;;
            2)
                add_user_interactive
                ;;
            3)
                edit_user_interactive
                ;;
            4)
                remove_user_interactive
                ;;
            5)
                view_permissions
                ;;
            6)
                manage_user_permissions
                ;;
            7)
                # Obter lista de usuários
                USERS_LIST=$(run_python "list" "$DEFINITIONS_FILE" 2>/dev/null)
                echo "$USERS_LIST"
                echo ""
                read -p "Número ou nome do usuário (ou '.' para voltar): " USER_INPUT
                if [ "$USER_INPUT" = "." ] || [ -z "$USER_INPUT" ]; then
                    print_info "Voltando ao menu..."
                    continue
                fi
                
                # Verificar se é um número (índice)
                if [[ "$USER_INPUT" =~ ^[0-9]+$ ]]; then
                    # Extrair nome do usuário pelo índice
                    USER_INFO=$(echo "$USERS_LIST" | grep -E "^\s*${USER_INPUT}\." | head -1)
                    if [ -z "$USER_INFO" ]; then
                        print_error "Índice '$USER_INPUT' não encontrado na lista!"
                        continue
                    fi
                    # Extrair nome do usuário (tudo entre o número e o parêntese)
                    USERNAME=$(echo "$USER_INFO" | sed -E 's/^\s*[0-9]+\.\s+([^(]+)\s+\(.*/\1/' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                else
                    USERNAME="$USER_INPUT"
                fi
                
                if [ -n "$USERNAME" ]; then
                    configure_permissions "$USERNAME"
                fi
                ;;
            8)
                print_header "👤 Criar Usuário Admin"
                echo ""
                if run_python "ensure_admin" "$DEFINITIONS_FILE"; then
                    print_success "Usuário admin criado/verificado com sucesso!"
                fi
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

