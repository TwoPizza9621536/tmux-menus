#!/bin/sh
#
#   Copyright (c) 2023: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-menus
#
#  Parses params and generates tmux or whiptail menus
#
#  Global exclusions
#  shellcheck disable=SC2154

#  shellcheck disable=SC1091
. "$SCRIPT_DIR/utils.sh"

menu_type="whiptail" #  fallback if tmux can't be used

menu_debug=0 #  Display progress as menu is being built

if [ -z "$FORCE_WHIPTAIL" ] || [ "$FORCE_WHIPTAIL" = "0" ]; then
    #
    #  tmux built in popup menus requires tmux 3.0
    #
    if tmux_vers_compare 3.0; then
        menu_type="tmux"
    # else
    #     echo "--->  tmux older than 3.0, switching to whiptail  <---"
    fi
fi

ensure_menu_fits_on_screen() {
    #
    #  Since tmux display-menu returns 0 even if it failed to display the menu
    #  due to not fitting on the screen, for now I check how long the menu
    #  was displayed. If the seconds didn't tick up, inspect required size vs
    #  actual screen size, and display a message if the menu doesn't fit.
    #
    #  Not perfect, but it kind of works. If you hit escape and instantly close
    #  the menu, a time diff zero might trigger this to check sizes, but if
    #  the menu fits on the screen, no size warning will be printed.
    #
    #  This gets slightly more complicated with tmux 3.3, since now tmux shrinks
    #  menus that don't fit due to width, so tmux might decide it can show a menu,
    #  but due to shrinkage, the hints in the menu might be so shortened that they
    #  are off little help explaining what this option would do.
    #
    [ "$t_start" -ne "$(date +'%s')" ] && return # should have been displayed

    #
    #  Param checks
    #
    msg="ensure_menu_fits_on_screen() req_win_width not set"
    [ "$req_win_width" = "" ] && error_msg "$msg" 1
    msg="ensure_menu_fits_on_screen() req_win_height not set"
    [ "$req_win_height" = "" ] && error_msg "$msg" 1
    msg="ensure_menu_fits_on_screen() menu_name not set"
    [ "$menu_name" = "" ] && error_msg "$msg" 1

    set -- "ensure_menu_fits_on_screen() '$menu_name'" \
        "w:$req_win_width h:$req_win_height"
    log_it "$*"

    cur_width="$($TMUX_BIN display -p "#{window_width}")"
    log_it "Current width: $cur_width"
    cur_height="$($TMUX_BIN display -p "#{window_height}")"
    log_it "Current height: $cur_height"

    if [ "$cur_width" -lt "$req_win_width" ] ||
        [ "$cur_height" -lt "$req_win_height" ]; then
        echo
        echo "menu '$menu_name'"
        echo "needs a screen size"
        echo "of at least $req_win_width x $req_win_height"
    fi
}

starting_with_dash() {
    #
    #  in whiptail, an initial '-'' in a label causes the menu to fail
    #  in tmux menus this is used to indicate dimmed entries
    #  for whiptail entries with such labels are just ignored
    #
    if [ "$(printf '%s' "$1" | cut -c 1)" = "-" ]; then
        return 0
    else
        return 1
    fi

    #  another aproach doing the same
    # if [ "$(printf '%s\n' "${label%"${label#?}"}")" = "-" ]; then
}

#
#  tmux 3.0+ built in menu handling using display-menu
#
tmux_dialog_prefix() {
    #  shellcheck disable=SC2154
    menu_prefix="$TMUX_BIN display-menu -T \"#[align=centre] $menu_name \"
                 -x \"$menu_location_x\" -y \"$menu_location_y\""
}

tmux_open_menu() {
    label="$1"
    key="$2"
    menu="$3"

    # [ $menu_debug -eq 1 ] && echo "tmux_open_menu($label,$key,$menu)"

    # shellcheck disable=SC2089
    menu_items="$menu_items \"$label\" $key \"run-shell '$menu'\""
}

tmux_external_cmd() {
    label="$1"
    key="$2"
    # cmd="$3"
    cmd="$(echo "$3" | sed 's/"/\\"/g')" # replace embedded " with \"

    # [ $menu_debug -eq 1 ] && echo "tmux_external_cmd($label,$key,$cmd)"
    #
    #  needs to be prefixed with run-shell, since this is triggered by
    #  tmux
    #
    menu_items="$menu_items \"$label\" $key 'run-shell \"$cmd\"'"
}

tmux_command() {
    label="$1"
    key="$2"
    # cmd="$3"
    cmd="$(echo "$3" | sed 's/"/\\"/g')" # replace embedded " with \"

    [ $menu_debug -eq 1 ] && echo "tmux_command($label,$key,$cmd)"
    menu_items="$menu_items \"$label\" $key \"$cmd\""
}

