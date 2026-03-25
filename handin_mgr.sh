#!/bin/sh

PROG=$(basename "$0")

STATE=${HOME:-.}/.handin_mgr
TODOS=$STATE/todos.csv
RUNS=$STATE/runs
LOCKS=$STATE/locks
LOCKDIR=$LOCKS/main.lock
LIMIT_MB=5
LIMIT_BYTES=5242880

err() {
    printf '%s\n' "$*" >&2
}

die() {
    err "$*"
    exit 1
}

ensure_state() {
    [ -d "$STATE" ] || mkdir -p "$STATE" || die "Erro ao criar $STATE"
    [ -d "$RUNS" ] || mkdir -p "$RUNS" || die "Erro ao criar $RUNS"
    [ -d "$LOCKS" ] || mkdir -p "$LOCKS" || die "Erro ao criar $LOCKS"
    [ -f "$TODOS" ] || : > "$TODOS" || die "Erro ao criar $TODOS"
}

print_general_help() {
    cat <<EOF
Uso:
  $PROG todo-add "titulo" [-p P] [-d AAAA-MM-DD] [-t tag1,tag2]
  $PROG todo-list [-a] [-s due|prio|created] [-t tag] [-p minPrio]
  $PROG todo-done <id>
  $PROG todo-search <texto>
  $PROG handin-ingest <inbox_dir> <repo_dir> [-m]
  $PROG handin-check <repo_dir> [-o relatorio.csv]
  $PROG handin-summary <repo_dir> [-u UC] [-t TP#]

Ajuda:
  $PROG -h
  $PROG <comando> -h

Modo interativo:
  executar ./$PROG sem argumentos
EOF
}

print_todo_add_help() {
    cat <<EOF
Uso: $PROG todo-add "titulo" [-p P] [-d AAAA-MM-DD] [-t tag1,tag2]
Cria uma tarefa OPEN persistente em $TODOS.
EOF
}

print_todo_list_help() {
    cat <<EOF
Uso: $PROG todo-list [-a] [-s due|prio|created] [-t tag] [-p minPrio]
Lista tarefas em formato legivel.
EOF
}

print_todo_done_help() {
    cat <<EOF
Uso: $PROG todo-done <id>
Marca a tarefa indicada como DONE.
EOF
}

print_todo_search_help() {
    cat <<EOF
Uso: $PROG todo-search <texto>
Procura texto no titulo, sem distinguir maiusculas de minusculas.
EOF
}

print_handin_ingest_help() {
    cat <<EOF
Uso: $PROG handin-ingest <inbox_dir> <repo_dir> [-m]
Importa entregas do inbox para o repositorio.
EOF
}

print_handin_check_help() {
    cat <<EOF
Uso: $PROG handin-check <repo_dir> [-o relatorio.csv]
Valida entregas e produz um relatorio CSV.
EOF
}

print_handin_summary_help() {
    cat <<EOF
Uso: $PROG handin-summary <repo_dir> [-u UC] [-t TP#]
Mostra um resumo agregado das entregas.
EOF
}

now_iso() {
    date '+%Y-%m-%d %H:%M:%S'
}

now_run_id() {
    date '+%Y-%m-%d_%H%M%S'
}

sanitize_field() {
    printf '%s' "$1" | tr '\n' ' ' | tr ';' ','
}

is_iso_date() {
    printf '%s\n' "$1" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
}

is_prio() {
    case $1 in
        1|2|3|4|5) return 0 ;;
        *) return 1 ;;
    esac
}

is_positive_int() {
    printf '%s\n' "$1" | grep -Eq '^[1-9][0-9]*$'
}

is_timestamp12() {
    printf '%s\n' "$1" | grep -Eq '^[0-9]{12}$'
}

is_alnum_simple() {
    printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9]+$'
}

is_tp() {
    printf '%s\n' "$1" | grep -Eq '^TP[0-9]+$'
}

