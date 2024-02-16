#!/bin/bash

# This script is a wrapper around isort and ruff to lint Python files.
# To use this script, add it to the root of your project and run it with
# the desired options/flags. Make sure to have isort, ruff, and git installed.
# To enable it as a pre-commit hook, add the following to your
# .git/hooks/pre-commit file:
#
# #!/bin/bash
#
# LINT_SCRIPT="./lint.sh"
# $LINT_SCRIPT --files modified-cached --line-length 79
#
# if [ $? -ne 0 ]; then
#     echo "Linting failed, commit aborted."
#     exit 1
# fi
#
# if git diff --quiet; then
#     echo "No changes detected after linting."
# else
#     echo "Files were modified during linting."
#     echo "Please review the changes and re-add/re-commit again."
#     exit 1
# fi


DEFAULT_LINE_LENGTH=90
LINE_LENGTH=$DEFAULT_LINE_LENGTH
FILES_OPTION=""
DIFF=""
VERBOSE=""

EXCLUDE_PATTERN="\
(\/\.bzr|\/\.direnv|\/\.eggs|\/\.git|\/\.git-rewrite|\/\.hg|\
\/\.ipynb_checkpoints|\/\.mypy_cache|\/\.nox|\/\.pants\.d|\
\/\.pyenv|\/\.pytest_cache|\/\.pytype|\/\.ruff_cache|\/\.svn|\
\/\.tox|\/\.venv|\/\.vscode|\/__pypackages__|\/_build|\/buck-out|\
\/build|\/dist|\/node_modules|\/site-packages|\/venv)"

# Color setup, need to check if stdout is a terminal.
if [ -t 1 ]; then
    NC='\033[0m' # No Color
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
else
    NC=''
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
fi


display_header() {
    echo -e "${MAGENTA}"
    echo "  _     _       _     __  __       _     _           "
    echo " | |   (_) _ _ | |_  |  \/  | ___ (_)___| |_ ___ _ __ "
    echo " | |   | | '_ \| __| | |\/| |/ _ \| / __| __/ _ \ '__|"
    echo " | |___| | | | | |_  | |  | |  __/| \__ \ ||  __/ |   "
    echo " |_____|_|_| |_|\__| |_|  |_|\___||_|___/\__\___|_|   "
    echo "                                                     "
    echo -e "${NC}"
    echo -e "${CYAN}               The Python hygiene tool!${NC}\n\n"
}


display_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -f, --files <command>   Specify files to lint ('all', 'modified',"
    echo "                         'modified-cached', 'untracked', or file paths)."
    echo "  -d, --diff              Show diff and ask to apply changes."
    echo "  -v, --verbose           Run in verbose mode."
    echo "  --line-length=<n>       Set the line length for linting"
    echo "                         (default is 90)."
    echo "  -h, --help              Display this help message."
    echo
    exit 0
}



parse_args() {
    FILES_OPTION=() # Initialize as an empty array
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -f|--files)
                shift
                while [ "$#" -gt 0 ] && [[ "$1" != -* ]]; do
                    FILES_OPTION+=("$1") # Append file or directory to array
                    shift
                done
                ;;
            -d|--diff)
                DIFF="--diff"
                shift
                ;;
            -v|--verbose)
                VERBOSE="--verbose"
                shift
                ;;
            --line-length=*)
                LINE_LENGTH="${1#*=}"
                if ! [[ $LINE_LENGTH =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}Error: --line-length must be a number.${NC}"
                    exit 1
                fi
                shift
                ;;
            -h|--help)
                display_help
                ;;
            *)
                echo -e "${YELLOW}Unknown argument: $1. Run $0 --help for usage.${NC}"
                exit 1
                ;;
        esac
    done
}


