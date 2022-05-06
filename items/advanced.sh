#!/bin/sh
#
#   Copyright (c) 2022: Jacob.Lundqvist@gmail.com
#   License: MIT
#
#   Part of https://github.com/jaclu/tmux-menus
#
#   Version: 1.3.0 2022-05-06
#
#   Advanced options
#
#   Types of menu item lines.
#
#   1) An item leading to an action
#          "Description" "In-menu key" "Action taken when it is triggered"
#
#   2) Just a line of text
#      You must supply two empty strings, in order for the
#      menu logic to interpret it as a full menu line item.
#          "Some text to display" "" ""
#
#   3) Separator line
#      This is a proper graphical separator line, without any label.
#          ""
#
#   4) Labeled separator line
#      Not perfect, since you will have at least one space on each side of
#      the labeled separator line, but using something like this and carefully
#      increase the dashes until you are just below forcing the menu to just
#      grow wider, seems to be as close as it gets.
#          "#[align=centre]-----  Other stuff  -----" "" ""
#
#
#   All but the last line in the menu, needs to end with a continuation \
#   White space after this \ will cause the menu to fail!
#   For any field containing no spaces, quotes are optional.
#

# shellcheck disable=SC1007
CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPT_DIR="$(dirname "$CURRENT_DIR")/scripts"

# shellcheck disable=SC1091
. "$SCRIPT_DIR/utils.sh"


menu_name="Advanced options"
req_win_width=40
req_win_height=17

#
#  Gather some info in order to be able to show states
#
current_mouse_status="$(tmux show-option -g mouse | cut -d' ' -f2)"
if [ "$current_mouse_status" = "on" ]; then
    new_mouse_status="off"
else

    new_mouse_status="on"
fi


current_prefix="$(tmux show-option -g prefix | cut -d' ' -f2 | cut -d'-' -f2)"


t_start="$(date +'%s')"

# shellcheck disable=SC2154,SC2140
tmux display-menu \
     -T "#[align=centre] $menu_name "             \
     -x "$menu_location_x" -y "$menu_location_y"  \
     \
     "Back to Main menu"       Left  "run-shell $CURRENT_DIR/main.sh"  \
     "Client management  -->"  C     "run-shell \"$CURRENT_DIR/advanced_manage_clients.sh\""    \
     "" \
     "<P> Show messages"         \~  show-messages        \
     "<P> Customize options"      C  "customize-mode -Z"  \
     "<P> Describe (prefix) key"  /  "command-prompt -k -p key \"list-keys -1N \\"%%%\\"\""  \
     "<P> Prompt for a command"   :  command-prompt  \
     "" \
     "Toggle mouse to: $new_mouse_status"  m  "set-option -g mouse $new_mouse_status"   \
     "Change prefix <$current_prefix>"     p  "command-prompt -1 -p prefix 'run \"$SCRIPT_DIR/change_prefix.sh %%\"'"  \
     "" \
     "-#[nodim]Kill server - all your sessions"       "" ""  \
     " on this host are terminated    "    k  "confirm-before -p \"kill tmux server on #H ? (y/n)\" kill-server"  \
     "" \
     "Help  -->"  H  "run-shell \"$CURRENT_DIR/help.sh $CURRENT_DIR/advanced.sh\""


ensure_menu_fits_on_screen
