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

## ToDo's

* make the SNMP Perl script suid and revert the snmp daemon configuration so the daemon runs as user `snmp`.
* write a NIB File to resolve the numeric OIDs.


## Author

* Remus Lazar (rl@cron.eu)