acquire_lock() {
    mkdir "$LOCKDIR" 2>/dev/null || die "Estado bloqueado: $LOCKDIR"
}

release_lock() {
    rmdir "$LOCKDIR" 2>/dev/null || :
}

next_todo_id() {
    awk -F';' 'BEGIN{m=0} NF>=1 && $1+0>m{m=$1+0} END{print m+1}' "$TODOS"
}

add_problem() {
    case ",$PROBLEMS," in
        *,"$1",*) ;;
        *,) PROBLEMS=$1 ;;
        *) PROBLEMS=$PROBLEMS,$1 ;;
    esac
}

format_todo_stream() {
    awk -F';' '
    {
        due=$4
        tags=$5
        if (due=="") due="-"
        if (tags=="") tags="-"
        printf("[%s] (P%s) %s %s tags:%s - %s\n", $1, $3, due, $2, tags, $8)
    }'
}

list_submission_dirs() {
    find "$1" -mindepth 4 -maxdepth 4 -type d 2>/dev/null | sort
}

parse_submission_name() {
    name=$1
    oldIFS=$IFS
    IFS=_
    set -- $name
    IFS=$oldIFS
    [ $# -eq 4 ] || return 1
    aluno=$1
    uc=$2
    tp=$3
    ts=$4
    is_alnum_simple "$aluno" || return 1
    is_alnum_simple "$uc" || return 1
    is_tp "$tp" || return 1
    is_timestamp12 "$ts" || return 1
    printf '%s;%s;%s;%s\n' "$aluno" "$uc" "$tp" "$ts"
}

base_from_archive() {
    name=$1
    case $name in
        *.tar.gz) printf '%s\n' "${name%.tar.gz}" ;;
        *.tar) printf '%s\n' "${name%.tar}" ;;
        *.zip) printf '%s\n' "${name%.zip}" ;;
        *) return 1 ;;
    esac
}

has_extract_tool() {
    case $1 in
        zip)
            command -v unzip >/dev/null 2>&1
            ;;
        tar|targz)
            command -v tar >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

flatten_single_subdir() {
    dest=$1
    count=$(find "$dest" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
    [ "$count" -eq 1 ] || return 0
    only=$(find "$dest" -mindepth 1 -maxdepth 1 -type d)
    [ -n "$only" ] || return 0
    find "$only" -mindepth 1 -maxdepth 1 -exec mv {} "$dest"/ \;
    rmdir "$only" 2>/dev/null || :
}

append_report_line() {
    report_file=$1
    shift
    printf '%s\n' "$*" >> "$report_file" || die "Erro a escrever relatorio"
}

copy_or_move_dir() {
    src=$1
    dest=$2
    mode=$3
    parent=$(dirname "$dest")
    mkdir -p "$parent" || return 1
    if [ "$mode" = "move" ]; then
        mv "$src" "$dest"
    else
        cp -R "$src" "$dest"
    fi
}

extract_or_store_archive() {
    src=$1
    dest=$2
    mode=$3
    mkdir -p "$dest" || return 1
    case $src in
        *.zip)
            if has_extract_tool zip; then
                unzip -qq "$src" -d "$dest" || return 1
                flatten_single_subdir "$dest"
                [ "$mode" = "move" ] && rm -f "$src"
            else
                if [ "$mode" = "move" ]; then
                    mv "$src" "$dest"/
                else
                    cp "$src" "$dest"/
                fi
            fi
            ;;
        *.tar.gz)
            if has_extract_tool targz; then
                tar -xzf "$src" -C "$dest" || return 1
                flatten_single_subdir "$dest"
                [ "$mode" = "move" ] && rm -f "$src"
            else
                if [ "$mode" = "move" ]; then
                    mv "$src" "$dest"/
                else
                    cp "$src" "$dest"/
                fi
            fi
            ;;
        *.tar)
            if has_extract_tool tar; then
                tar -xf "$src" -C "$dest" || return 1
                flatten_single_subdir "$dest"
                [ "$mode" = "move" ] && rm -f "$src"
            else
                if [ "$mode" = "move" ]; then
                    mv "$src" "$dest"/
                else
                    cp "$src" "$dest"/
                fi
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

