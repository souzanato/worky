#!/bin/bash
set -e

# Carrega o RVM
source /home/renato/.rvm/scripts/rvm

cd /opt/worky

# Sobe o Puma
exec bundle exec puma -C /opt/worky/config/puma.rb
