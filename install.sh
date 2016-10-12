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

# General packages
apt-get install -y git unzip nano wget man-db bzip2
apt-get install -y mlocate
updatedb


## Stage 2: Conversion software

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




## Stage 3: Server software

# Webserver
apt-get install -y apache2
a2enmod rewrite
apt-get install -y php php-cli
apt-get install -y libapache2-mod-php




# Report completion
echo "#	Installation completed"

# Remove the lock file - ${0##*/} extracts the script's basename
) 9>$lockdir/${0##*/}

# End of file