append_superseded_lines() {
    repo_dir=$1
    report_file=$2
    list_submission_dirs "$repo_dir" |
    awk -F/ '
    {
        ts=$NF
        aluno=$(NF-1)
        tp=$(NF-2)
        uc=$(NF-3)
        printf "%s;%s;%s;%s;%s\n", aluno, uc, tp, ts, $0
    }' |
    sort -t';' -k1,1 -k2,2 -k3,3 -k4,4 |
    awk -F';' '
    {
        key=$1 FS $2 FS $3
        if (prev_key==key && prev_path!="") {
            print prev_path
        }
        prev_key=key
        prev_path=$5
    }' |
    while IFS= read -r oldpath; do
        [ -n "$oldpath" ] || continue
        append_report_line "$report_file" "SUPERSEDED;$oldpath;entrega_mais_recente_existe"
    done
}

ensure_failure_todo() {
    aluno=$1
    uc=$2
    tp=$3
    motivos=$4

    title="Corrigir entrega $aluno $uc $tp ($motivos)"
    tags="handin,$uc,$tp"
    prio=4
    case ",$motivos," in
        *,missing_src,*|*,binary_found,*) prio=5 ;;
    esac

    acquire_lock
    if awk -F';' -v title="$title" '$8==title{found=1} END{exit !found}' "$TODOS"; then
        release_lock
        return 0
    fi

    id=$(next_todo_id)
    created=$(now_iso)
    printf '%s;%s;%s;%s;%s;%s;%s;%s\n' \
        "$id" "OPEN" "$prio" "" "$tags" "$created" "" "$title" >> "$TODOS" || {
        release_lock
        die "Erro a escrever em $TODOS"
    }
    release_lock
}

check_has_readme() {
    root=$1
    [ -f "$root/README.md" ] || [ -f "$root/README.txt" ]
}

count_src_files() {
    root=$1
    if [ -d "$root/src" ]; then
        find "$root/src" -type f 2>/dev/null | wc -l | tr -d ' '
    else
        printf '0\n'
    fi
}

count_total_files() {
    root=$1
    find "$root" -type f 2>/dev/null | wc -l | tr -d ' '
}

count_total_lines_text_src() {
    root=$1
    if [ ! -d "$root/src" ]; then
        printf '0\n'
        return 0
    fi
    find "$root/src" -type f -exec sh -c '
        f=$1
        if grep -Iq . "$f" 2>/dev/null; then
            wc -l < "$f"
        else
            printf "0\n"
        fi
    ' sh {} \; 2>/dev/null | awk '{s+=$1} END{print s+0}'
}

has_forbidden_dir() {
    root=$1
    find "$root" -type d \( -name node_modules -o -name dist -o -name build \) -print 2>/dev/null | grep . >/dev/null 2>&1
}

has_binary_file() {
    root=$1
    find "$root" -type f -exec sh -c '
        f=$1
        if ! grep -Iq . "$f" 2>/dev/null; then
            printf "yes\n"
        fi
    ' sh {} \; 2>/dev/null | grep . >/dev/null 2>&1
}

has_large_file() {
    root=$1
    find "$root" -type f -exec sh -c '
        limit=$1
        f=$2
        size=$(wc -c < "$f" | tr -d " ")
        if [ "$size" -gt "$limit" ]; then
            printf "yes\n"
        fi
    ' sh "$LIMIT_BYTES" {} \; 2>/dev/null | grep . >/dev/null 2>&1
}

