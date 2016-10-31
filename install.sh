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

# Set a lock file; see: http://stackoverflow.com/questions/7057234/bash-flock-exit-if-cant-acquire-lock/7057385
(
	flock -n 9 || { echo '#	An installation is already running' ; exit 1; }


# Get the script directory see: http://stackoverflow.com/a/246128/180733
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

# GDAL/ogr2ogr
add-apt-repository -y ppa:ubuntugis/ppa
apt-get update
apt-get install gdal-bin

# ogr2osm, for conversion of shapefiles to .osm
# See: http://wiki.openstreetmap.org/wiki/Ogr2osm
# See: https://github.com/pnorman/ogr2osm
# Usage: python /opt/ogr2osm/ogr2osm.py my-shapefile.shp [-t my-translation-file.py]
if [ ! -f /opt/ogr2osm/ogr2osm.py ]; then
	apt-get -y install python-gdal
	cd /opt/
	git clone git://github.com/pnorman/ogr2osm.git
	cd ogr2osm
	git submodule update --init
fi

# Omsosis, for pre-processing of .osm files
# See: http://wiki.openstreetmap.org/wiki/Osmosis/Installation
# Note: apt-get -y install osmosis can't be used, as that gives too old a version that does not include TagTransform
apt-get install default-jdk
if [ ! -f /opt/osmosis/bin/osmosis ]; then
	cd /opt/
	wget http://bretth.dev.openstreetmap.org/osmosis-build/osmosis-latest.tgz
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

# Add user and group who will own the files
adduser --gecos "" travelintimes || echo "The travelintimes user already exists"
addgroup rollout || echo "The rollout group already exists"



## Stage 4: Front-end software

# Create website area
websiteDirectory=/opt/travelintimes/
if [ ! -d "$websiteDirectory" ]; then
	mkdir "$websiteDirectory"
	chown travelintimes.rollout "$websiteDirectory"
	git clone https://github.com/campop/travelintimes.git "$websiteDirectory"
else
	echo "Updating travelintimes repo ..."
	cd "$websiteDirectory"
	git pull
	echo "... done"
fi
chmod -R g+w "$websiteDirectory"
find "$websiteDirectory" -type d -exec chmod g+s {} \;

# Ensure the configurations directories are writable by the webserver
chown www-data "${websiteDirectory}configuration/frontend"
chown www-data "${websiteDirectory}configuration/mapnikstylesheet"
chown www-data "${websiteDirectory}configuration/routingprofiles"
chown www-data "${websiteDirectory}configuration/tagtransform"
chown www-data "${websiteDirectory}configuration/frontend/archive"
chown www-data "${websiteDirectory}configuration/mapnikstylesheet/archive"
chown www-data "${websiteDirectory}configuration/routingprofiles/archive"
chown www-data "${websiteDirectory}configuration/tagtransform/archive"

# Ensure the configuration files are writable by the webserver
chown www-data "${websiteDirectory}configuration/tagtransform/tagtransform.xml"
chown www-data "${websiteDirectory}configuration/mapnikstylesheet/mapnikstylesheet.xml"
chown www-data "${websiteDirectory}configuration/frontend/osrm-frontend.js"
chown www-data "${websiteDirectory}configuration/routingprofiles/profile-*"

# Ensure the build directory is writable by the webserver
chown www-data "${websiteDirectory}build-tmp/"

# Link in Apache VirtualHost
if [ ! -L /etc/apache2/sites-enabled/travelintimes.conf ]; then
	ln -s $SCRIPTDIRECTORY/apache.conf /etc/apache2/sites-enabled/travelintimes.conf
	service apache2 restart
fi

# Add OSRM frontend
osrmFrontendDirectory=/opt/osrm-frontend/
if [ ! -d "$osrmFrontendDirectory" ]; then
	mkdir "$osrmFrontendDirectory"
	chown travelintimes.rollout "$osrmFrontendDirectory"
	git clone https://github.com/Project-OSRM/osrm-frontend.git "$osrmFrontendDirectory"
else
	echo "Updating OSRM frontend repo ..."
	cd "$osrmFrontendDirectory"
	git pull
	echo "... done"
fi
chmod -R g+w "$osrmFrontendDirectory"
find "$osrmFrontendDirectory" -type d -exec chmod g+s {} \;
mv "${osrmFrontendDirectory}src/leaflet_options.js" "${osrmFrontendDirectory}src/leaflet_options.js.original"
ln -s "${osrmFrontendDirectory}configuration/frontend/osrm-frontend.js" "${osrmFrontendDirectory}src/"



## Stage 5: Routing engine

# OSRM routing engine
# See: https://github.com/Project-OSRM/osrm-backend/wiki/Building-OSRM
# See: https://github.com/Project-OSRM/osrm-backend/wiki/Building-on-Ubuntu
# See: https://github.com/Project-OSRM/osrm-backend/wiki/Running-OSRM
osrmBackendDirectory=/opt/osrm-backend/
if [ ! -f "${osrmBackendDirectory}build/osrm-extract" ]; then
#	apt-get -y install build-essential git cmake pkg-config libbz2-dev libstxxl-dev libstxxl-doc libstxxl1 libxml2-dev libzip-dev libboost-all-dev lua5.1 liblua5.1-0-dev libluabind-dev libtbb-dev
	apt-get -y install build-essential git cmake pkg-config libbz2-dev libstxxl-dev libstxxl1v5 libxml2-dev libzip-dev libboost-all-dev lua5.2 liblua5.2-dev libluabind-dev libtbb-dev
	apt-get -y install doxygen
	cd /opt/
	mkdir "$osrmBackendDirectory"
	chown -R travelintimes.rollout "$osrmBackendDirectory"
	wget -P /tmp/ https://github.com/Project-OSRM/osrm-backend/archive/v5.4.0.tar.gz
	sudo -H -u travelintimes bash -c "tar -xvzf /tmp/v5.4.0.tar.gz -C $osrmBackendDirectory --strip-components=1"
	cd "$osrmBackendDirectory"
	mkdir -p build
	chown -R travelintimes.rollout "${osrmBackendDirectory}build/"
	cd build
	sudo -H -u travelintimes bash -c "cmake .. -DCMAKE_BUILD_TYPE=Release"
	sudo -H -u travelintimes bash -c "cmake --build ."
	cmake --build . --target install
fi
chmod -R g+w "$osrmBackendDirectory"
find "$osrmBackendDirectory" -type d -exec chmod g+s {} \;




# Report completion
echo "#	Installation completed"

# Remove the lock file - ${0##*/} extracts the script's basename
) 9>$lockdir/${0##*/}

# End of file
