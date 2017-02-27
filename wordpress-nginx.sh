#Modification of NGINX script by @ryanpq
#cloud-config
write_files:
  - path: /etc/nginx/nginx.conf
    content: |     
      user nginx;
      worker_processes auto;
      error_log /var/log/nginx/error.log;
      pid /run/nginx.pid;
      
      events {
          worker_connections 1024;
      }
      
      http {
          log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                            '$status $body_bytes_sent "$http_referer" '
                            '"$http_user_agent" "$http_x_forwarded_for"';
      
          access_log  /var/log/nginx/access.log  main;
      
          sendfile            on;
          tcp_nopush          on;
          tcp_nodelay         on;
          keepalive_timeout   65;
          types_hash_max_size 2048;
		  
		  client_max_body_size 250M;
      
          include             /etc/nginx/mime.types;
          default_type        application/octet-stream;
      
          # Load modular configuration files from the /etc/nginx/conf.d directory.
          # See http://nginx.org/en/docs/ngx_core_module.html#include
          # for more information.
          include /etc/nginx/conf.d/*.conf;
		  
		  gzip on;
	      gzip_disable "msie6";

          gzip_vary on;
          gzip_proxied any;
          gzip_comp_level 6;
          gzip_buffers 16 8k;
          gzip_http_version 1.1;
          gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
      }

  - path: /etc/nginx/conf.d/default.conf
    content: |
	  fastcgi_cache_path /var/run/nginx-cache levels=1:2
                         keys_zone=WORDPRESS:100m inactive=60m;
      fastcgi_cache_key "$scheme$request_method$host$request_uri";
	
      server {
        listen 80 default_server;
        listen [::]:80 default_server ipv6only=on;
        root /var/www/html;
        index index.php index.html index.htm;
        server_name localhost;
        
        set $skip_cache 0;
        
        # POST requests and URLs with a query string should always go to PHP
        if ($request_method = POST) {
            set $skip_cache 1;
        }   
        
        if ($query_string != "") {
            set $skip_cache 1;
        }   
        
        # Don't cache URIs containing the following segments
        if ($request_uri ~* "/wp-admin/|/xmlrpc.php|wp-.*.php|/feed/|index.php
                             |sitemap(_index)?.xml") {
            set $skip_cache 1;
        }   
        
        # Don't use the cache for logged-in users or recent commenters
        if ($http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass
            |wordpress_no_cache|wordpress_logged_in") {
            set $skip_cache 1;
        }
        
        location / {
            try_files $uri $uri/ /index.php?$args;
        
            # Uncomment to enable naxsi on this location
            # include /etc/nginx/naxsi.rules
        }
        error_page 404 403 /404.html;
        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            root /var/www/html;
        }
        location ~ \.php$ {
            try_files $uri /index.php;
            include fastcgi_params;
            fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
            fastcgi_split_path_info ^(.+\.php)(/.+)$;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            fastcgi_cache_bypass $skip_cache;
            fastcgi_no_cache $skip_cache;
            fastcgi_cache WORDPRESS;
            fastcgi_cache_valid  60m;
        }
        
        location ~* .(ogg|ogv|svg|svgz|eot|otf|woff|mp4|ttf|css|rss|atom|js|jpg|jpeg|gif|png|ico|zip|tgz|gz|rar|bz2|doc|xls|exe|ppt|tar|mid|midi|wav|bmp|rtf)$ {
            expires max;
            log_not_found off;
            access_log off;
        }
        
        # Restrict access to WordPress dashboard
        #location /wp-admin {
        #    allow xx.xxx.xx.xxx;
        #    deny  all;
        #}
        
        # Deny public access to wp-config.php
        location ~* wp-config.php {
            deny all;
        }
        
        location = /robots.txt {
            access_log off;
            log_not_found off;
        }
        
        location ~ /\. {
            deny  all;
            access_log off;
            log_not_found off;
        }
      }
  - path: /var/www/html/info.php
    content: |
      <?php
      phpinfo();
      ?>
runcmd:
  - yum -y install epel-release
  - yum -y install unzip nginx php-fpm php-mysql mariadb-server mariadb
  - wget https://wordpress.org/latest.zip -O /tmp/wordpress.zip
  - unzip /tmp/wordpress.zip -d /tmp/
  - cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php
  - ROOTMYSQLPASS=`dd if=/dev/urandom bs=1 count=12 2>/dev/null | base64 -w 0 | rev | cut -b 2- | rev`
  - WPMYSQLPASS=`dd if=/dev/urandom bs=1 count=12 2>/dev/null | base64 -w 0 | rev | cut -b 2- | rev`
  - echo "Root MySQL Password $ROOTMYSQLPASS" > /root/passwords.txt
  - echo "Wordpress MySQL Password $WPMYSQLPASS" >> /root/passwords.txt
  - sed -i -e "s/database_name_here/wordpress/" /tmp/wordpress/wp-config.php
  - sed -i -e "s/username_here/wordpress/" /tmp/wordpress/wp-config.php
  - sed -i -e "s/password_here/$WPMYSQLPASS/" /tmp/wordpress/wp-config.php
  - for i in `seq 1 8`; do wp_salt=$(</dev/urandom tr -dc 'a-zA-Z0-9!@#$%^&*()\-_ []{}<>~`+=,.;:/?|' | head -c 64 | sed -e 's/[\/&]/\\&/g'); sed -i "0,/put your unique phrase here/s/put your unique phrase here/$wp_salt/" /tmp/wordpress/wp-config.php; done
  - systemctl enable mariadb
  - systemctl start mariadb
  - /usr/bin/mysqladmin -u root -h localhost create wordpress
  - /usr/bin/mysqladmin -u root -h localhost password $ROOTMYSQLPASS
  - /usr/bin/mysql -uroot -p$ROOTMYSQLPASS -e "CREATE USER wordpress@localhost IDENTIFIED BY '"$WPMYSQLPASS"'"
  - /usr/bin/mysql -uroot -p$ROOTMYSQLPASS -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost"
  - mkdir -p /var/www/html
  - sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php.ini
  - sed -i -e "s|listen = 127.0.0.1:9000|listen = /var/run/php-fpm/php-fpm.sock|" /etc/php-fpm.d/www.conf
  - sed -i -e "s|user = apache|user = nginx|" /etc/php-fpm.d/www.conf
  - sed -i -e "s|group = apache|group = nginx|" /etc/php-fpm.d/www.conf
  - cp -Rf /tmp/wordpress/* /var/www/html/.
  - chown -Rf nginx.nginx /var/www/html/*
  - rm -f /var/www/html/index.html
  - rm -Rf /tmp/wordpress*
  - systemctl start php-fpm
  - systemctl enable php-fpm.service
  - systemctl enable nginx.service
  - systemctl restart nginx