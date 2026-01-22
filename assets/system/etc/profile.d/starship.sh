# Set global Starship config for all shells unless user already set one
if [ -z "${STARSHIP_CONFIG}" ] && [ -f /etc/starship.toml ]; then
  export STARSHIP_CONFIG=/etc/starship.toml
fi
