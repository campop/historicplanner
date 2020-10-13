#!/bin/bash
# Installation
# Written for Ubuntu 20.04 LTS Server


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

# General packages, required for deployment
apt-get install -y git wget


## Stage 2: Conversion software

# Define path containing all local software; can be specified as a script argument, or the default will be used
softwareRoot=${1:-/var/www/travelintimes}

# Add user and group who will own the files
adduser --gecos "" travelintimes || echo "The travelintimes user already exists"
addgroup travelintimes || echo "The travelintimes group already exists"

# Create the directory
mkdir -p $softwareRoot
chown travelintimes.travelintimes $softwareRoot

# GDAL/ogr2ogr (2.x)
apt-get install -y gdal-bin

# ogr2osm, for conversion of shapefiles to .osm
# See: https://wiki.openstreetmap.org/wiki/Ogr2osm
# See: https://github.com/pnorman/ogr2osm
# Usage: python $softwareRoot/ogr2osm/ogr2osm.py my-shapefile.shp [-t my-translation-file.py]
if [ ! -f $softwareRoot/ogr2osm/ogr2osm.py ]; then
	cd $softwareRoot/
	git clone --recursive https://github.com/pnorman/ogr2osm
fi

# Omsosis, for pre-processing of .osm files
# See: https://wiki.openstreetmap.org/wiki/Osmosis/Installation
apt-get install -y osmosis

# # osmconvert, for merging .osm files
# apt-get -y install osmctools

# Install modern version of Node.js - Ubuntu 14.04 official version dates back to 2014
##curl -sL https://deb.nodesource.com/setup_9.x | sudo -E bash -
apt-get install -y nodejs

# npm; also run an update
apt-get install -y npm
npm i -g npm

# Conversion to GeoJSON
npm install -g osmtogeojson
npm install -g ndjson-cli
npm install -g geojson-mend
npm install -g geojson-precision
apt-get install -y jq



## Stage 3: Webserver software

# Webserver (Apache 2.4)
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
	cp -p "${websiteDirectory}/htdocs/.config.js.template" "${websiteDirectory}/htdocs/.config.js"
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

# Ensure the GeoJSON directory is writable
chown -R www-data "$websiteDirectory/htdocs/geojson/"

# Ensure the configurations directories are writable by the webserver
chown www-data "${websiteDirectory}/configuration"
chown www-data "${websiteDirectory}/configuration/mapnikstylesheet"
chown www-data "${websiteDirectory}/configuration/routingprofiles"
chown www-data "${websiteDirectory}/configuration/turns"
chown www-data "${websiteDirectory}/configuration/tagtransform"
chown www-data "${websiteDirectory}/configuration/mapnikstylesheet/archive"
chown www-data "${websiteDirectory}/configuration/routingprofiles/archive"
chown www-data "${websiteDirectory}/configuration/turns/archive"
chown www-data "${websiteDirectory}/configuration/tagtransform/archive"

# Ensure the configuration files are writable by the webserver
chown www-data "${websiteDirectory}/configuration/tagtransform/tagtransform.xml"
chown www-data "${websiteDirectory}/configuration/mapnikstylesheet/mapnikstylesheet.xml"
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


## Stage 5: Routing engine and isochrones

# OSRM routing engine
# See: https://github.com/Project-OSRM/osrm-backend/wiki/Building-OSRM
# See: https://github.com/Project-OSRM/osrm-backend/wiki/Building-on-Ubuntu
# See: https://github.com/Project-OSRM/osrm-backend/wiki/Running-OSRM
osrmBackendDirectory=$softwareRoot/osrm-backend
osrmVersion=5.17.2
if [ ! -f "${osrmBackendDirectory}/build/osrm-extract" ]; then
	apt-get install software-properties-common
	add-apt-repository -y ppa:ubuntu-toolchain-r/test
	apt-get update
	apt-get install -y build-essential cmake pkg-config libbz2-dev libstxxl-dev libstxxl1v5 libxml2-dev libzip-dev libboost-all-dev lua5.2 liblua5.2-dev libtbb-dev libluabind-dev libluabind0.9.1d1
	export CPP=cpp-6 CC=gcc-6 CXX=g++-6
	cd $softwareRoot/
	mkdir "$osrmBackendDirectory"
	chown -R travelintimes.travelintimes "$osrmBackendDirectory"
	wget -P /tmp/ "https://github.com/Project-OSRM/osrm-backend/archive/v${osrmVersion}.tar.gz"
	sudo -H -u travelintimes bash -c "tar -xvzf /tmp/v${osrmVersion}.tar.gz -C ${osrmBackendDirectory}/ --strip-components=1"
	rm "/tmp/v${osrmVersion}.tar.gz"
	cd "$osrmBackendDirectory/"
	chown www-data profiles/
	mkdir -p build
	chown -R travelintimes.travelintimes "${osrmBackendDirectory}/build/"
	# Patch; see: https://github.com/Project-OSRM/osrm-backend/issues/5797
	wget -O fix-boost-fs.patch https://aur.archlinux.org/cgit/aur.git/plain/fix-boost-fs.patch?h=osrm-backend
	git apply fix-boost-fs.patch
	cd build
	# Fix at: https://github.com/Project-OSRM/osrm-backend/issues/5797
	sudo -H -u travelintimes bash -c 'cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-Wno-pessimizing-move -Wno-redundant-move"'	# Flags added as per https://github.com/Project-OSRM/osrm-backend/issues/5797
	sudo -H -u travelintimes bash -c "cmake --build ."
	#cmake --build . --target install