tmux_text_line() {
    txt="$1"
    menu_items="$menu_items \"$txt\" '' ''"
}

tmux_spacer() {
    #  shellcheck disable=SC2089
    menu_items="$menu_items \"\""
}

#
#  using whiptail --menu
#

whiptail_dialog_prefix() {
    #  shellcheck disable=SC2089
    menu_prefix="$dialog_app --menu \"$menu_name\" 0 0 0 "
}

whiptail_parse_selection() {
    #
    #  Whiptail/dialog can only display selected keyword,
    #  so a post dialog step is needed matching keyword with intended
    #  action, and then perform it
    #

    # echo "selected item: [$menu_selection]"
    # echo "wt_actions [$wt_actions]"
    # echo
    # echo "Parsing actions:"
    # echo

    lst=$wt_actions
    i=0
    while true; do
        # POSIX way to handle array types of data
        section="${lst%%"${whiptail_action_separator}"*}" # up to first colon excluding it
        lst="${lst#*"${whiptail_action_separator}"}"      # after fist colon

        #  strip leading and trailing spaces
        # section=${section#"${string%%[![:space:]]*}"}
        # section=${section%%[[:space:]]*}

        # echo ">> section [$section]"
        i=$((i + 1))
        # echo "i $i"
        [ $i -gt 50 ] && break
        [ -z "$section" ] && continue # skip blank lines
        # echo ">> reimainder [$lst]"

        key="$(echo "$section" | cut -d'|' -f 1 | awk '{$1=$1};1')" # | tr '[:upper:]' '[:lower:]')"
        action="$(echo "$section" | cut -d'|' -f 2 | awk '{$1=$1};1')"

        # echo ">> section [$section]"
        # echo ">> name [$key] action [$action]"
        if [ "$key" = "$menu_selection" ]; then
            # echo "Will run whiptail triggered action:"
            # echo "$action"
            # sleep 1
            eval "$action"
            break
        fi
        [ "$lst" = "" ] && break # we have processed last group
        # echo
    done
}

whiptail_open_menu() {
    label="$1"
    key="$2"
    menu="$3"

    #
    #  labels starting with - indicates disabled feature in tmux notation,
    #  whiptail can not handle labels starting with -, so just skip
    #  those lines
    #
    starting_with_dash "$label" && return

    menu_items="$menu_items $key \"$label\""
    wt_actions="$wt_actions $key | $menu $whiptail_action_separator"
}

whiptail_external_cmd() {
    label="$1"
    key="$2"
    cmd="$3"

    #
    #  labels starting with - indicates disabled feature in tmux notation,
    #  whiptail can not handle labels starting with -, so just skip
    #  those lines
    #
    starting_with_dash "$label" && return

    if echo "$cmd" | grep -vq /; then
        script="$CURRENT_DIR/$script"
    fi
    menu_items="$menu_items $key \"$label\""
    # This will run outside tmux, so should not have run-shell prefix
    wt_actions="$wt_actions $key | $cmd $whiptail_action_separator"
}

whiptail_command() {
    # filtering out tmux #{...} & #[...] sequences
    label="$(echo "$1" | sed 's/#{[^}]*}//g' | sed 's/#\[[^}]*\]//g')"

    key="$2"
    cmd="$3"

    #
    #  labels starting with - indicates disabled feature in tmux notation,
    #  whiptail can not handle labels starting with -, so just skip
    #  those lines
    #
    starting_with_dash "$label" && return

    # filer out backslashes prefixing special chars
    key_action="$(echo "$key" | sed 's/\\//')"

    menu_items="$menu_items $key \"$label\""
    wt_actions="$wt_actions $key_action | $TMUX_BIN $cmd $whiptail_action_separator"
}

whiptail_text_line() {
    # filtering out tmux #{...} sequences
    txt="$(echo "$1" | sed 's/#{[^}]*}//g' | sed 's/#\[[^}]*\]//g')"

    #
    #  labels starting with - indicates disabled feature,
    #  whiptail can not handle labels starting with -, so just skip
    #  those lines
    #
    starting_with_dash "$txt" && return

    menu_items="$menu_items '' \"$txt\""
}

whiptail_spacer() {
    menu_items="$menu_items '' ' '"
}