run_isort() {
    local file=$1

    isort "$file" $VERBOSE --profile=black --atomic --check-only >/dev/null 2>&1
    local status=$?

    if [ $status -eq 1 ]; then
        if [ "$DIFF" == "--diff" ]; then
            isort "$file" $VERBOSE --profile=black --atomic --diff

            echo -e "${YELLOW}Apply isort changes to '$file'? [y/n]${NC}"
            read apply_changes
            if [ "$apply_changes" == "y" ]; then
                isort "$file" $VERBOSE --profile=black --atomic
            fi
        else
            isort "$file" $VERBOSE --profile=black --atomic
        fi
    fi
}


run_ruff() {
    local file=$1

    local ruff_output=$(ruff format "$file" --line-length $LINE_LENGTH \
        $VERBOSE $DIFF 2>&1)

    if [[ $ruff_output == *"1 file left unchanged"* ]]; then
        return 0
    elif [[ $ruff_output == *"1 file already formatted"* ]]; then
        return 0
    else
        echo "$ruff_output"
    fi

    if [ "$DIFF" == "--diff" ]; then
        if [[ $ruff_output == *"would be reformatted"* ]]; then
            echo -e "${YELLOW}Apply ruff changes to '$file'? [y/n]${NC}"
            read apply_changes
            if [ "$apply_changes" == "y" ]; then
                ruff format "$file" --line-length $LINE_LENGTH $VERBOSE
            fi
        fi
    fi
}


run_linter() {
    local files=$1

    echo -e "${BLUE}Running isort on Python files:${NC}"
    for file in $files; do
        if [ -f "$file" ] || [ -d "$file" ]; then
            echo "Linting file: $file"
            run_isort "$file"
        fi
    done

    echo -e "\n${BLUE}Running ruff on Python files:${NC}"
    for file in $files; do
        if [ -f "$file" ] || [ -d "$file" ]; then
            echo "Linting file: $file"
            run_ruff "$file"
        fi
    done
}


cleanup() {
    if [ -d ".ruff_cache" ]; then
        rm -rf .ruff_cache
    fi
}


check_dependencies() {
    for cmd in isort ruff git; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}Error: $cmd is not installed.${NC}"
            exit 1
        fi
    done
}


filter_files() {
    while read file; do
        if ! [[ $file =~ $EXCLUDE_PATTERN ]]; then
            echo "$file"
        fi
    done
}


get_all_python_files() {
    find . -name "*.py"
}


get_modified_python_files() {
    git diff --name-only HEAD | grep '\.py$'
}


get_modified_cached_python_files() {
    git diff --cached --name-only HEAD | grep '\.py$'
}


get_untracked_python_files() {
    git ls-files --others --exclude-standard | grep '\.py$'
}


select_files_to_lint() {
    for item in "${FILES_OPTION[@]}"; do
        if [[ -d "$item" ]]; then
            find "$item" -name "*.py" | filter_files
        elif [[ -f "$item" ]]; then
            echo "$item" | filter_files
        else
            case "$item" in
                all)
                    get_all_python_files | filter_files
                    ;;
                modified)
                    get_modified_python_files | filter_files
                    ;;
                modified-cached)
                    get_modified_cached_python_files | filter_files
                    ;;
                untracked)
                    get_untracked_python_files | filter_files
                    ;;
                *)
                    echo -e "${RED}Error: Invalid file or directory '${item}'.${NC}"
                    exit 1
                    ;;
            esac
        fi
    done
}


display_header
check_dependencies
parse_args "$@"

SELECTED_FILES=$(select_files_to_lint)

if [ -z "$SELECTED_FILES" ]; then
    echo -e "${RED}No Python files to lint based on the specified criteria.${NC}"
else
    run_linter "$SELECTED_FILES"
    cleanup
fi


# TODO: Add support for other file types (e.g. .sh, .yml, .json, etc.)
# TODO: Add support for other linters/formatters (e.g. flake8, markdownlint, etc.)
# TODO: Add check for if git exists before running git commands
# TODO: Add flag whether to apply changes or not (e.g. --apply-changes)
# TODO: Add flag to specify wether to just all diff at once or per file (e.g. --diff-all)
