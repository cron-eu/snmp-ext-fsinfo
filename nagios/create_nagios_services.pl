#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';
use File::Basename;
use Data::Dumper qw(Dumper);

# resolves the device name (xvdX) from the uid (e.g. cca3e787-6594-4e55-8c24-094c634d9f45)
sub dev_name {
    (my $device_name) = @_;
    basename readlink $device_name;
}

# This determines the xen device number for a given device file. The number is 0 for /dev/xvda, 1 for /dev/xvdb
# and so on.
# see http://xenbits.xenproject.org/docs/unstable/man/xen-vbd-interface.7.html
sub get_xen_device_number {

    use constant {
        MINOR_MASK => 037774000377,
        MINOR_SHIFT => 0,
    };

    my ($device) = @_;
    my $rdev= (stat($device))[6];

    my $minor = ($rdev & MINOR_MASK) >> MINOR_SHIFT;

    if ($minor < 256) {
        return $minor >> 4;
    } else {
        # disks or partitions 16 onwards
        return ($minor >> 20);
    }
}

##
# Fetches a list of all available disks (all directory entries in /dev/disk/by-uuid/)
# hashed by the xen device number
#
sub get_all_disks {
    my $base_dir = "/dev/disk/by-uuid";
    chdir($base_dir);

    opendir(DIR, ".") or die $!;

    my %hash;

    while (my $device_name = readdir DIR) {
        my $xen_device_number = get_xen_device_number($device_name);
        next unless $xen_device_number > 0;

        my $dev_name = dev_name($device_name);
        next unless defined($dev_name);

        $hash{ $xen_device_number } = $device_name;
    }

    %hash;
}

my %uuid_to_oid_array_map = reverse get_all_disks();

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
        my $oid = $uuid_to_oid_array_map{ $uuid };

        if (defined($oid)) {
            $oid++;
            my $device = basename readlink "/dev/disk/by-uuid/" . $uuid;

            my $host = `hostname -f`;
            chomp $host;

            print <<"END";
# backup-host: $host
# uuid: $uuid
# device: $device
# oid: SNMPv2-SMI::enterprises.29662.1.2.1.4.$oid
define service {
	use			generic-service
	service_description	BACKUP_USAGE
	check_command		check_backup_usage!$host!$oid
	host_name		$dir
}
# oid: SNMPv2-SMI::enterprises.29662.1.2.1.5.$oid
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
