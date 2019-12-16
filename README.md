# cron-ffm-backup-snmp

## Abstract

Gather the free block count and last write timestamp for all available
backup partitions and make this info available via SNMP by using a perl script.

## Setup

Install SNMP Daemon:

```bash
aptitude install snmpd sudo
```

Make the perl script from the repo available under `/usr/share/snmp/snmp_backup_part_usage.pl`

```bash
cp snmp_backup_part_usage.pl /usr/share/snmp/
chmod +x /usr/share/snmp/snmp_backup_part_usage.pl
```

Configure sudo for the tune2fs binary

```bash
echo "snmp    ALL = (root) NOPASSWD: /sbin/tune2fs -l *" > /etc/sudoers.d/snmp_backup_part_usage_script
```

Configure SNMP Daemon:

EDIT `/etc/snmp/snmpd.conf`

And add this configuration:

```bash
# internet.experimental.1
pass .1.3.6.1.4.1.99999.1               /usr/bin/perl   /usr/share/snmp/snmp_backup_part_usage.pl
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
snmpwalk -v2c -c public backup-ffm-1.ffm SNMPv2-SMI::enterprises.99999.1
```

This should return the free blocks, last write timestamp and other infos like:

```bash
SNMPv2-SMI::enterprises.99999.1.1.0 = INTEGER: 15
SNMPv2-SMI::enterprises.99999.1.2.1.1.1 = INTEGER: 1
SNMPv2-SMI::enterprises.99999.1.2.1.1.2 = INTEGER: 2
SNMPv2-SMI::enterprises.99999.1.2.1.1.3 = INTEGER: 3
SNMPv2-SMI::enterprises.99999.1.2.1.1.4 = INTEGER: 4
SNMPv2-SMI::enterprises.99999.1.2.1.1.5 = INTEGER: 5
SNMPv2-SMI::enterprises.99999.1.2.1.1.6 = INTEGER: 6
SNMPv2-SMI::enterprises.99999.1.2.1.1.7 = INTEGER: 7
SNMPv2-SMI::enterprises.99999.1.2.1.1.8 = INTEGER: 8
SNMPv2-SMI::enterprises.99999.1.2.1.1.9 = INTEGER: 9
SNMPv2-SMI::enterprises.99999.1.2.1.1.10 = INTEGER: 10
(..)
```

To gather a specific info, e.g. only the free block count for all devices:

```bash
snmpwalk -v2c -c public backup-ffm-1.ffm SNMPv2-SMI::enterprises.99999.1.2.1.4
```

## Nagios

EDIT `objects/commands.cfg`:

```
define command {
	command_name	check_backup_usage
	# warn if less than 4GB free, critical if less than 2GB
	command_line	/usr/lib/nagios/plugins/check_snmp -P2c -H $ARG1$ -o SNMPv2-SMI::enterprises.99999.1.2.1.4.$ARG2$ -u blocks -w 1048576: -c 524288:
}

define command {
	command_name	check_backup_last_write
	# warn if last write time was more than 2 days ago, critical if more than 6 days ago
	command_line	/usr/lib/nagios/plugins/check_snmp -P2c -H $ARG1$ -o SNMPv2-SMI::enterprises.99999.1.2.1.5.$ARG2$ -u seconds -w 172800 -c 518400
}
```

To create the service definitions there is a perl script available:

```bash
/usr/share/snmp/nagios/create_nagios_services.pl
```

This will generate snippets like:

```
# backup-host: backup-ffm-1.ffm
# uuid: 7d0260f4-6670-407c-aaa2-fe13d26017ae
# device: xvdf
# oid: SNMPv2-SMI::experimental.1.3
define service {
	use			generic-service
	service_description	BACKUP_USAGE
	check_command		check_backup_usage!backup-ffm-1.ffm!3
	host_name		web50.serverdienst.net
}
define service {
	use			generic-service
	service_description	BACKUP_LAST_WRITE
	check_command		check_backup_last_write!backup-ffm-1.ffm!3
	host_name		web50.serverdienst.net
}
```

to be appended to the nagios host definition file.

## ToDo's

* write a NIB File to resolve the numeric OIDs.


## Author

* Remus Lazar (rl@cron.eu)
