#!/bin/bash
#
# This script takes user home folder quota settings from filr and applies it as a directory quota to a user's home folder on an NSS filesystem 
# In addition it takes the used space on that folder and applies it to the user's used space setting within filr 
#  The end result is that user's quota settings are repoorted within filr for users with external home folders
#
#Set this to '1' to see more info about what's going on...

debug=0

# Bail out unless we have required executables...

if [ ! -e /usr/bin/mysql ]; then
	echo "You must have mysql-client installed to proceed!"
	exit 1;
fi

if [ ! -e /sbin/nssquota ]; then
	echo "You must have novell-nss installed to proceed!"
	exit 1;
fi

# Assumptions:  
#  You have access to the filr database server.  
#  You have quotas defined in the filr admin interface and intend to manage home folder quotas from within filr.  
#  You are using directory quotas and not userquotas on the volume.
#  You will have filrewalled tightly the access to the MySql server to restrict acces just to your NSS fileserver from where you will run this script.
#  You are happy that poking around in filr's database is something you want to do and you've tested all this on a test filr system!
#
#  You will need to set this up before you start:

#  A MySQL user must be created on the Filr database server with SELECT rights to the 'name'
#  column on the 'SS_Principals' table.  In the following SQL example the user is 'quotaman' 
#
#  GRANT SELECT (`name`),
#  UPDATE (`diskQuota` ,`diskSpaceUsed`) 
#  ON `filr`.`SS_Principals` TO 'quotaman'@'radius3.imsu.ox.ac.uk' 
#  identified by 'some PASSWORD';
#
# Set this to the location of the Filr home folders on this server
FILRHOMES=/media/nss/FILRHOMES/homes
# Set this to the database user created for this purpose
DBUSER=quotaman
# Set this to the database user's password
DBPASS=PASSWORD
# Set this to the address of your filr database server - mysql must be listening and available on this address.
FILRDBSVR=filrdb.xxx.xxx.xxx
# Quotas are stored in filr in Mb   Used space is stored in bytes :-(
UNITS=Mb


# get list of folders in filr home location and use this as user list
USERLIST=$( ( /usr/bin/find $FILRHOMES/ -maxdepth 1 -mindepth 1 -type d -printf "%f\n" ) )

for USER in ${USERLIST[@]}
do
	# lowercase all usernames
	LCUSER=$( echo $USER | tr '[A-Z]' '[a-z]' ) 
	# get user's defined quota from filr database
	QUOTA=$( echo "SELECT diskQuota FROM SS_Principals WHERE name = '$LCUSER' limit 1;" | /usr/bin/mysql -N -h $FILRDBSVR -u$DBUSER -p$DBPASS filr )

	# If user has no individually defined quota  the value in the SS_Principals table will be NULL so instead get the default quota for the zone
	if [ "$QUOTA" == "NULL" ] || [ "$QUOTA" == "0" ];then
		QUOTA=$( echo "SELECT diskQuotaUserDefault FROM SS_Principals JOIN SS_ZoneConfig WHERE name = '$LCUSER' limit 1;" | /usr/bin/mysql -N -h $FILRDBSVR -u$DBUSER -p$DBPASS filr )
	fi

	if [ $debug -eq 1 ];then
		 echo $USER has $QUOTA Mb quota
	fi
	# Now apply the quota derived from the filr db to the user's home folder on an NSS filesystem

	if [ $debug -eq 1 ]; then
		echo "nssquota -D -d $FILRHOMES/$USER -s $QUOTA$UNITS"
	fi

        /sbin/nssquota -D -d $FILRHOMES/$USER -s $QUOTA$UNITS

	if [ $debug -eq 1 ]; then
		var=$(echo $?)
		if [ $var -eq 0 ]; then
			echo "Success!"
		else
			echo "PROBLEM - Return value was $var"
		fi
	fi

	# Now get the actual space used by the home folder on the NSS filesystem and update the filr database with that value

	if [ $debug -eq 1 ]; then
		echo "nssquota -D -d $FILRHOMES/$USER -g | grep ^spaceUsed"
	fi

        USED=$( /sbin/nssquota -D -d $FILRHOMES/$USER -g | grep ^spaceUsed | awk '{print $3}' )
        USEDUNITS=$( /sbin/nssquota -D -d $FILRHOMES/$USER -g | grep ^spaceUsed | awk '{print $4}' )

	if [ $debug -eq 1 ]; then
        	echo Quota in use for $USER: $USED$USEDUNITS
	fi

	# We have values which have a variety of units but filr holds everything as bytes so we need to convert all values to bytes as recorded in filr
	# There will be people who will find improved ways to do this I'm sure...
		
	case $USEDUNITS in
	KB)
	    USED=$( echo "scale=3; $USED * 1024" | /usr/bin/bc | /usr/bin/xargs printf '%0.f\n')
	    ;;
	MB)
	    USED=$( echo "($USED * 1024 * 1024 + 0.5) / 1" | /usr/bin/bc )
	    ;;
	GB)
	    USED=$( echo "($USED * 1024 * 1024 * 1024 + 0.5) / 1" | /usr/bin/bc )
	    ;;
	esac

	echo "$USER is using $USED Bytes"

	if [ $debug -eq 1 ];then
		echo "Running 'UPDATE SS_Principals set diskSpaceUsed = $USED WHERE name = '$LCUSER' limit 1;'"
	fi
	#  Update the filr database with the diskSpaceUsed value in bytes obtained above for the user we are currently processing.
	echo "UPDATE SS_Principals set diskSpaceUsed = $USED WHERE name = '$LCUSER' limit 1;" | /usr/bin/mysql -h $FILRDBSVR -u$DBUSER -p$DBPASS filr
	echo ""

done
