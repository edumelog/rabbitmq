# 🐰 RabbitMQ - Ambiente Docker com Docker Swarm

Um ambiente Docker completo e otimizado para executar RabbitMQ usando Docker Swarm, com persistência de dados, configurações pré-carregadas e integração com redes compartilhadas.

## 📋 Índice

- [Visão Geral](#visão-geral)
- [Estrutura do Projeto](#estrutura-do-projeto)
- [Funcionalidades](#funcionalidades)
- [Pré-requisitos](#pré-requisitos)
- [Configuração Inicial](#configuração-inicial)
- [Scripts de Automação](#scripts-de-automação)
- [Uso](#uso)
- [Troubleshooting](#troubleshooting)

## 🎯 Visão Geral

Este projeto fornece um ambiente Docker completo para executar RabbitMQ com:

- **Imagem Oficial**: Usa a imagem oficial `rabbitmq:3.13.3-management` do Docker Hub
- **Versão Fixa**: Versão específica para evitar problemas com atualizações futuras
- **Docker Swarm**: Compatibilidade total com Docker Swarm e Portainer
- **Persistência**: Volumes locais para dados, logs e definições
- **Redes Compartilhadas**: Integração com redes overlay para comunicação entre serviços
- **Configurações Pré-carregadas**: Filas, exchanges e políticas definidas via `definitions.json`
- **Automação**: Scripts para iniciar e parar a stack facilmente

## 📁 Estrutura do Projeto

```
rabbitmq/
├── docker-compose.yml          # Configuração da stack RabbitMQ
├── env.example                 # Exemplo de variáveis de ambiente
├── start_stack.sh             # Script para iniciar a stack
├── stop_stack.sh              # Script para parar a stack
├── [nome]_data/               # Dados persistentes (mnesia)
├── [nome]_logs/               # Logs do RabbitMQ
├── [nome]_definitions/        # Definições (filas, exchanges, políticas)
│   └── definitions.json       # Arquivo de definições do RabbitMQ
└── README.md
```

## ⚡ Funcionalidades

### 🐰 RabbitMQ
- **Versão**: RabbitMQ 3.13.3 com Management Plugin
- **Management UI**: Console web de gerenciamento (porta 15672)
- **AMQP**: Protocolo de mensageria (porta 5672)
- **Persistência**: Dados e logs armazenados localmente
- **Definições**: Filas, exchanges e políticas pré-configuradas

### 🐳 Docker Swarm
- **Compatibilidade**: Total com Portainer e ambientes de produção
- **Healthchecks**: Monitoramento automático do serviço
- **Rollback**: Reversão automática em caso de falhas
- **Zero-downtime**: Atualizações sem interrupção
- **Redes Overlay**: Comunicação segura entre serviços

### 🔧 Automação
- **Scripts**: Início e parada automatizados da stack
- **Validação**: Verificação de pré-requisitos antes de iniciar
- **Pull Automático**: Download automático da imagem se não existir
- **Logs Coloridos**: Saída formatada para melhor experiência
- **Tratamento de Erros**: Mensagens claras em caso de problemas

## 📋 Pré-requisitos

- **Docker** instalado e rodando
- **Docker Swarm** inicializado (o script inicializa automaticamente se necessário)
- **Acesso à Internet** para baixar a imagem oficial do RabbitMQ

## ⚙️ Configuração Inicial

### 1. Clone o Repositório

```bash
git clone <repository>
cd rabbitmq
```

### 2. Configure as Variáveis de Ambiente

Copie o arquivo de exemplo e configure as variáveis:

```bash
cp env.example .env
nano .env
```

Configure as seguintes variáveis obrigatórias:

```bash
# Credenciais do RabbitMQ
RABBITMQ_DEFAULT_USER=admin
RABBITMQ_DEFAULT_PASS=secret
RABBITMQ_DEFAULT_VHOST=/
RABBITMQ_ERLANG_COOKIE=secret_cookie

# Nome da stack (opcional)
STACK_NAME=my-stack
```

**⚠️ IMPORTANTE**: 
- Altere as credenciais padrão em produção!
- O arquivo `.env` está no `.gitignore` e não será commitado

### 3. Configure as Definições (Opcional)

**Opção 1 - Gerador Interativo (Recomendado):**
```bash
./generate_definitions.sh
```
O script guia você passo a passo para criar o `definitions.json` personalizado.

**Opção 2 - Manual:**
```bash
cp rabbit_definitions/definitions.json.example rabbit_definitions/definitions.json
nano rabbit_definitions/definitions.json
```

Configure:
- Usuários e permissões
- Filas e exchanges
- Políticas (DLX, TTL, etc.)
- Bindings

## 🚀 Scripts de Automação

### Iniciar a Stack

```bash
./start_stack.sh
```

**O que o script faz:**
- Verifica se Docker e Docker Swarm estão rodando
- Carrega variáveis de ambiente do arquivo `.env`
- Verifica se a imagem oficial está disponível (faz pull se necessário)
- Cria os diretórios de dados se não existirem
- Verifica/cria as redes necessárias
- Faz deploy da stack no Docker Swarm
- Exibe informações de acesso e status

### Parar a Stack

```bash
./stop_stack.sh
```

**O que o script faz:**
- Verifica se a stack está rodando
- Exibe status atual dos serviços
- Confirma a parada com o usuário
- Remove a stack do Docker Swarm
- Gerencia redes (pergunta se deseja manter ou remover)
- Limpa recursos não utilizados

## 📖 Uso

### Iniciar o Ambiente

```bash
# 1. Configure o .env
cp env.example .env
nano .env

# 2. Inicie a stack
./start_stack.sh
```

### Acessar o RabbitMQ

**Management UI** (se portas estiverem expostas):
- URL: http://localhost:15672
- Usuário: Definido em `RABBITMQ_DEFAULT_USER`
- Senha: Definida em `RABBITMQ_DEFAULT_PASS`

**AMQP** (se portas estiverem expostas):
- Host: localhost
- Porta: 5672
- Usuário: Definido em `RABBITMQ_DEFAULT_USER`
- Senha: Definida em `RABBITMQ_DEFAULT_PASS`

**⚠️ Nota**: Por padrão, as portas NÃO estão expostas no `docker-compose.yml`. O acesso é feito apenas via redes Docker. Para expor as portas, descomente as linhas no `docker-compose.yml`:

```yaml
ports:
  - "5672:5672"     # Porta padrão AMQP
  - "15672:15672"   # Painel de administração
```

### Comandos Úteis

```bash
# Ver status dos serviços
docker service ls

# Ver logs em tempo real
docker service logs [stack-name]_[service-name] -f

# Acessar o container
docker exec -it $(docker ps -q -f name=[stack-name]_[service-name]) bash

# Ver status da stack
docker stack ls

# Ver detalhes de um serviço
docker service inspect [stack-name]_[service-name]
```

### Parar o Ambiente

```bash
./stop_stack.sh
```

Os dados em `[nome]_data/` e logs em `[nome]_logs/` serão preservados.

## 🔧 Configurações Avançadas

### Redes Docker

O projeto usa três redes:

1. **`[nome]_network`**: Rede específica do projeto (criada automaticamente)
2. **`shared_dev_net`**: Rede compartilhada para comunicação entre stacks (criada automaticamente)
3. **`net_nginx_pm`**: Rede externa compartilhada (deve existir ou será criada)

### Volumes

Os seguintes volumes são mapeados:

- `[nome]_data/` → `/var/lib/rabbitmq` (dados persistentes)
- `[nome]_logs/` → `/var/log/rabbitmq` (logs)
- `[nome]_definitions/definitions.json` → `/etc/rabbitmq/definitions.json` (definições)

### Healthcheck

O RabbitMQ possui healthcheck configurado que verifica o status do serviço a cada 30 segundos.

## 🚨 Troubleshooting

### Problema: "Docker não está rodando"

```bash
# Iniciar Docker
sudo systemctl start docker
```

### Problema: "Docker Swarm não está inicializado"

O script `start_stack.sh` inicializa automaticamente. Se precisar fazer manualmente:

```bash
docker swarm init --advertise-addr 127.0.0.1
```

### Problema: "Arquivo .env não encontrado"

```bash
# Criar arquivo .env baseado no exemplo
cp env.example .env
nano .env
```

### Problema: "Rede externa não encontrada"

O script cria automaticamente as redes necessárias. Se precisar criar manualmente:

```bash
# Rede compartilhada entre stacks
docker network create --driver overlay --attachable shared_dev_net

# Rede do proxy (se necessário)
docker network create --driver overlay --attachable net_nginx_pm
```

### Problema: "Imagem não encontrada"

O script faz pull automático. Se falhar:

```bash
# Fazer pull manual
docker pull rabbitmq:3.13.3-management
```

### Problema: "Container não inicia"

```bash
# Verificar logs
docker service logs [stack-name]_[service-name] -f

# Verificar status
docker service ps [stack-name]_[service-name]
```

### Problema: "Permissões nos volumes"

```bash
# Ajustar permissões dos diretórios
sudo chown -R 999:999 [nome]_data/
sudo chown -R 999:999 [nome]_logs/
```

O RabbitMQ roda como usuário `rabbitmq` (UID 999).

## 📝 Notas Importantes

### Segurança

- **NUNCA** commite o arquivo `.env` no Git
- Use senhas fortes em produção
- Mantenha o `RABBITMQ_ERLANG_COOKIE` secreto
- Considere usar secrets do Docker Swarm para credenciais sensíveis

### Persistência

- Os dados são armazenados em `[nome]_data/`
- Os logs são armazenados em `[nome]_logs/`
- As definições estão em `[nome]_definitions/definitions.json`
- Esses diretórios são preservados mesmo após parar a stack

### Atualização da Versão

Para atualizar a versão do RabbitMQ:

1. Edite o `docker-compose.yml` e altere a tag da imagem:
   ```yaml
   image: rabbitmq:3.13.3-management  # Altere para a nova versão
   ```

2. Faça pull da nova imagem:
   ```bash
   docker pull rabbitmq:[nova-versao]-management
   ```

3. Atualize a stack:
   ```bash
   ./stop_stack.sh
   ./start_stack.sh
   ```

### Backup

Para fazer backup dos dados:

```bash
# Backup dos dados
tar -czf rabbitmq_data_backup_$(date +%Y%m%d).tar.gz [nome]_data/

# Backup das definições
cp [nome]_definitions/definitions.json definitions_backup_$(date +%Y%m%d).json
```

## 🔗 Recursos Adicionais

- [Documentação Oficial do RabbitMQ](https://www.rabbitmq.com/documentation.html)
- [RabbitMQ Management Plugin](https://www.rabbitmq.com/management.html)
- [Docker Swarm Documentation](https://docs.docker.com/engine/swarm/)
- [RabbitMQ Docker Hub](https://hub.docker.com/_/rabbitmq)

## 📄 Licença

Este projeto é fornecido como está, sem garantias. Use por sua conta e risco.

---

**Desenvolvido para facilitar o deploy e gerenciamento do RabbitMQ com Docker Swarm.**
