 README — `handin_mgr`

 Descrição

`handin_mgr` é um programa em **POSIX sh** que junta duas partes no mesmo ficheiro:

- **gestão de tarefas** (`todo`)
- **gestão e validação de entregas** (`handin`)

O programa guarda o estado de forma persistente em:

```sh
$HOME/.handin_mgr/
```

Nessa pasta ficam, entre outros, os seguintes elementos:

- `todos.csv` — base de dados simples das tarefas
- `runs/` — relatórios gerados durante a execução
- `locks/` — controlo de lock para evitar conflitos de escrita

O ficheiro principal do trabalho é:

```sh
handin_mgr
```

O programa pode ser usado de **duas formas**:

1. **modo direto**, escrevendo o comando logo na execução
2. **modo interativo**, arrancando o programa sem argumentos

---

Como executar cada comando

```sh
./handin_mgr <comando> [opções] [argumentos]
./handin_mgr -h
./handin_mgr <comando> -h
```

### Modo interativo

```sh
./handin_mgr
```

Depois aparece um prompt parecido com:

```text
shell>
```

Nesse modo, os comandos devem ser escritos com o nome do programa no início:

```sh
handin_mgr todo-list
handin_mgr todo-search README
```

> Nota: para evitar problemas com títulos que têm espaços, o mais seguro é usar o **modo direto**.

---

## Comandos disponíveis

### 1) `todo-add`

Cria uma nova tarefa.

```sh
./handin_mgr todo-add "titulo" [-p P] [-d AAAA-MM-DD] [-t tag1,tag2]
```

**Opções:**

- `-p P` → prioridade de `1` a `5`
- `-d AAAA-MM-DD` → data limite
- `-t tag1,tag2` → lista de tags separadas por vírgulas

**Comportamento:**

- a tarefa fica com estado `OPEN`
- a prioridade por omissão é `3`
- o título e as tags são limpos para evitar `;` e mudanças de linha
- a tarefa fica guardada em `todos.csv`

---

### 2) `todo-list`

Lista as tarefas guardadas.

```sh
./handin_mgr todo-list [-a] [-s due|prio|created] [-t tag] [-p minPrio]
```

**Opções:**

- `-a` → mostra tarefas `OPEN` e `DONE`
- `-s due` → ordena por prazo
- `-s prio` → ordena por prioridade
- `-s created` → ordena por data de criação
- `-t tag` → mostra só tarefas com essa tag
- `-p minPrio` → mostra só tarefas com prioridade maior ou igual ao valor indicado

**Comportamento:**

- sem `-a`, mostra apenas tarefas `OPEN`
- a saída aparece num formato legível

Exemplo de saída:

```text
[3] (P4) 2026-04-05 OPEN tags:so,tp1 - Rever README
```

---

### 3) `todo-done`

Marca uma tarefa como concluída.

```sh
./handin_mgr todo-done <id>
```

**Comportamento:**

- altera o estado da tarefa para `DONE`
- regista a data/hora de conclusão
- se a tarefa já estiver concluída, o programa informa isso

---

### 4) `todo-search`

Pesquisa texto no título das tarefas.

```sh
./handin_mgr todo-search <texto>
```

**Comportamento:**

- a pesquisa é feita sem distinguir maiúsculas e minúsculas
- procura apenas no campo do título

---

### 5) `handin-ingest`

Importa entregas para um repositório organizado.

```sh
./handin_mgr handin-ingest <inbox_dir> <repo_dir> [-m]
```

**Argumentos:**

- `inbox_dir` → pasta onde estão as entregas recebidas
- `repo_dir` → pasta do repositório final
- `-m` → em vez de copiar, move a entrega

**Comportamento:**

- lê apenas o **primeiro nível** de `inbox_dir`
- aceita:
  - diretórios
  - ficheiros `.zip`
  - ficheiros `.tar`
  - ficheiros `.tar.gz`
- o nome da entrega deve seguir o formato:

```text
ALUNO_UC_TP#_YYYYMMDDHHMM
```

Exemplo:

```text
a12345_SO_TP1_202602131845
```

As entregas válidas ficam organizadas em:

```text
<repo_dir>/<UC>/<TP#>/<ALUNO>/<timestamp>/
```

É também criado um relatório em:

```text
$HOME/.handin_mgr/runs/
```

---

### 6) `handin-check`

Valida as entregas guardadas no repositório.

```sh
./handin_mgr handin-check <repo_dir> [-o relatorio.csv]
```

**Validações feitas:**

- existência de `README.md` ou `README.txt`
- existência de pasta `src/` com pelo menos 1 ficheiro
- ausência de diretórios proibidos:
  - `node_modules`
  - `dist`
  - `build`