build_check_line() {
    dir=$1
    create_todos=$2

    timestamp=$(basename "$dir")
    aluno=$(basename "$(dirname "$dir")")
    tp=$(basename "$(dirname "$(dirname "$dir")")")
    uc=$(basename "$(dirname "$(dirname "$(dirname "$dir")")")")

    PROBLEMS=

    is_alnum_simple "$uc" || add_problem invalid_uc
    is_tp "$tp" || add_problem invalid_tp
    is_alnum_simple "$aluno" || add_problem invalid_aluno
    is_timestamp12 "$timestamp" || add_problem invalid_timestamp

    if ! check_has_readme "$dir"; then
        add_problem missing_readme
    fi

    num_src_files=$(count_src_files "$dir")
    if [ "$num_src_files" -eq 0 ]; then
        add_problem missing_src
    fi

    if has_forbidden_dir "$dir"; then
        add_problem forbidden_dir
    fi

    if has_binary_file "$dir"; then
        add_problem binary_found
    fi

    if has_large_file "$dir"; then
        add_problem too_large
    fi

    total_files=$(count_total_files "$dir")
    total_lines=$(count_total_lines_text_src "$dir")

    if [ -n "$PROBLEMS" ]; then
        status=FAIL
        [ "$create_todos" = "1" ] && ensure_failure_todo "$aluno" "$uc" "$tp" "$PROBLEMS"
    else
        status=OK
    fi

    printf '%s;%s;%s;%s;%s;%s;%s;%s;%s\n' \
        "$uc" "$tp" "$aluno" "$timestamp" "$status" "$num_src_files" "$total_files" "$total_lines" "$PROBLEMS"
}

build_check_report() {
    repo_dir=$1
    report_out=$2
    create_todos=$3

    : > "$report_out" || die "Erro a escrever em $report_out"

    list_submission_dirs "$repo_dir" | while IFS= read -r dir; do
        build_check_line "$dir" "$create_todos" >> "$report_out"
    done
}

cmd_todo_add() {
    [ "${1-}" = "-h" ] && {
        print_todo_add_help
        return 0
    }

    [ $# -ge 1 ] || die "Falta o titulo"

    title=$1
    shift
    prio=3
    due=
    tags=

    while [ $# -gt 0 ]; do
        case $1 in
            -p)
                shift
                [ $# -gt 0 ] || die "Falta valor para -p"
                prio=$1
                ;;
            -d)
                shift
                [ $# -gt 0 ] || die "Falta valor para -d"
                due=$1
                ;;
            -t)
                shift
                [ $# -gt 0 ] || die "Falta valor para -t"
                tags=$1
                ;;
            *)
                die "Opcao invalida em todo-add: $1"
                ;;
        esac
        shift
    done

    is_prio "$prio" || die "Prioridade invalida: use 1..5"
    [ -z "$due" ] || is_iso_date "$due" || die "Data invalida: use AAAA-MM-DD"

    title=$(sanitize_field "$title")
    tags=$(sanitize_field "$tags")
    created=$(now_iso)

    acquire_lock
    id=$(next_todo_id)
    printf '%s;%s;%s;%s;%s;%s;%s;%s\n' \
        "$id" "OPEN" "$prio" "$due" "$tags" "$created" "" "$title" >> "$TODOS" || {
        release_lock
        die "Erro a escrever em $TODOS"
    }
    release_lock

    printf 'Tarefa criada com id %s\n' "$id"
}

cmd_todo_list() {
    [ "${1-}" = "-h" ] && {
        print_todo_list_help
        return 0
    }

    show_all=0
    sort_by=
    tag=
    min_prio=

    while [ $# -gt 0 ]; do
        case $1 in
            -a)
                show_all=1
                ;;
            -s)
                shift
                [ $# -gt 0 ] || die "Falta valor para -s"
                sort_by=$1
                ;;
            -t)
                shift
                [ $# -gt 0 ] || die "Falta valor para -t"
                tag=$1
                ;;
            -p)
                shift
                [ $# -gt 0 ] || die "Falta valor para -p"
                min_prio=$1
                ;;
            *)
                die "Opcao invalida em todo-list: $1"
                ;;
        esac
        shift
    done

    case $sort_by in
        ''|due|prio|created) ;;
        *) die "Ordenacao invalida: use due, prio ou created" ;;
    esac

    [ -z "$min_prio" ] || is_prio "$min_prio" || die "minPrio invalido: use 1..5"

    records=$(awk -F';' -v show_all="$show_all" -v tag="$tag" -v minp="$min_prio" '
        function has_tag(tags, wanted,   n, a, i) {
            if (wanted == "") return 1
            n = split(tags, a, ",")
            for (i = 1; i <= n; i++) if (a[i] == wanted) return 1
            return 0
        }
        {
            if (show_all != 1 && $2 != "OPEN") next
            if (minp != "" && ($3 + 0) < (minp + 0)) next
            if (!has_tag($5, tag)) next
            print $0
        }
    ' "$TODOS")

    [ -n "$records" ] || return 0

    case $sort_by in
        due)
            printf '%s\n' "$records" |
            awk -F';' 'BEGIN{OFS=";"} {k=$4; if(k=="") k="9999-99-99"; print k,$0}' |
            sort -t';' -k1,1 | cut -d';' -f2- |
            format_todo_stream
            ;;
        prio)
            printf '%s\n' "$records" | sort -t';' -k3,3nr | format_todo_stream
            ;;
        created)
            printf '%s\n' "$records" | sort -t';' -k6,6 | format_todo_stream
            ;;
        *)
            printf '%s\n' "$records" | format_todo_stream
            ;;
    esac
}

