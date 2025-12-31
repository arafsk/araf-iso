#!/bin/bash
set -eo pipefail
##################################################################################################################
#tput setaf 0 = black
#tput setaf 1 = red
#tput setaf 2 = green
#tput setaf 3 = yellow
#tput setaf 4 = dark blue
#tput setaf 5 = purple
#tput setaf 6 = cyan
#tput setaf 7 = gray
#tput setaf 8 = light blue
##################################################################################################################
# Git workflow
git add --all .
git commit -m "update"

branch=$(git rev-parse --abbrev-ref HEAD)
git push -u origin "$branch"

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename "$0") done"
echo "##############################################################"
tput sgr0
echo
