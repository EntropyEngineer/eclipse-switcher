#!/bin/bash

# ------------------------------------------------------
# Основные настройки
# ------------------------------------------------------

THRESHOLD=4800      # Порог, ниже которого включается тёмная тема
SLEEP_PERIOD_SEC=60 # Интервал опроса системы

# ------------------------------------------------------
# Конфигурация тем ('Светлая' 'Тёмная')
# можно закомментировать переменные, переключение которых не требуется
# ------------------------------------------------------

# может быть определён или пакет оформления целиком
PACKAGES=('org.kde.breeze.desktop' 'org.kde.breezedark.desktop')

# или отдельные настройки оформления, если пакет не определён (параметр закомментирован)
if [[ ! -v PACKAGES ]]; then
    COLOR_SCHEMES=('BreezeLight' 'BreezeDark')
    CURSOR_THEMES=('Breeze_Light' 'breeze_cursors')
    ICONS_THEMES=('breeze' 'breeze-dark')
    WALLPAPERS=('/usr/share/wallpapers/Next/contents/images/1920x1080.png' '/usr/share/wallpapers/Next/contents/images_dark/1920x1080.png')
    GTK_THEMES=('Breeze' 'Breeze')
fi

VSCODE_THEMES=('Default Light Modern' 'Default Dark Modern')

# Здесь следует указать название желаемых цветовых схем. Не профилей!
KONSOLE_SCHEMES=('BlackOnWhite' 'WhiteOnBlack')

# ------------------------------------------------------
# Определение режима работы
# ------------------------------------------------------

MODE_UNKNOWN=-1
MODE_LIGHT=0
MODE_DARK=1

CURRENT_MODE=$MODE_UNKNOWN

detected_mode() {
    local temp=$(qdbus6 org.kde.KWin /org/kde/KWin/NightLight org.kde.KWin.NightLight.currentTemperature)
    if [ "$temp" -lt "$THRESHOLD" ]; then
        echo $MODE_DARK
    else
        echo $MODE_LIGHT
    fi
}

# ------------------------------------------------------
# Переключение тем
# ------------------------------------------------------

switch_to() {
    CURRENT_MODE=$1

    # Plasma
    if [[ -v PACKAGES ]]; then
        plasma-apply-lookandfeel -a "${PACKAGES[$1]}"
    fi

    if [[ -v COLOR_SCHEMES ]]; then
        plasma-apply-colorscheme "${COLOR_SCHEMES[$1]}"
    fi

    if [[ -v CURSOR_THEMES ]]; then
        plasma-apply-cursortheme "${CURSOR_THEMES[$1]}"
    fi

    if [[ -v ICONS_THEMES ]]; then
        /usr/lib/plasma-changeicons "${ICONS_THEMES[$1]}"
    fi

    if [[ -v WALLPAPERS ]]; then
        plasma-apply-wallpaperimage "${WALLPAPERS[$1]}"
    fi

    # GTK
    if [[ -v GTK_THEMES ]]; then
        gsettings set org.gnome.desktop.interface gtk-theme "${GTK_THEMES[$1]}"
    fi

    # VSCode
    if [[ -v VSCODE_THEMES ]]; then
        switch_vscode_to $1
    fi

    # Konsole
    if [[ -v KONSOLE_SCHEMES ]]; then
        switch_konsole_to $1
    fi
}

# ------------------------------------------------------
# Переключение темы vscode
# ------------------------------------------------------

switch_vscode_to() {
    VSCODE_CONFIG_FOLDERS=("Code" "Code - OSS")

    for VSCODE_CONFIG_FOLDER in "${VSCODE_CONFIG_FOLDERS[@]}"; do
        VSCODE_CONFIG_PATH="$HOME/.config/$VSCODE_CONFIG_FOLDER/User/settings.json"

        if [ -e "$VSCODE_CONFIG_PATH" ]; then
            jq --arg theme "${VSCODE_THEMES[$1]}" '
            if .["workbench.colorTheme"] then
                .["workbench.colorTheme"] = $theme
            else
                . + {"workbench.colorTheme": $theme}
            end
        ' "$VSCODE_CONFIG_PATH" >tmpfile && mv tmpfile "$VSCODE_CONFIG_PATH"
        fi
    done
}

# ------------------------------------------------------
# Переключение цветовой схемы Konsole
# ------------------------------------------------------