cmd_todo_done() {
    [ "${1-}" = "-h" ] && {
        print_todo_done_help
        return 0
    }

    [ $# -eq 1 ] || die "Uso: $PROG todo-done <id>"
    id=$1
    is_positive_int "$id" || die "id invalido"

    line=$(awk -F';' -v id="$id" '$1==id{print; exit}' "$TODOS")
    [ -n "$line" ] || die "id inexistente"

    oldIFS=$IFS
    IFS=';'
    set -- $line
    IFS=$oldIFS

    if [ "$2" = "DONE" ]; then
        printf 'A tarefa %s ja estava DONE\n' "$id"
        return 0
    fi

    done_at=$(now_iso)
    tmp=$STATE/todos.tmp.$$ 

    acquire_lock
    awk -F';' -v id="$id" -v done_at="$done_at" 'BEGIN{OFS=";"}
        $1==id {$2="DONE"; $7=done_at}
        {print}
    ' "$TODOS" > "$tmp" || {
        release_lock
        rm -f "$tmp"
        die "Erro a atualizar tarefa"
    }
    mv "$tmp" "$TODOS" || {
        release_lock
        rm -f "$tmp"
        die "Erro a guardar $TODOS"
    }
    release_lock

    printf 'Tarefa %s marcada como DONE\n' "$id"
}