fi
chmod -R g+w "$osrmBackendDirectory/"
find "$osrmBackendDirectory/" -type d -exec chmod g+s {} \;

# nvm; install then load immediately; see: https://github.com/nvm-sh/nvm
sudo apt-get install -y curl
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.36.0/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

# Isochrones, using Galton: https://github.com/urbica/galton
# Binds against OSRM 5.17.2; see: https://github.com/urbica/galton/issues/231#issuecomment-707938664
# Note that 8.0.0 does not work - using "8" will give v8.17.0, which works
nvm install 8
nvm use 8
cd "$softwareRoot/"
npm install galton@v5.17.2
chown -R travelintimes.travelintimes node_modules/
rm package-lock.json

# Add firewall
## Permit routing engines from port 5000
## Permit isochrone engines from port 4000
#iptables -I INPUT 1 -p tcp --match multiport --dports 5000:5002 -j ACCEPT
#netfilter-persistent save
#netstat -ntlup
#Check status using: sudo ufw status verbose
apt-get -y install ufw
ufw allow from 127.0.0.1 to any port 5000
ufw allow from 127.0.0.1 to any port 5001
ufw allow from 127.0.0.1 to any port 5002
ufw allow from 127.0.0.1 to any port 5003
ufw allow from 127.0.0.1 to any port 4000
ufw allow from 127.0.0.1 to any port 4001
ufw allow from 127.0.0.1 to any port 4002
ufw allow from 127.0.0.1 to any port 4003
ufw reload
ufw status verbose

# Enable Apache-commenced OSRM process to log to a folder
chown www-data "${websiteDirectory}/logs-osrm/"


## Stage 6: HTTPS support


# Install certbot (Let's Encrypt)
apt-get install -y certbot

# Issue certificate
domainName=www.travelintimes.org
if [ ! -f "/etc/letsencrypt/live/${domainName}/fullchain.pem" ]; then
	email="campop@"
	email+="geog.cam.ac.uk"
#	certbot --agree-tos --no-eff-email certonly --keep-until-expiring --webroot -w $softwareRoot/travelintimes/htdocs/ --email $email -d "${domainName}" -d travelintimes.org
fi

# Enable SSL in Apache
a2enmod ssl

# Enable proxing, as osrm-routed can only serve HTTP, not HTTPS
a2enmod proxy proxy_http

# Restart Apache
service apache2 restart


## Stage 7: Tile rendering

# Install mapnik; see: https://switch2osm.org/serving-tiles/manually-building-a-tile-server-20-04-lts/ and https://wiki.openstreetmap.org/wiki/User:SomeoneElse/Ubuntu_1604_tileserver_load#Mapnik
apt-get install -y libboost-all-dev git tar unzip wget bzip2 build-essential autoconf libtool libxml2-dev libgeos-dev libgeos++-dev libpq-dev libbz2-dev libproj-dev munin-node munin protobuf-c-compiler libfreetype6-dev libtiff5-dev libicu-dev libgdal-dev libcairo2-dev libcairomm-1.0-dev apache2 apache2-dev libagg-dev liblua5.2-dev ttf-unifont lua5.1 liblua5.1-0-dev



# Update file search index
updatedb

# Report completion
echo "#	Installation completed"

# Remind the user to update the website config file
echo "Please edit the website config file at ${websiteDirectory}/travelintimes/htdocs/.config.js"

# Give a link to the control panel
echo "Please upload data and start the routing at https://${domainName}/controlpanel/"

# Remove the lock file - ${0##*/} extracts the script's basename
) 9>$lockdir/${0##*/}

# End of file
