#!/bin/bash

# Ensure your DNS settings for your domain are accurate prior to running
# this script.

# elicit website name and letsencrypt registration email address from user
echo 'What is the name of your website (please include .com)'
read website

echo 'Give me a valid email address for Lets Encrypt certificate:'
read certbotemail

# randomly generate your databse user and root passwords
dbpass=$(openssl rand -base64 16)
mysqlroot=$(openssl rand -base64 16)

# change webroot if you want to change where your serving your website from
webroot=/var/www

# install base PHP and associated modules along with nginx
apt-get update
apt install software-properties-common
add-apt-repository ppa:ondrej/php -y
apt-get update
apt-get upgrade -y
apt-get install -y 'php8.0' php8.0-cli php8.0-common php8.0-opcache php8.0-mysql php8.0-mbstring libmcrypt-dev php8.0-zip php8.0-fpm php8.0-bcmath php8.0-intl php8.0-xml php8.0-curl php8.0-gd 'libapache2-mod-php8.0' php8.0-ldap
apt-get install -y nginx
sudo systemctl stop nginx.service
sudo systemctl start nginx.service
sudo systemctl enable nginx.service

debconf-set-selections <<< "mysql-server-8.0 mysql-server/root_password password $mysqlroot"
sudo debconf-set-selections <<< "mysql-server-8.0 mysql-server/root_password_again password $mysqlroot"
apt-get -y install 'mysql-server-8.0'
apt install composer -y

# use composer to install firefly-iii in your webroot folder
composer create-project grumpydictator/firefly-iii --no-dev -d $webroot --prefer-dist firefly-iii 5.6.5
sudo chown -R www-data:www-data $webroot
sudo chmod -R 775 $webroot/firefly-iii/storage

# create required database tables in mysql
cat >/tmp/user.sql <<EOL
CREATE USER 'firefly'@'localhost' IDENTIFIED BY '${dbpass}';
CREATE DATABASE firefly;
GRANT ALL PRIVILEGES ON firefly.* TO 'firefly'@'localhost';
FLUSH PRIVILEGES;
EOL

mysql -u root --password="$mysqlroot"< /tmp/user.sql >/dev/null 2>&1
sed -i "s:"DB_HOST=db":"DB_HOST=localhost":" $webroot/firefly-iii/.env
sed -i "s:"DB_PASSWORD=secret_firefly_password":"DB_PASSWORD=$dbpass":" $webroot/firefly-iii/.env


php $webroot/firefly-iii/artisan migrate:refresh --seed
php $webroot/firefly-iii/artisan firefly:upgrade-database
php $webroot/firefly-iii/artisan passport:install

# creates your config file in nginx sites-available
cat >/etc/nginx/sites-available/$website <<EOL
server {
   listen 80;
   root /var/www/firefly-iii/public;
   index index.php index.html index.htm index.nginx-debian.html;
   server_name $website www.$website;

   location / {
       try_files \$uri \$uri/ /index.php?\$query_string;
       autoindex on;
       sendfile off;
   }

   location ~ \.php$ {
      include snippets/fastcgi-php.conf;
      fastcgi_pass unix:/run/php/php8.0-fpm.sock;
   }

   location ~ /\.ht {
      deny all;
   }
}
EOL

# symlink your config file to sites-enabled
ln -s /etc/nginx/sites-available/$website /etc/nginx/sites-enabled/

# make sure that the default config is unlinked from sites-enabled
unlink /etc/nginx/sites-enabled/default

# stop apache2 so that nginx can serve the webpages
service apache2 stop
systemctl start nginx

# install letsencrypt certificate
apt install certbot python3-certbot-nginx -y
certbot --nginx -n -d $website -d www.$website --email $certbotemail --agree-tos --redirect --hsts

# output the mysql user and root password to the user for records
cat <<EOF

###### Store these in a safe place they will dissapear after this ######


Mysql root password is  ${mysqlroot}
Firefly db user password is  ${dbpass}

EOF