- ausência de ficheiros binários
- ausência de ficheiros com mais de **5 MB**

**Saída:**

o programa gera linhas no formato:

```text
UC;TP#;ALUNO;timestamp;STATUS;num_src_files;total_files;total_lines;problemas
```

O `STATUS` pode ser:

- `OK`
- `FAIL`

Se a entrega falhar e a opção estiver ativa internamente nesse comando, o programa cria automaticamente uma tarefa em `todos.csv` para lembrar a correção da entrega.

---

### 7) `handin-summary`

Mostra um resumo agregado das entregas.

```sh
./handin_mgr handin-summary <repo_dir> [-u UC] [-t TP#]
```

**Opções:**

- `-u UC` → filtra por unidade curricular
- `-t TP#` → filtra por trabalho prático

**Comportamento:**

- mostra o total de entregas
- mostra quantas estão `OK`
- mostra quantas estão `FAIL`
- mostra o top 5 por número de ficheiros
- mostra o top 5 por número de linhas
- mostra os alunos com pelo menos uma entrega com falha

---

## Exemplos

### Exemplos da parte das tarefas

```sh
# criar uma tarefa simples
./handin_mgr todo-add "Estudar shell script"

# criar tarefa com prioridade, prazo e tags
./handin_mgr todo-add "Rever README do TP1" -p 4 -d 2026-04-05 -t so,tp1

# listar tarefas abertas
./handin_mgr todo-list

# listar todas as tarefas
./handin_mgr todo-list -a

# listar por prioridade
./handin_mgr todo-list -s prio

# filtrar por tag
./handin_mgr todo-list -t tp1

# procurar uma palavra no título
./handin_mgr todo-search README

# marcar a tarefa 2 como concluída
./handin_mgr todo-done 2
```

### Exemplos da parte das entregas

```sh
# importar entregas copiando para o repositório
./handin_mgr handin-ingest ./inbox ./repo

# importar entregas movendo para o repositório
./handin_mgr handin-ingest ./inbox ./repo -m

# validar o repositório e mostrar no terminal
./handin_mgr handin-check ./repo

# validar o repositório e guardar num CSV
./handin_mgr handin-check ./repo -o relatorio.csv

# mostrar resumo geral
./handin_mgr handin-summary ./repo

# mostrar resumo apenas da UC SO
./handin_mgr handin-summary ./repo -u SO

# mostrar resumo apenas do TP1
./handin_mgr handin-summary ./repo -t TP1

# mostrar resumo filtrado por UC e TP
./handin_mgr handin-summary ./repo -u SO -t TP1
```

### Exemplo em modo interativo

```sh
./handin_mgr
```

Depois:

```sh
handin_mgr todo-list
handin_mgr todo-search README
```

---

## Limitações e suposições

- O programa assume que o ficheiro principal se chama `handin_mgr`.
- O repositório indicado em `handin-ingest` **já tem de existir** antes da execução.
- O `handin-ingest` analisa apenas o primeiro nível da pasta `inbox_dir`.
- O nome das entregas tem de seguir exatamente o formato `ALUNO_UC_TP#_YYYYMMDDHHMM`.
- Os campos `ALUNO` e `UC` são validados como alfanuméricos simples, sem espaços nem símbolos especiais.
- O `TP` tem de seguir o formato `TP` seguido de número, por exemplo `TP1`.
- A data em `todo-add` é validada apenas no formato `AAAA-MM-DD`; não há validação completa do calendário real.
- O título e as tags são sanitizados para evitar `;` e mudanças de linha.
- A deteção de ficheiros binários é feita com `grep -Iq .`, por isso pode depender do ambiente.
- O limite de tamanho de ficheiro é **5 MB**.
- A extração de `.zip`, `.tar` e `.tar.gz` depende das ferramentas disponíveis no sistema, como `unzip` e `tar`.
- Se essas ferramentas não existirem, o programa guarda o ficheiro comprimido sem extrair.
- Nesses casos, o `handin-check` pode marcar a entrega com falhas como `missing_readme` e `missing_src`, porque o conteúdo não foi descomprimido.
- O controlo de lock é feito por diretório em `locks/`; se o programa for interrompido de forma anormal, pode ser necessário remover o lock manualmente.

---

## Conclusão

O `handin_mgr` permite gerir tarefas e entregas no mesmo programa, usando apenas shell script e ficheiros simples. A solução foi feita para ser prática, legível e fácil de testar no terminal.



Tomás Ferreira Abrantes
Leonardo Mendes
