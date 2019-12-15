#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper qw(Dumper);
use Getopt::Std;
use File::Basename;
use Date::Parse;

# SNMPv2-SMI::experimental.1.<DEVICE_NO>.<OID_ACTION>

use constant {
    OID_ROOT                   => ".1.3.6.1.3.1", # SNMPv2-SMI::experimental.1

    OID_ACTION_DEVICE          => 0,
    OID_ACTION_UUID            => 1,
    OID_ACTION_FREE_BLOCKS     => 2,
    OID_ACTION_LAST_WRITE_TIME => 3,

    DEV_INFO_UUID              => "DEV_INFO_UUID",
    DEV_INFO_FREE_BLOCKS       => "DEV_INFO_FREE_BLOCKS",
    DEV_INFO_LAST_WRITE_TIME   => "DEV_INFO_LAST_WRITE_TIME",
};

sub snmp_output {
    (my $oid_ref, my $type, my $value) = @_;

    print OID_ROOT . '.' . join('.', @$oid_ref) . "\n";
    print $type . "\n";
    print $value . "\n";
}

sub get_device_path_from_oid_index {
    my $oid_dev = shift();
    my @devices = get_all_disks();
    $devices[$oid_dev];
}

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
    opendir(DIR, ".") or die $!;

    # filter out all devices without a valid uuid and also all xvdaX devices, .e.g. /dev/xvda5
    my @devices =
        sort { dev_name($a) cmp dev_name($b) }
        grep(/\-/ && dev_name($_) !~ /^xvda\d/, readdir DIR);
    closedir DIR;

    @devices;
}

# fetches a specific info from the given device
sub get_info_from_device {

    (my $device_path, my $key) = @_;

    my %tune2fs_keys = (
        DEV_INFO_UUID            => "Filesystem UUID",
        DEV_INFO_FREE_BLOCKS     => "Free blocks",
        DEV_INFO_LAST_WRITE_TIME => "Last write time"
    );

    my $tune2fs_key = $tune2fs_keys{$key};

    my $tune2fs = `/sbin/tune2fs -l "$device_path"`;

    foreach (split /[\r\n]+/, $tune2fs) {
        if (index($_, $tune2fs_key) == 0) {
            $_ = substr $_, length($tune2fs_key);
            $_ =~ s/^:\s+//;
            return $_;
        }
    }
}

# process the specific action for an existing mountpoint
sub snmp_process_endpoint {
    (my $oid_ref, my $device_path, my $action) = @_;

    if ($action == OID_ACTION_DEVICE) {
        snmp_output($oid_ref, "STRING", dev_name($device_path));
    } elsif ($action == OID_ACTION_UUID) {
        snmp_output($oid_ref, "STRING", $device_path);
    } elsif ($action == OID_ACTION_FREE_BLOCKS) {
        $_ = get_info_from_device($device_path, DEV_INFO_FREE_BLOCKS);
        if (defined()) {
            snmp_output($oid_ref, "INTEGER32", $_);
        }
    } elsif ($action == OID_ACTION_LAST_WRITE_TIME) {
        $_ = get_info_from_device($device_path, DEV_INFO_LAST_WRITE_TIME);
        if (defined()) {
            snmp_output($oid_ref, "INTEGER32", str2time($_));
        }
    }
}

# process an SNMP GET request
sub snmp_get {
    my @oid = @_;
    (my $oid_dev, my $snmp_action) = @oid;

    if (defined $oid_dev) {
        my $device_path = get_device_path_from_oid_index($oid_dev);
        if (defined $device_path) {
            snmp_process_endpoint(\@oid, $device_path, $snmp_action);
        }
    }
}

##
# Determine the next leaf in the OIB tree and return it
#
# see https://stackoverflow.com/questions/16365940/snmp-extend-as-an-integer-and-not-a-string
#
sub snmp_next {
    (my $oid_dev, my $snmp_action) = @_;

    unless (defined $oid_dev) {
        snmp_get(0,0);
        return;
    }

    unless (defined($snmp_action)) {
        snmp_get($oid_dev + 1, 0);
        return;
    }

    if ($snmp_action < OID_ACTION_LAST_WRITE_TIME) {
        snmp_get($oid_dev, $snmp_action + 1);
        return;
    } else {
        snmp_get($oid_dev + 1, 0);
        return;
    }
}

##
# main
#
my %opts;

sub usage() { die("Usage: $0 [-g] [-n] OID"); }
getopts('h?gn', \%opts) or usage;

my $base_dir = "/dev/disk/by-uuid";
chdir($base_dir);

if ( (index $ARGV[0], OID_ROOT) >= 0) {
    $_ = substr($ARGV[0], length(OID_ROOT));
    my @oid = split(/\./);
    shift(@oid);

    if ($opts{'g'}) {
        snmp_get(@oid);
    } elsif ($opts{'n'}) {
        snmp_next(@oid);
    }

} else { die("OID must match the prefix " . OID_ROOT); }