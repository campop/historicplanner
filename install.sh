#!/bin/bash
# Installation


## Stage 1: Boilerplate script setup

echo "#	Install travelintimes"

# Ensure this script is run as root
if [ "$(id -u)" != "0" ]; then
	echo "# This script must be run as root." 1>&2
	exit 1
fi

# Bomb out if something goes wrong
set -e

# Lock directory
lockdir=/var/lock/travelintimes
mkdir -p $lockdir

# Set a lock file; see: https://stackoverflow.com/questions/7057234/bash-flock-exit-if-cant-acquire-lock/7057385
(
	flock -n 9 || { echo '#	An installation is already running' ; exit 1; }


# Get the script directory see: https://stackoverflow.com/a/246128/180733
# The multi-line method of geting the script directory is needed to enable the script to be called from elsewhere.
SOURCE="${BASH_SOURCE[0]}"
DIR="$( dirname "$SOURCE" )"
while [ -h "$SOURCE" ]
do
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
SCRIPTDIRECTORY=$DIR


## Main body

# Update sources and packages
apt-get -y update
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove

# General packages, useful while developing
apt-get install -y unzip nano man-db bzip2 dnsutils
apt-get install -y mlocate
updatedb

# General packages, required for deployment
apt-get install -y git wget


## Stage 2: Conversion software

# Define path containing all local software; can be specified as a script argument, or the default will be used
softwareRoot=${1:-/var/www/travelintimes}

# Add user and group who will own the files
adduser --gecos "" travelintimes || echo "The travelintimes user already exists"
addgroup travelintimes || echo "The travelintimes group already exists"

# GDAL/ogr2ogr
add-apt-repository -y ppa:ubuntugis/ppa
apt-get update
apt-get install -y gdal-bin

# ogr2osm, for conversion of shapefiles to .osm
# See: https://wiki.openstreetmap.org/wiki/Ogr2osm
# See: https://github.com/pnorman/ogr2osm
# Usage: python $softwareRoot/ogr2osm/ogr2osm.py my-shapefile.shp [-t my-translation-file.py]
if [ ! -f $softwareRoot/ogr2osm/ogr2osm.py ]; then
	apt-get -y install python-gdal
	cd $softwareRoot/
	git clone --recursive https://github.com/pnorman/ogr2osm
fi

# Omsosis, for pre-processing of .osm files
# See: https://wiki.openstreetmap.org/wiki/Osmosis/Installation
# Note: apt-get -y install osmosis can't be used, as that gives too old a version that does not include TagTransform
apt-get install -y default-jdk
if [ ! -f $softwareRoot/osmosis/bin/osmosis ]; then
	cd $softwareRoot/
	wget https://bretth.dev.openstreetmap.org/osmosis-build/osmosis-latest.tgz
	mkdir osmosis
	mv osmosis-latest.tgz osmosis
	cd osmosis
	tar xvfz osmosis-latest.tgz
	rm osmosis-latest.tgz
	chmod a+x bin/osmosis
	# bin/osmosis
fi

# # osmconvert, for merging .osm files
# apt-get -y install osmctools

# Install modern version of Node.js - Ubuntu 14.04 official version dates back to 2014
curl -sL https://deb.nodesource.com/setup_9.x | sudo -E bash -
apt-get install -y nodejs

# Update npm
npm i -g npm

# Conversion to GeoJSON
npm install -g osmtogeojson
npm install -g ndjson-cli
npm install -g geojson-mend
npm install -g geojson-precision
apt-get install -y jq



## Stage 3: Webserver software

# Webserver
apt-get install -y apache2
a2enmod rewrite
apt-get install -y php php-cli php-xml
apt-get install -y libapache2-mod-php
a2enmod macro
a2enmod headers

# Disable Apache logrotate, as this loses log entries for stats purposes
if [ -f /etc/logrotate.d/apache2 ]; then
	mv /etc/logrotate.d/apache2 /etc/logrotate.d-apache2.disabled
fi



## Stage 4: Front-end software

# Create website area
websiteDirectory=$softwareRoot/travelintimes
if [ ! -d "$websiteDirectory/" ]; then
	mkdir "$websiteDirectory/"
	git clone https://github.com/campop/travelintimes.git "$websiteDirectory/"
else
	echo "Updating travelintimes repo ..."
	cd "$websiteDirectory/"
	git pull
	echo "... done"
fi
chown -R travelintimes.travelintimes "$websiteDirectory/"
chmod -R g+w "$websiteDirectory/"
find "$websiteDirectory/" -type d -exec chmod g+s {} \;
cp -p "$websiteDirectory/htdocs/controlpanel/index.html.template" "$websiteDirectory/htdocs/controlpanel/index.html"

# Ensure the configurations directories are writable by the webserver
chown www-data "${websiteDirectory}/configuration"
chown www-data "${websiteDirectory}/configuration/frontend"
chown www-data "${websiteDirectory}/configuration/mapnikstylesheet"
chown www-data "${websiteDirectory}/configuration/routingprofiles"
chown www-data "${websiteDirectory}/configuration/turns"
chown www-data "${websiteDirectory}/configuration/tagtransform"
chown www-data "${websiteDirectory}/configuration/frontend/archive"
chown www-data "${websiteDirectory}/configuration/mapnikstylesheet/archive"
chown www-data "${websiteDirectory}/configuration/routingprofiles/archive"
chown www-data "${websiteDirectory}/configuration/turns/archive"
chown www-data "${websiteDirectory}/configuration/tagtransform/archive"

# Ensure the configuration files are writable by the webserver
chown www-data "${websiteDirectory}/configuration/tagtransform/tagtransform.xml"
chown www-data "${websiteDirectory}/configuration/mapnikstylesheet/mapnikstylesheet.xml"
chown www-data "${websiteDirectory}/configuration/frontend/osrm-frontend.js"
chown www-data "${websiteDirectory}/configuration/routingprofiles/profile-"*
chown www-data "${websiteDirectory}/configuration/turns/turns-"*

# Ensure the upload export files are writable by the webserver
chown www-data "${websiteDirectory}/exports"

# Ensure the build directory is writable by the webserver
chown www-data "${websiteDirectory}/enginedata/"

# Link in Apache VirtualHost
if [ ! -f /etc/apache2/sites-enabled/travelintimes.conf ]; then
	cp -p $SCRIPTDIRECTORY/apache.conf /etc/apache2/sites-enabled/travelintimes.conf
	sed -i "s|/var/www/travelintimes|${softwareRoot}|g" /etc/apache2/sites-enabled/travelintimes.conf
fi

# Add leaflet-routing-machine
lrmFrontendDirectory=$softwareRoot/leaflet-routing-machine
lrmVersion=3.2.8
if [ ! -d "$lrmFrontendDirectory/" ]; then
	cd $softwareRoot/
	mkdir "$lrmFrontendDirectory"
	chown -R travelintimes.travelintimes "$lrmFrontendDirectory"
	wget -P /tmp/ "https://github.com/perliedman/leaflet-routing-machine/archive/v${lrmVersion}.tar.gz"
	sudo -H -u travelintimes bash -c "tar -xvzf /tmp/v${lrmVersion}.tar.gz -C ${lrmFrontendDirectory}/ --strip-components=1"
fi
chown travelintimes.travelintimes "${websiteDirectory}/htdocs/index."*
chmod g+w "${websiteDirectory}/htdocs/index."*

#  # Add OSRM frontend (alternative GUI)
#  osrmFrontendDirectory=$softwareRoot/osrm-frontend
#  if [ ! -d "$osrmFrontendDirectory/" ]; then
#  	mkdir "$osrmFrontendDirectory/"
#  	git clone https://github.com/Project-OSRM/osrm-frontend.git "$osrmFrontendDirectory/"
#  else
#  	echo "Updating OSRM frontend repo ..."
#  	cd "$osrmFrontendDirectory/"
#  	git pull
#  	echo "... done"
#  fi
#  chown -R travelintimes.travelintimes "$osrmFrontendDirectory"
#  chmod -R g+w "$osrmFrontendDirectory/"
#  find "$osrmFrontendDirectory/" -type d -exec chmod g+s {} \;
#  
#  # Link in configuration and enable building of OSRM frontend
#  if [ ! -L "${osrmFrontendDirectory}/src/leaflet_options.js" ]; then
#  	mv "${osrmFrontendDirectory}/src/leaflet_options.js" "${osrmFrontendDirectory}/src/leaflet_options.js.original"
#  	ln -s "${websiteDirectory}/configuration/frontend/osrm-frontend.js" "${osrmFrontendDirectory}/src/leaflet_options.js"
#  fi
#  chown -R www-data "${osrmFrontendDirectory}/bundle."* "${osrmFrontendDirectory}/css"
#  # Install npm for building frontend
#  apt-get install -y npm
#  # Use of nodejs-legacy needed to avoid: 'npm WARN This failure might be due to the use of legacy binary "node"'; see: https://stackoverflow.com/a/21171188
#  apt-get install -y nodejs-legacy
#  cd "$osrmFrontendDirectory/"
#  npm install
#  sudo -H -u www-data bash -c "make"


## Stage 5: Routing engine

# OSRM routing engine
# See: https://github.com/Project-OSRM/osrm-backend/wiki/Building-OSRM
# See: https://github.com/Project-OSRM/osrm-backend/wiki/Building-on-Ubuntu
# See: https://github.com/Project-OSRM/osrm-backend/wiki/Running-OSRM
osrmBackendDirectory=$softwareRoot/osrm-backend
osrmVersion=5.15.2
if [ ! -f "${osrmBackendDirectory}/build/osrm-extract" ]; then
	apt-get install software-properties-common
	add-apt-repository -y ppa:ubuntu-toolchain-r/test
	apt-get update
	apt-get install -y g++-6 gcc-6 build-essential git wget cmake3 pkg-config libbz2-dev libstxxl-dev libstxxl1 libxml2-dev libzip-dev libboost-all-dev lua5.2 liblua5.2-dev libtbb-dev
	export CPP=cpp-6 CC=gcc-6 CXX=g++-6
	export AR=gcc-ar-4.9 NM=gcc-nm-4.9 RANLIB=gcc-ranlib-4.9
	cd $softwareRoot/
	mkdir "$osrmBackendDirectory"
	chown -R travelintimes.travelintimes "$osrmBackendDirectory"
	wget -P /tmp/ "https://github.com/Project-OSRM/osrm-backend/archive/v${osrmVersion}.tar.gz"
	sudo -H -u travelintimes bash -c "tar -xvzf /tmp/v${osrmVersion}.tar.gz -C ${osrmBackendDirectory}/ --strip-components=1"
	rm "/tmp/v${osrmVersion}.tar.gz"
	cd "$osrmBackendDirectory/"
	mkdir -p build
	chown -R travelintimes.travelintimes "${osrmBackendDirectory}/build/"
	cd build
	sudo -H -u travelintimes bash -c "cmake .. -DCMAKE_BUILD_TYPE=Release"
	sudo -H -u travelintimes bash -c "cmake --build ."
	cmake --build . --target install
fi
chmod -R g+w "$osrmBackendDirectory/"
find "$osrmBackendDirectory/" -type d -exec chmod g+s {} \;

# Add firewall
## Permit engine(s) from port 5000
#iptables -I INPUT 1 -p tcp --match multiport --dports 5000:5002 -j ACCEPT
#netfilter-persistent save
#netstat -ntlup
#Check status using: sudo ufw status verbose
apt-get -y install ufw
ufw allow from 127.0.0.1 to any port 5000
ufw allow from 127.0.0.1 to any port 5001
ufw allow from 127.0.0.1 to any port 5002
ufw reload
ufw status verbose

# Create a symlink to where the profile will be, and enable it to be writeable by the webserver
touch "${osrmBackendDirectory}/profiles/latest-build-profile.lua"
chown -R www-data.travelintimes "${osrmBackendDirectory}/profiles/latest-build-profile.lua"
chmod g+w "${osrmBackendDirectory}/profiles/latest-build-profile.lua"
if [ ! -L  "${osrmBackendDirectory}/build/profile.lua" ]; then
	ln -s "${osrmBackendDirectory}/profiles/latest-build-profile.lua" "${osrmBackendDirectory}/build/profile.lua"
fi

# Enable Apache to log to a build file
touch "${websiteDirectory}/build.log"
chown www-data "${websiteDirectory}/build.log"

# Enable Apache-commenced OSRM process to log to a folder
chown www-data "${websiteDirectory}/logs-osrm/"


## Stage 6: HTTPS support


# Install certbot (Let's Encrypt); see: https://certbot.eff.org/all-instructions/#ubuntu-14-04-trusty-apache
apt-get install -y software-properties-common
add-apt-repository -y ppa:certbot/certbot
apt-get update
apt-get install -y python-certbot-apache

# Issue certificate
if [ ! -f /etc/letsencrypt/live/www.travelintimes.org/fullchain.pem ]; then
	email="campop@"
	email+="geog.cam.ac.uk"
	certbot --agree-tos --no-eff-email certonly --keep-until-expiring --webroot -w $softwareRoot/travelintimes/htdocs/ --email $email -d www.travelintimes.org -d travelintimes.org
fi

# Enable SSL in Apache
a2enmod ssl

# Enable proxing, as osrm-routed can only serve HTTP, not HTTPS
a2enmod proxy proxy_http

# Restart Apache
service apache2 restart


## Stage 7: Tile rendering

# Install mapnik; see: https://wiki.openstreetmap.org/wiki/User:SomeoneElse/Ubuntu_1604_tileserver_load#Mapnik
apt-get install -y autoconf apache2-dev libtool libxml2-dev libbz2-dev libgeos-dev libgeos++-dev libproj-dev gdal-bin libgdal1-dev libmapnik-dev mapnik-utils python-mapnik



# Update file search index
updatedb

# Report completion
echo "#	Installation completed"

# Remove the lock file - ${0##*/} extracts the script's basename
) 9>$lockdir/${0##*/}

# End of file