parse_menu() {
    #
    #  Since the various menu entries have different numbers of params
    #  we first identify all the params used by the different options,
    #  only then can we continue if the min_vers does not match running tmux
    #
    [ -z "$menu_name" ] && error_msg "$current_script - menu_name must be set!"
    [ $menu_debug -eq 1 ] && echo ">> parse_menu($*)"
    while [ -n "$1" ]; do
        min_vers="$1"
        shift
        action="$1"
        shift
        [ $menu_debug -eq 1 ] && echo "[$min_vers] [$action]"
        case "$action" in

        "M") #  Open another menu
            key="$1"
            shift
            label="$1"
            shift
            menu="$1"
            shift

            ! tmux_vers_compare "$min_vers" && continue

            #
            #  If no path separators pressent in a menu name
            #  assume it is located in the same dir as the script
            #  defining the menu, and prepend with its path
            #
            if echo "$menu" | grep -vq /; then
                menu="$CURRENT_DIR/$menu"
            fi

            [ $menu_debug -eq 1 ] && echo "key[$key] label[$label] menu[$menu]"

            if [ "$menu_type" = "tmux" ]; then
                tmux_open_menu "$label" "$key" "$menu"
            else
                whiptail_open_menu "$label" "$key" "$menu"
            fi
            ;;

        "C") #  direct tmux command - params: key label task
            key="$1"
            shift
            label="$1"
            shift
            cmd="$1"
            shift

            ! tmux_vers_compare "$min_vers" && continue

            [ $menu_debug -eq 1 ] && echo "key[$key] label[$label] command[$cmd]"

            if [ "$menu_type" = "tmux" ]; then
                tmux_command "$label" "$key" "$cmd"
            else
                whiptail_command "$label" "$key" "$cmd"
            fi
            ;;

        "E") #  Run external command - params: key label cmd
            #
            #  If no / is found in the script param, it will be prefixed with
            #  $CURRENT_DIR
            #  This means that if you give full path to something in this
            #  param, all scriptd needs to have full path pre-pended.
            #  For example help menus, which takes the full path to the
            #  current script, in order to be able to go back.
            #  For the normal case a name pointing to a script in the same
            #  dir as the current, this will be pre-pended automatically.
            #
            key="$1"
            shift
            label="$1"
            shift
            cmd="$1"
            shift

            ! tmux_vers_compare "$min_vers" && continue

            #
            #  Not sure if this would make sense for external commands
            #  they could be intentionally path-less
            #
            # if echo "$cmd" | grep -vq /; then
            #     cmd="$CURRENT_DIR/$cmd"
            # fi

            [ $menu_debug -eq 1 ] && echo "key[$key] label[$label] command[$cmd]"

            if [ "$menu_type" = "tmux" ]; then
                tmux_external_cmd "$label" "$key" "$cmd"
            else
                whiptail_external_cmd "$label" "$key" "$cmd"
            fi
            ;;

        "T") #  text line - params: txt
            txt="$1"
            shift

            ! tmux_vers_compare "$min_vers" && continue

            [ $menu_debug -eq 1 ] && echo "text line [$txt]"
            if [ "$menu_type" = "tmux" ]; then
                tmux_text_line "$txt"
            else
                whiptail_text_line "$txt"
            fi
            ;;

        "S") #  Spacer line - params: none

            ! tmux_vers_compare "$min_vers" && continue

            [ $menu_debug -eq 1 ] && echo "Spacer line"

            # Whiptail/dialog does not have a concept of spacer lines
            if [ "$menu_type" = "tmux" ]; then
                tmux_spacer
            else
                whiptail_spacer
            fi
            ;;

        *) # Error
            echo
            echo "ERROR: [$1]"
            echo "--- Menu created so far ---"
            echo "$menu_items"
            exit 1
            ;;

        esac
    done

    if [ "$menu_type" = "tmux" ]; then
        tmux_dialog_prefix
    else
        whiptail_dialog_prefix
    fi

    #  prepend cmd line with menu prefix
    #  shellcheck disable=SC2086,SC2090
    set -- $menu_prefix $menu_items

    if [ "$menu_debug" -eq 1 ]; then
        echo "Would run:"
        echo "$@"
        if [ -n "$wt_actions" ]; then
            echo "Whiptail actions:"
            echo "$wt_actions"
        fi
    fi

    if [ "$menu_type" = "tmux" ]; then
        #  shellcheck disable=SC2034
        t_start="$(date +'%s')"
        # tmux can trigger actions by it self
        #  shellcheck disable=SC2068,SC2294
        eval $@
        ensure_menu_fits_on_screen
    else
        #  shellcheck disable=SC2294
        menu_selection=$(eval "$@" 3>&2 2>&1 1>&3) # skip - for non MacOS
        # echo "selection[$menu_selection]"
        whiptail_parse_selection
    fi
}

if [ -z "$CURRENT_DIR" ] || [ -z "$SCRIPT_DIR" ]; then
    echo "ERROR: CURRENT_DIR & SCRIPT_DIR must be defined!"
    exit 1
fi

dialog_app="whiptail"
whiptail_action_separator=":/:/:/:"

#
#  Define a variable that can be used as suffix on commands, to reload
#  the same menu in calling scripts
#
if [ "$menu_type" = "tmux" ]; then
    menu_reload="; run-shell '$current_script'"
else
    # shellcheck disable=SC2034
    menu_reload="; '$current_script'"
fi
