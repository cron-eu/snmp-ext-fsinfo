# snmp-ext-fsinfo

## Abstract

Gather the free block count and last write timestamp for all available
devices and make this info available via SNMP via a perl script.


## Limitations und known issues

* uses the `tune2fs` binary to retrieve the info which requires an ext2/3/4 file system.
* kind-of specific to our use-case (monitoring a bunch of partitions on our backup server infrastructure)


## Setup

Install SNMP Daemon:

```bash
aptitude install snmpd sudo
```

Make the perl script from the repo available under `/usr/share/snmp/snmp_ext_part_usage.pl`

```bash
cp snmp_ext_part_usage.pl /usr/share/snmp/
chmod +x /usr/share/snmp/snmp_ext_part_usage.pl
```

Configure sudo for the tune2fs binary

```bash
echo "snmp    ALL = (root) NOPASSWD: /sbin/tune2fs -l *" > /etc/sudoers.d/snmp_ext_part_usage_script
```

Configure SNMP Daemon:

EDIT `/etc/snmp/snmpd.conf`

And add this configuration:

```bash
# internet.enterprises.29662.1
pass .1.3.6.1.4.1.29662.1               /usr/bin/perl   /usr/share/snmp/snmp_ext_part_usage.pl
``` 

And in the Access Control block, e.g. allow the IP xxx.xxx.xxx.xxx to get access.

```bash
rocommunity public  xxx.xxx.xxx.xxx
```

.. so the specified IP can access the rocommunity.

Restart the daemon

```bash
/etc/init.d/snmpd restart
```

## Test

```bash
snmpwalk -v2c -c public IP_OR_HOSTNAME SNMPv2-SMI::enterprises.29662.1
```

This should return the free blocks, last write timestamp and other infos like:

```bash
SNMPv2-SMI::enterprises.29662.1.1.0 = INTEGER: 15
SNMPv2-SMI::enterprises.29662.1.2.1.1.1 = INTEGER: 1
SNMPv2-SMI::enterprises.29662.1.2.1.1.2 = INTEGER: 2
SNMPv2-SMI::enterprises.29662.1.2.1.1.3 = INTEGER: 3
SNMPv2-SMI::enterprises.29662.1.2.1.1.4 = INTEGER: 4
SNMPv2-SMI::enterprises.29662.1.2.1.1.5 = INTEGER: 5
SNMPv2-SMI::enterprises.29662.1.2.1.1.6 = INTEGER: 6
SNMPv2-SMI::enterprises.29662.1.2.1.1.7 = INTEGER: 7
SNMPv2-SMI::enterprises.29662.1.2.1.1.8 = INTEGER: 8
SNMPv2-SMI::enterprises.29662.1.2.1.1.9 = INTEGER: 9
SNMPv2-SMI::enterprises.29662.1.2.1.1.10 = INTEGER: 10
(..)
```

To gather a specific info, e.g. only the free block count for all devices:

```bash
snmpwalk -v2c -c public IP_OR_HOSTNAME SNMPv2-SMI::enterprises.29662.1.2.1.4
```

## Nagios

EDIT `objects/commands.cfg`:

```
define command {
	command_name	check_backup_usage
	# warn if less than 4GB free, critical if less than 2GB
	command_line	/usr/lib/nagios/plugins/check_snmp -P2c -H $ARG1$ -o SNMPv2-SMI::enterprises.29662.1.2.1.4.$ARG2$ -u blocks -w 1048576: -c 524288:
}

define command {
	command_name	check_backup_last_write
	# warn if last write time was more than 2 days ago, critical if more than 6 days ago
	command_line	/usr/lib/nagios/plugins/check_snmp -P2c -H $ARG1$ -o SNMPv2-SMI::enterprises.29662.1.2.1.5.$ARG2$ -u seconds -w 172800 -c 518400
}
```

## Author

* Remus Lazar (rl@cron.eu)
