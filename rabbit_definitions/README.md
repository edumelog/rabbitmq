# 📋 Definições do RabbitMQ

Este diretório contém as definições do RabbitMQ que são carregadas automaticamente na inicialização.

## 📁 Arquivos

- **`definitions.json.example`** - Arquivo de exemplo com uma fila e tratamento de Dead Letter
- **`definitions.json`** - Arquivo de configuração real (criado a partir do exemplo)

## 🚀 Como Usar

### Opção 1: Usar o Gerador Interativo (Recomendado)

Execute o script na raiz do projeto:

```bash
./generate_definitions.sh
```

O script irá:
- Explicar o que é definitions.json
- Perguntar nome e senha do administrador
- Perguntar quais filas criar
- Perguntar se cada fila deve ter Dead Letter
- Gerar o arquivo definitions.json automaticamente

### Opção 2: Copiar e Editar Manualmente

```bash
# 1. Copiar o arquivo de exemplo
cp definitions.json.example definitions.json

# 2. Editar o definitions.json
nano definitions.json
# ou
vim definitions.json
```

### 3. Estrutura do Arquivo

O arquivo JSON contém as seguintes seções:

#### **users** - Usuários do RabbitMQ
```json
{
  "name": "admin",
  "password": "sua_senha_segura",
  "tags": "administrator"
}
```

#### **exchanges** - Exchanges para roteamento
- **direct**: Roteia mensagens baseado no routing_key exato
- **fanout**: Envia mensagens para todas as filas vinculadas (usado para DLX)
- **topic**: Roteia baseado em padrões de routing_key
- **headers**: Roteia baseado em headers da mensagem

#### **queues** - Filas de mensagens
```json
{
  "name": "nome.da.fila",
  "durable": true,
  "arguments": {
    "x-dead-letter-exchange": "dlx_exchange"
  }
}
```

#### **bindings** - Vinculações entre exchanges e filas
```json
{
  "source": "nome_exchange",
  "destination": "nome.fila",
  "routing_key": "chave.roteamento"
}
```

#### **policies** - Políticas globais
A política DLX aplica Dead Letter Exchange automaticamente a todas as filas.

## 💀 Dead Letter Exchange (DLX)

### O que é?

O Dead Letter Exchange é usado para tratar mensagens que não puderam ser processadas:
- Mensagens rejeitadas (nack)
- Mensagens expiradas (TTL)
- Mensagens que excederam o limite de tentativas

### Como Configurar

1. **Criar o exchange DLX** (tipo `fanout`):
```json
{
  "name": "dlx_exchange",
  "type": "fanout",
  "durable": true
}
```

2. **Configurar a fila principal** com DLX:
```json
{
  "name": "minha.fila",
  "arguments": {
    "x-dead-letter-exchange": "dlx_exchange"
  }
}
```

3. **Criar fila dead** para receber mensagens mortas:
```json
{
  "name": "minha.fila.dead",
  "durable": true
}
```

4. **Vincular fila dead ao DLX**:
```json
{
  "source": "dlx_exchange",
  "destination": "minha.fila.dead",
  "routing_key": ""
}
```

### Exemplo Completo

Veja o arquivo `definitions.json.example` para um exemplo completo com:
- 1 exchange de exemplo (`example_exchange`)
- 1 exchange DLX (`dlx_exchange`)
- 1 fila principal (`example.queue`) com DLX configurado
- 1 fila dead (`example.queue.dead`) vinculada ao DLX
- Política global DLX

## 🔄 Aplicar Mudanças

Após editar o `definitions.json`:

1. **Reiniciar a stack**:
```bash
./stop_stack.sh
./start_stack.sh
```

2. **Ou recarregar definições** (sem reiniciar):
```bash
docker exec -it $(docker ps -q -f name=rabbitmq) rabbitmqctl load_definitions /etc/rabbitmq/definitions.json
```

## 📝 Validação JSON

Antes de usar, valide o JSON:

```bash
# Com Python
python3 -m json.tool definitions.json > /dev/null && echo "JSON válido" || echo "JSON inválido"

# Com jq
jq . definitions.json > /dev/null && echo "JSON válido" || echo "JSON inválido"

# Online
# https://jsonlint.com/
```

## ⚠️ Importante

- **NUNCA** commite o `definitions.json` se contiver senhas reais
- Use o `.env` para credenciais sensíveis
- O arquivo é carregado automaticamente na inicialização do RabbitMQ
- Mudanças no arquivo requerem reinicialização ou reload das definições

## 🔗 Recursos

- [RabbitMQ Definitions](https://www.rabbitmq.com/definitions.html)
- [Dead Letter Exchanges](https://www.rabbitmq.com/dlx.html)
- [RabbitMQ Policies](https://www.rabbitmq.com/parameters.html#policies)

