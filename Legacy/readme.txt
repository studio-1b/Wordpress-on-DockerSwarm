The docker-compose.yml here has /var/www/html/wp-content as the mapped directory

The problem is that the Wordpress installer in the container in docker, checks
/var/www/html if wordpress needs to be reinstalled.  Since all docker containers
are "fresh" /var/www/html will always be empty and it will try to reinstall
wordpress.   But /var/www/html/wp-content is not empty and the installer will
not overwrite any existing files.

You can see this when you run "docker service logs <id of service for wordpress>"
and it says "file already exists... error detected... terminating container"

So the mapped folder HAS TO BE /var/www/html, to prevent the installer from
reinitiating an install, with every new wordpress container.  And this installing
over existing files before, causes a crash of the container.  You can write your
own docker build, to get around this, but I find this solution to be the fastest,
if the least elegant.