cmd_todo_search() {
    [ "${1-}" = "-h" ] && {
        print_todo_search_help
        return 0
    }

    [ $# -ge 1 ] || die "Falta o texto"
    text=$1

    awk -F';' -v q="$text" '
        index(tolower($8), tolower(q)) > 0 {print}
    ' "$TODOS" | format_todo_stream
}

cmd_handin_ingest() {
    [ "${1-}" = "-h" ] && {
        print_handin_ingest_help
        return 0
    }

    inbox_dir=
    repo_dir=
    mode=copy

    while [ $# -gt 0 ]; do
        case $1 in
            -m)
                mode=move
                ;;
            -*)
                die "Opcao invalida em handin-ingest: $1"
                ;;
            *)
                if [ -z "$inbox_dir" ]; then
                    inbox_dir=$1
                elif [ -z "$repo_dir" ]; then
                    repo_dir=$1
                else
                    die "Argumentos a mais em handin-ingest"
                fi
                ;;
        esac
        shift
    done

    [ -n "$inbox_dir" ] || die "Falta inbox_dir"
    [ -n "$repo_dir" ] || die "Falta repo_dir"
    [ -d "$inbox_dir" ] || die "inbox_dir inexistente"
    [ -r "$inbox_dir" ] || die "Sem permissao de leitura em inbox_dir"
    [ -d "$repo_dir" ] || die "repo_dir inexistente"
    [ -w "$repo_dir" ] || die "Sem permissao de escrita em repo_dir"

    report="$RUNS/ingest_$(now_run_id).txt"

    acquire_lock
    : > "$report" || {
        release_lock
        die "Erro a criar relatorio"
    }

    find "$inbox_dir" -mindepth 1 -maxdepth 1 \( -type d -o -type f \) | while IFS= read -r src; do
        base=$(basename "$src")
        kind=
        subname=

        if [ -d "$src" ]; then
            subname=$base
            kind=dir
        elif [ -f "$src" ]; then
            case $base in
                *.zip|*.tar|*.tar.gz)
                    subname=$(base_from_archive "$base") || subname=
                    kind=archive
                    ;;
                *)
                    continue
                    ;;
            esac
        else
            continue
        fi

        parsed=$(parse_submission_name "$subname") || {
            append_report_line "$report" "FAIL;$src;nome_invalido"
            continue
        }

        oldIFS=$IFS
        IFS=';'
        set -- $parsed
        IFS=$oldIFS
        aluno=$1
        uc=$2
        tp=$3
        ts=$4
        dest="$repo_dir/$uc/$tp/$aluno/$ts"

        if [ -e "$dest" ]; then
            append_report_line "$report" "FAIL;$src;destino_ja_existe"
            continue
        fi

        if [ "$kind" = "dir" ]; then
            if copy_or_move_dir "$src" "$dest" "$mode"; then
                append_report_line "$report" "OK;$src;$dest"
            else
                append_report_line "$report" "FAIL;$src;erro_a_copiar_ou_mover"
            fi
        else
            if extract_or_store_archive "$src" "$dest" "$mode"; then
                append_report_line "$report" "OK;$src;$dest"
            else
                rm -rf "$dest"
                append_report_line "$report" "FAIL;$src;erro_a_importar_arquivo"
            fi
        fi
    done

    append_superseded_lines "$repo_dir" "$report"
    release_lock

    printf 'Relatorio criado em %s\n' "$report"
}

cmd_handin_check() {
    [ "${1-}" = "-h" ] && {
        print_handin_check_help
        return 0
    }

    repo_dir=
    output=

    while [ $# -gt 0 ]; do
        case $1 in
            -o)
                shift
                [ $# -gt 0 ] || die "Falta valor para -o"
                output=$1
                ;;
            -*)
                die "Opcao invalida em handin-check: $1"
                ;;
            *)
                if [ -z "$repo_dir" ]; then
                    repo_dir=$1
                else
                    die "Argumentos a mais em handin-check"
                fi
                ;;
        esac
        shift
    done

    [ -n "$repo_dir" ] || die "Falta repo_dir"
    [ -d "$repo_dir" ] || die "repo_dir inexistente"

    tmp=$STATE/check.tmp.$$
    build_check_report "$repo_dir" "$tmp" 1

    if [ -n "$output" ]; then
        cp "$tmp" "$output" || {
            rm -f "$tmp"
            die "Erro a escrever relatorio"
        }
    else
        cat "$tmp"
    fi

    rm -f "$tmp"
}

