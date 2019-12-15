# cron-ffm-backup-snmp

## Abstract

Gather the free block count and last write timestamp for all available
backup partitions and make this info available via SNMP by using a perl script.

## Setup

Install SNMP Daemon:

```bash
aptitude install snmpd
```

Make the perl script from the repo available under `/usr/share/snmp/snmp_backup_part_usage.pl`

```bash
cp snmp_backup_part_usage.pl /usr/share/snmp/
chmod +x /usr/share/snmp/snmp_backup_part_usage.pl
```

Configure SNMP Daemon:

EDIT `vi /etc/default/snmpd` and setup the daemon to run as root:

```bash
SNMPDOPTS='-Lsd -Lf /dev/null -I -smux -p /var/run/snmpd.pid'
```

EDIT `/etc/snmp/snmpd.conf`

And add this configuration:

```bash
# internet.experimental.1
pass .1.3.6.1.3.1               /usr/bin/perl   /usr/share/snmp/snmp_backup_part_usage.pl
``` 

And in the Access Control block:

```bash
rocommunity public  217.24.223.9
```

.. so the specified IP can access the rocommunity.

Restart the daemon

```bash
/etc/init.d/snmpd restart
```

## Test

```bash
snmpwalk -v2c -c public backup-ffm-1.ffm SNMPv2-SMI::experimental.1
```

This should return the free blocks, last write timestamp and other infos like:

```bash
SNMPv2-SMI::experimental.1.0.0 = STRING: "xvdb"
SNMPv2-SMI::experimental.1.0.1 = STRING: "8466cac3-10c2-4f0f-802f-c8891b5c919f"
SNMPv2-SMI::experimental.1.0.2 = INTEGER: 51465923
SNMPv2-SMI::experimental.1.0.3 = INTEGER: 1576375538
(..)
```

## Nagios

EDIT `objects/commands.cfg`:

```
define command {
	command_name	check_backup_usage
	# warn if less than 4GB free, critical if less than 2GB
	command_line	/usr/lib/nagios/plugins/check_snmp -P2c -H backup-ffm-$ARG1$.ffm -o SNMPv2-SMI::experimental.1.$ARG2$.2 -u blocks -w 1048576: -c 524288:
}

define command {
	command_name	check_backup_last_write
	# warn if last write time was more than 2 days ago, critical if more than 6 days ago
	command_line	/usr/lib/nagios/plugins/check_snmp -P2c -H backup-ffm-$ARG1$.ffm -o SNMPv2-SMI::experimental.1.$ARG2$.3 -u seconds -w 172800 -c 518400
}
```

Then, for each host with an associated backup service, append to the host configuration:

```
define service {
	use			generic-service
	service_description	WEBXX_BACKUP_USAGE
	check_command		check_backup_usage!1!9
	host_name		cron-support
}

define service {
	use			generic-service
	service_description	WEBXX_BACKUP_LAST_WRITE
	check_command		check_backup_last_write!1!9
	host_name		cron-support
}
```

To create the service definitions there is a perl script available:

```bash
/usr/share/snmp/nagios/create_nagios_services.pl
```

This will generate snippets like:

```bash
# uuid: cca3e787-6594-4e55-8c24-094c634d9f45
# device: xvdi
define service {
	use			generic-service
	service_description	BERIMBAU_BASCHNY_DE_BACKUP_USAGE
	check_command		check_backup_usage!1!6
	host_name		berimbau.baschny.de
}
define service {
	use			generic-service
	service_description	BERIMBAU_BASCHNY_DE_LAST_WRITE
	check_command		check_backup_last_write!1!6
	host_name		berimbau.baschny.de
}
```

to be appended to the nagios host definition file.

## ToDo's

* make the SNMP Perl script suid and revert the snmp daemon configuration so the daemon runs as user `snmp`.
* write a NIB File to resolve the numeric OIDs.


## Author

* Remus Lazar (rl@cron.eu)
