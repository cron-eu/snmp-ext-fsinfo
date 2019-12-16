#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use File::Basename;
use Data::Dumper qw(Dumper);

##
# Loop over all available backup directories and outputs Nagios (v3) service definitions to be copy-and-pasted
#

# resolves the device name (xvdX) from the uid (e.g. cca3e787-6594-4e55-8c24-094c634d9f45)
sub dev_name {
    (my $device_name) = @_;
    basename readlink $device_name;
}

##
# Fetches a list of all available disks (all directory entries in /dev/disk/by-uuid/)
# sorted by the underlying device in /dev/xvdX
#
sub get_all_disks {
    my $base_dir = "/dev/disk/by-uuid";
    chdir($base_dir);
    opendir(DIR, $base_dir) or die $!;

    # filter out all devices without a valid uuid and also all xvdaX devices, .e.g. /dev/xvda5
    my @devices =
        sort { dev_name($a) cmp dev_name($b) }
        grep(/\-/ && dev_name($_) !~ /^xvda\d/, readdir DIR);
    closedir DIR;

    @devices;
}


my @uuid_to_oid_array = get_all_disks();

chdir "/backup/RSYNC-BACKUP" or die $!;

opendir(DIR, ".") or die $!;
my @dirs = readdir DIR;
closedir DIR;

foreach my $dir (@dirs) {
    # e.g. web23.serverdienst.net
    if (-l $dir) {

        # e.g. 00be18cd-d47f-4515-aac5-c7cab6cb0830
        my $uuid = basename readlink $dir;

        # e.g. 9
        my ($oid) = grep { $uuid_to_oid_array[$_] eq $uuid } (0 .. @uuid_to_oid_array-1);

        if (defined($oid)) {
            $oid++;
            my $device = basename readlink "/dev/disk/by-uuid/" . $uuid;

            my $host = `hostname -f`;
            chomp $host;

            print <<"END";
# backup-host: $host
# uuid: $uuid
# device: $device
# oid: SNMPv2-SMI::enterprises.99999.1.2.1.4.$oid
define service {
	use			generic-service
	service_description	BACKUP_USAGE
	check_command		check_backup_usage!$host!$oid
	host_name		$dir
}
# oid: SNMPv2-SMI::enterprises.99999.1.2.1.5.$oid
define service {
	use			generic-service
	service_description	BACKUP_LAST_WRITE
	check_command		check_backup_last_write!$host!$oid
	host_name		$dir
}

END
        }
    }
}