cmd_handin_summary() {
    [ "${1-}" = "-h" ] && {
        print_handin_summary_help
        return 0
    }

    repo_dir=
    filter_uc=
    filter_tp=

    while [ $# -gt 0 ]; do
        case $1 in
            -u)
                shift
                [ $# -gt 0 ] || die "Falta valor para -u"
                filter_uc=$1
                ;;
            -t)
                shift
                [ $# -gt 0 ] || die "Falta valor para -t"
                filter_tp=$1
                ;;
            -*)
                die "Opcao invalida em handin-summary: $1"
                ;;
            *)
                if [ -z "$repo_dir" ]; then
                    repo_dir=$1
                else
                    die "Argumentos a mais em handin-summary"
                fi
                ;;
        esac
        shift
    done

    [ -n "$repo_dir" ] || die "Falta repo_dir"
    [ -d "$repo_dir" ] || die "repo_dir inexistente"

    tmp=$STATE/summary.tmp.$$
    filtered=$STATE/summary.filtered.$$

    build_check_report "$repo_dir" "$tmp" 0

    awk -F';' -v uc="$filter_uc" -v tp="$filter_tp" '
        (uc=="" || $1==uc) && (tp=="" || $2==tp) {print}
    ' "$tmp" > "$filtered"

    total=$(wc -l < "$filtered" | tr -d ' ')
    ok_count=$(awk -F';' '$5=="OK"{n++} END{print n+0}' "$filtered")
    fail_count=$(awk -F';' '$5=="FAIL"{n++} END{print n+0}' "$filtered")

    printf 'Resumo de entregas\n'
    printf '==================\n'
    [ -n "$filter_uc" ] && printf 'Filtro UC: %s\n' "$filter_uc"
    [ -n "$filter_tp" ] && printf 'Filtro TP: %s\n' "$filter_tp"
    printf 'Total de entregas: %s\n' "$total"
    printf 'OK: %s\n' "$ok_count"
    printf 'FAIL: %s\n' "$fail_count"

    printf '\nTop 5 por numero de ficheiros\n'
    printf '%s\n' '----------------------------'
    sort -t';' -k7,7nr "$filtered" | \
    awk -F';' 'NR<=5{printf "%d. %s %s %s %s - %s ficheiros\n", NR, $1, $2, $3, $4, $7}'

    printf '\nTop 5 por numero de linhas\n'
    printf '%s\n' '-------------------------'
    sort -t';' -k8,8nr "$filtered" | \
    awk -F';' 'NR<=5{printf "%d. %s %s %s %s - %s linhas\n", NR, $1, $2, $3, $4, $8}'

    printf '\nAlunos com pelo menos uma entrega FAIL\n'
    printf '%s\n' '--------------------------------------'
    awk -F';' '$5=="FAIL"{print $3}' "$filtered" | sort | uniq | awk '{printf "- %s\n", $0}'

    rm -f "$tmp" "$filtered"
}

dispatch() {
    [ $# -gt 0 ] || {
        err "Falta comando"
        return 1
    }

    case $1 in
        todo-add)
            shift
            cmd_todo_add "$@"
            ;;
        todo-list)
            shift
            cmd_todo_list "$@"
            ;;
        todo-done)
            shift
            cmd_todo_done "$@"
            ;;
        todo-search)
            shift
            cmd_todo_search "$@"
            ;;
        handin-ingest)
            shift
            cmd_handin_ingest "$@"
            ;;
        handin-check)
            shift
            cmd_handin_check "$@"
            ;;
        handin-summary)
            shift
            cmd_handin_summary "$@"
            ;;
        -h|--help)
            print_general_help
            ;;
        *)
            err "Comando invalido: $1"
            return 1
            ;;
    esac
}

run_shell() {
    ensure_state

    printf 'Shell interativa de %s\n' "$PROG"
    printf 'Escreve help para ajuda e exit para sair\n'

    while :; do
        printf 'shell> '
        IFS= read -r line || {
            printf '\n'
            break
        }

        case $line in
            '')
                continue
                ;;
            exit)
                break
                ;;
            help)
                print_general_help
                continue
                ;;
            "$PROG "*)
                cmdline=${line#"$PROG "}
                ;;
            "$PROG")
                err "Falta o comando"
                continue
                ;;
            *)
                err "Usa comandos no formato: $PROG <comando> ..."
                continue
                ;;
        esac

        set -- $cmdline
        [ $# -gt 0 ] || continue

        dispatch "$@"
        rc=$?
        [ "$rc" -eq 0 ] || err "Comando terminou com codigo $rc"
    done
}

ensure_state

if [ $# -gt 0 ]; then
    dispatch "$@"
else
    run_shell
fi
