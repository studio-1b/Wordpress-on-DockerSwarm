#! /bin/bash


# below copied from wordpress resarch
# customized local volume config
SVC_PREFIX="jmbc-wordpress"
NFS_SHARE="/srv"
WP_SUBDIR="$NFS_SHARE/jmbc_wordpress"
WP_FRONTEND="$WP_SUBDIR/wpress"
WP_MYSQL="$WP_SUBDIR/mariadb"

echo "This script tries to order the steps, and ensure the dependencies are installed"
echo "NFS Share............: $NFS_SHARE"
echo "WP Uploads NFS Volume: $WP_FRONTEND"
echo "MySQL Datafile Volume: $WP_MYSQL"
echo "Port mappings 8001 8002 are hardcoded in docker-compose.yml"
echo "This script does check localhost:8001, to wait for the container to be active"
echo

#checking if NFS is installed
echo Checking if NFS is installed....
exportfs &> /dev/null
if [ $? -ne 0 ]; then
  echo "NFS server not installed!  Install now? (y/n) [n]"
  read DO_NFS_INSTALL
  if [ "$DO_NFS_INSTALL" == "y" ]; then
    echo "It might ask for sudo password"
    sudo apt install nfs-kernel-server
  else
    exit 1
  fi
fi

if [ ! -d $NFS_SHARE ]; then
  echo "No srv dir, creating... It might ask for sudo password"
  sudo mkdir $NFS_SHARE
  sudo chmod 777 $NFS_SHARE
fi

showmount -e localhost | cut -f1 -d' ' | grep $NFS_SHARE &> /dev/null
if [ $? -ne 0 ]; then
  echo "No NFS mount ($NFS_SHARE) defined.  Creating, but may need sudo password"
  ALLOWED_SUBNET=$(<allowed_nfs_subnet.txt &> /dev/null)
  if [ "$ALLOWED_SUBNET" == "" ]; then
    echo "Enter X.X.X.X/X for hosts allowed to access NFS share [*]"
    read ALLOWED_SUBNET
    if [ "$ALLOWED_SUBNET" == "" ]; then
      ALLOWED_SUBNET="*"
    fi
    echo $ALLOWED_SUBNET > allowed_nfs_subnet.txt
  fi
  EXPORT_LINE="$NFS_SHARE		$ALLOWED_SUBNET(rw,sync,no_subtree_check)"
  sudo echo $EXPORT_LINE >> /var/exports
  sudo exportfs -ra
fi
showmount -e localhost | cut -f1 -d' ' | grep $NFS_SHARE &> /dev/null
if [ $? -ne 0 ]; then
  echo NFS is not installed.  This means that wordpress frontend containers
  echo will not be able to share content.  Not all content is stored in the
  echo MySQL database.
  exit 1
fi







echo
echo This script is going to start the Wordpress in docker, on this console.
echo This is b/c docker-compose, creates the local volume dir more effectively
echo   with the correct permissions, for the service containers to access.
echo
echo Please check web browser at http://localhost:8001/ to see when it is up
echo and when it is, return to console, hit ctrl-c once and let it terminate
echo it will continue installing
echo
echo Press enter to continue installation, and hit Ctrl-C when Wordpress is up...
read ok

docker-compose up

#I added this, after worker nodes not starting up
#bob@swarm1:/srv/jmbc_wordpress/wpress/wp-content$ sudo chmod -R 664 *.*
#above makes no difference, changing path of folder. 664 is not enough

# next line also does not work
#bob@swarm1:/srv/jmbc_wordpress/wpress$ sudo chmod 775 /srv/jmbc_wordpress/wpress
# above line failes bc installer uses /var/www/html as temporary directory to create temporary files


#but below works
#sudo chmod 777 /srv/jmbc_wordpress/wpress
sudo chmod 777 $WP_FRONTEND


#below will allow mariadb to run any node
#  BUT mysql runs much slower over NFS
#sudo chmod 755 /srv/jmbc_wordpress/mariadb/data/performance_schema
#sudo chmod 755 /srv/jmbc_wordpress/mariadb/data/mysql
#sudo chmod 755 /srv/jmbc_wordpress/mariadb/data/wordpress
sudo chmod 755 $WP_MYSQL/data/performance_schema
sudo chmod 755 $WP_MYSQL/data/mysql
sudo chmod 755 $WP_MYSQL/data/wordpress














if [ ! -d "$WP_SUBDIR" ]; then
  echo "$WP_SUBDIR doesnt exist. creation failed above"
  exit 1
fi



# Important docker steps 
# (Just creating the service with stack deploy, 
#  will result in the containers crashing on worker nodes, 
#  bc there is no image available for them, unless pull image is used)
echo "Pulling images for Wordpress, explicitly"
echo "might be redundant since docker-compose should already do this"
echo "but running docker-compose before creating the service, is a sort of hack"
docker image pull wordpress:5.1.1-php7.1-apache
docker image pull mariadb:10.4.4


echo "Creating services"
docker stack deploy --compose-file=docker-compose.yml $SVC_PREFIX








#
echo waiting for both databases and wordpress to finish installing
# Waiting for service to run before updating replica count
docker service ls | grep ${SVC_PREFIX}'_wordpress.*1/1' &> /dev/null
while [ $? -ne 0 ]; do
  echo -n "."
  sleep 1
  docker service ls | grep ${SVC_PREFIX}'_wordpress.*1/1' &> /dev/null
done
echo .
echo Docker reports wordpress is up... waiting for website to be up
curl http://localhost:8001 &> /dev/null
while [ $? -ne 0 ]; do
   echo -n "."
   sleep 1
   curl http://localhost:8001 &> /dev/null
done
echo '.'
echo

# After the images replicate on worker nodes, create image based on the running copies
# if you don't do this and use the wordpress image from docker to create container, it will try to overwrite the files created from the 1st container and fail
##echo Creating image for single service to support sessions
##docker container ls | grep ${SVC_PREFIX}_wordpress | cut -d' ' -f1 | head -n1
##if [ $? -eq 0 ]; then
##  CONTAINER_ID=$(docker container ls | grep ${SVC_PREFIX}_wordpress | cut -d' ' -f1 | head -n1)
##  docker commit $CONTAINER_ID ${SVC_PREFIX}-clone
##  docker image ls | grep $CONTAINER_ID ${SVC_PREFIX}-clone

#  cp docker-compose.yml docker-compose_w_login.yml
#  cat fragment.yml >> docker-compose_w_login.yml
#  sed -i "s/image: jmbc-wordpress-clone/image: ${SVC_PREFIX}-clone/" docker-compose_w_login.yml

#  echo again wait until 8002 is up, then ctrl-c
#  read ok
#  docker-compose -f docker-compose_w_login.yml up

  # we added a new 
##  docker stack deploy --compose-file=fragment.yml $SVC_PREFIX

##  echo please login on port 8002
##fi
##echo anyone can visit on port 8001




# Waiting for service to run before updating replica count
echo Updating wordpress replicas to 3,
docker service ls | grep ${SVC_PREFIX}'_wordpress.*1/1' &> /dev/null
while [ $? -ne 0 ]; do
  echo -n "."
  sleep 1
  docker service ls | grep ${SVC_PREFIX}'_wordpress.*1/1' &> /dev/null
done
docker service update --replicas 3 ${SVC_PREFIX}_wordpress




echo
echo

# show the nodes running the front end container
echo These are the containers that are clustered, port 8001:
docker service ps ${SVC_PREFIX}_wordpress

echo
echo These are the service that supports sessions, port 8002:
docker service ps ${SVC_PREFIX}_wordpress-login
