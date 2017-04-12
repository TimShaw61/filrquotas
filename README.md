# filrquotas
Fix for displaying filr quotas when external home folders are used.  The display of quotas and used space in the filr interface only works if personal storage (internal to filr) is used for home folders.

This script takes user home folder quota settings from filr and applies it as a directory quota to a user's home folder on an NSS filesystem.  In addition it takes the used space on that folder and applies it to the user's used space setting within filr 
The end result is that user's quota settings are reported within filr for users with external home folders.

Tested on Filr 2.x

# Assumptions:  

You have access to the filr database server.  
You have quotas defined in the flr admin interface and intend to manage home folder quotas from within filr.  
You are using directory quotas and not userquotas on the volume.
You will have filrewalled tightly the access to the MySql server to restrict acces just to your NSS fileserver from where you will run this script.
You are happy that poking around in filr's database is something you want to do and you've tested all this on a test filr system!

# Preparation

A MySQL user must be created on the Filr database server with SELECT rights to the 'name' column on the 'SS_Principals' table.  In the following SQL example the user is 'quotaman' 

<pre>
GRANT SELECT (`name`),
UPDATE (`diskQuota` ,`diskSpaceUsed`) 
ON `filr`.`SS_Principals` TO 'quotaman'@'radius3.imsu.ox.ac.uk' 
identified by 'some PASSWORD';
</pre>