switch_konsole_to() {
    KONSOLE_RC_FILE="$HOME/.config/konsolerc"

    if [[ -f "$KONSOLE_RC_FILE" ]]; then
        KONSOLE_PROFILE_NAME=$(grep "^DefaultProfile=" "$KONSOLE_RC_FILE" | cut -d'=' -f2)

        if [[ -n "$KONSOLE_PROFILE_NAME" ]]; then
            KONSOLE_PROFILE_PATH="$HOME/.local/share/konsole/$KONSOLE_PROFILE_NAME"
        else
            KONSOLE_PROFILE_PATH="$KONSOLE_RC_FILE"
        fi

        sed -i "s/^ColorScheme=.*/ColorScheme=${KONSOLE_SCHEMES[$1]}/" "$KONSOLE_PROFILE_PATH"

        for KONSOLE_INSTANCE in $(qdbus6 | grep 'org.kde.konsole'); do
            for KONSOLE_SESSION in $(qdbus6 $KONSOLE_INSTANCE | grep -E 'Sessions/[0-9]+'); do
                qdbus6 $KONSOLE_INSTANCE $KONSOLE_SESSION org.kde.konsole.Session.runCommand "konsoleprofile ColorScheme='${KONSOLE_SCHEMES[$1]}'"
            done
        done
    fi
}

# ------------------------------------------------------
# Параметры
# ------------------------------------------------------

SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(realpath "$0")

AUTOSTART_DIR="$HOME/.config/autostart"
DESKTOP_FILE_PATH="$AUTOSTART_DIR/eclipse-switcher.desktop"

if [[ -n "$XDG_RUNTIME_DIR" ]]; then
    PID_FILE="$XDG_RUNTIME_DIR/${SCRIPT_NAME}.pid"
else
    PID_FILE="/run/user/$(id -u)/${SCRIPT_NAME}.pid"
fi

# ------------------------------------------------------
# Цикл опроса
# ------------------------------------------------------

watch() {
    if [[ -f "$PID_FILE" ]]; then
        CURRENT_PID=$(cat "$PID_FILE")
        echo "Скрипт уже работает в фоне, PID: $CURRENT_PID"
        exit 1
    fi

    echo $$ >"$PID_FILE"

    while true; do
        DETECTED_MODE=$(detected_mode)

        if [ "$DETECTED_MODE" != "$CURRENT_MODE" ]; then
            switch_to "$DETECTED_MODE" >/dev/null 2>&1
        fi

        sleep "$SLEEP_PERIOD_SEC"
    done
}

# ------------------------------------------------------
# Завершение процесса скрипта
# ------------------------------------------------------

kill_process() {
    if [[ -f "$PID_FILE" ]]; then
        CURRENT_PID=$(cat "$PID_FILE")

        if [[ -n "$CURRENT_PID" && "$CURRENT_PID" =~ ^[0-9]+$ ]] && kill -0 "$CURRENT_PID" 2>/dev/null; then
            kill "$CURRENT_PID" 2>/dev/null

            for i in {1..50}; do
                if ! kill -0 "$CURRENT_PID" 2>/dev/null; then
                    break
                fi
                sleep 0.1
            done
        fi

        rm -f "$PID_FILE"
    fi
}

# ------------------------------------------------------
# Добавление скрипта в автозагрузку
# ------------------------------------------------------

add_to_autostart() {
    mkdir -p "$AUTOSTART_DIR"

    {
        echo "[Desktop Entry]"
        echo "Type=Application"
        echo "Exec=sh -c '$SCRIPT_PATH --watch'"
        echo "Hidden=false"
        echo "NoDisplay=false"
        echo "X-KDE-autostart-enabled=true"
        echo "Name=Eclipse Switcher"
        echo "GenericName=Переключение цветовой схемы согласно цветовой температуры экрана"
    } >"$DESKTOP_FILE_PATH"
}

# ------------------------------------------------------
# Удаление скрипта из автозагрузки
# ------------------------------------------------------

remove_from_autostart() {
    if [[ -f "$DESKTOP_FILE_PATH" ]]; then
        rm -f "$DESKTOP_FILE_PATH"
    fi
}

# ------------------------------------------------------
# Проверка, установлен ли jq
# ------------------------------------------------------

if ! command -v jq &>/dev/null; then
    echo "Предупреждение: Пакет 'jq' не установлен. Установите его для корректной работы скрипта"
    exit
fi

# ------------------------------------------------------
# Вызов методов
# ------------------------------------------------------

case "$1" in
    --light)
        switch_to $MODE_LIGHT
        ;;
    --dark)
        switch_to $MODE_DARK
        ;;
    --watch)
        watch
        ;;
    --set)
        kill_process
        add_to_autostart
        gio launch "$DESKTOP_FILE_PATH"
        echo "Скрипт добавлен в автозагрузку и запущен"
        ;;
    --remove)
        kill_process
        remove_from_autostart
        echo "Скрипт удалён из автозагрузки и остановлен"
        ;;
    *)
        echo "Использование: $0 [--set | --remove]"
        ;;
esac