docker service rm $(docker service ls | grep jmbc-wordpress | cut -f1 -d' ' | xargs)

if [ "$1" == "data" ]; then
  sudo rm -Rf /srv/jmbc_wordpress/
fi
