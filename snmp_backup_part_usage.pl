#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper qw(Dumper);
use Getopt::Std;
use File::Basename;
use Date::Parse;

# SNMPv2-SMI::experimental.1.<DEVICE_NO>.<OID_ACTION>

use constant {
    OID_FFM_BACKUP => ".1.3.6.1.4.1.99999.1",
};

use constant {
    # our OID root, currently under enterprises.99999 (iana OIB registration is pending)
    OID_PART_NUMBER                    => OID_FFM_BACKUP . '.1',
    OID_PART_TABLE                     => OID_FFM_BACKUP . '.2',
    OID_PART_TABLE_ENTRY               => OID_FFM_BACKUP . '.2.1',
    OID_PART_TABLE_ENTRY_INDEX         => OID_FFM_BACKUP . '.2.1.1',
    OID_PART_TABLE_ENTRY_DEVICE        => OID_FFM_BACKUP . '.2.1.2',
    OID_PART_TABLE_ENTRY_UUID          => OID_FFM_BACKUP . '.2.1.3',
    OID_PART_TABLE_ENTRY_FREE_BLOCKS   => OID_FFM_BACKUP . '.2.1.4',
    OID_PART_TABLE_ENTRY_LAST_WRITE    => OID_FFM_BACKUP . '.2.1.5',

    # internals
    DEV_INFO_UUID                      => "DEV_INFO_UUID",
    DEV_INFO_FREE_BLOCKS               => "DEV_INFO_FREE_BLOCKS",
    DEV_INFO_LAST_WRITE_TIME           => "DEV_INFO_LAST_WRITE_TIME",
    TUNE2FS_BIN                        => "sudo /sbin/tune2fs",
};

sub snmp_output {
    (my $oid, my $type, my $value) = @_;
    print join("\n",
        $oid,
        $type,
        $value
    ) . "\n";
}

sub get_device_path_from_oid_index {
    my $oid_dev = shift() - 1;

    # our index is positive (non zero) by definition
    return if $oid_dev == -1;

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
        sort {dev_name($a) cmp dev_name($b)}
            grep (/\-/ && dev_name($_) !~ /^xvda\d/, readdir DIR);
    closedir DIR;

    @devices;
}

sub get_disks_count {
    @_ = get_all_disks();
    return scalar(@_);
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

    my $tune2fs_bin = TUNE2FS_BIN;
    my $tune2fs = `$tune2fs_bin -l "$device_path"`;

    foreach (split /[\r\n]+/, $tune2fs) {
        if (index($_, $tune2fs_key) == 0) {
            $_ = substr $_, length($tune2fs_key);
            $_ =~ s/^:\s+//;
            return $_;
        }
    }
}

# parses the OID string and returns a known prefix and the index, if any
sub parse_oid {
    my ($oid) = @_;

    my $oid_prefix = '';
    my $index = undef;

    my @OID = (
        OID_PART_TABLE_ENTRY_LAST_WRITE,
        OID_PART_TABLE_ENTRY_FREE_BLOCKS,
        OID_PART_TABLE_ENTRY_UUID,
        OID_PART_TABLE_ENTRY_DEVICE,
        OID_PART_TABLE_ENTRY_INDEX,
        OID_PART_TABLE_ENTRY,
        OID_PART_TABLE,
        OID_PART_NUMBER,
    );

    foreach (@OID) { # loop over all available OID prefixes and try to match the most specific one
        if ((index $oid, $_) == 0) {
            $oid_prefix = $_;
            # extract the index (last item) if available
            $index = substr($oid, length($_) + 1) if length($oid) > length($_);
            last;
        }
    }

    ($oid_prefix, $index);
}

# checks if the given oid has a specific prefix
sub oid_has_prefix {
    my ($oid, $prefix) = @_;
    (index $oid, $prefix) == 0;
}

# process an SNMP GET request, index being already defined. The given OID MUST resolve to a leaf in the OIB tree,
# else this method will fail.
sub snmp_get {
    my ($oid) = @_;

    my ($oid_prefix, $index) = parse_oid($oid);

    if ($oid_prefix eq OID_PART_NUMBER && defined $index && $index == 0) {
        snmp_output($oid, "INTEGER", get_disks_count());
    }

    elsif ($oid_prefix eq OID_PART_TABLE_ENTRY_INDEX) {
        snmp_output($oid, "INTEGER", $index);
    }

    else {
        my $device_path = get_device_path_from_oid_index($index);
        return unless defined $device_path;

        if ($oid_prefix eq OID_PART_TABLE_ENTRY_DEVICE) {
            snmp_output($oid, "STRING", dev_name($device_path));
        }

        elsif ($oid_prefix eq OID_PART_TABLE_ENTRY_UUID) {
            snmp_output($oid, "STRING", $device_path);
        }

        elsif ($oid_prefix eq OID_PART_TABLE_ENTRY_FREE_BLOCKS) {
            $_ = get_info_from_device($device_path, DEV_INFO_FREE_BLOCKS);
            if (defined()) {
                snmp_output($oid, "INTEGER32", $_);
            }
        }

        elsif ($oid_prefix eq OID_PART_TABLE_ENTRY_LAST_WRITE) {
            $_ = get_info_from_device($device_path, DEV_INFO_LAST_WRITE_TIME);
            if (defined()) {
                snmp_output($oid, "INTEGER32", time() - str2time($_));
            }
        }
    }
}

##
# Fetch the "next" leaf in the OIB tree and returns it. Used by snmpwalk to traverse the OIB tree.
#
# see https://stackoverflow.com/questions/16365940/snmp-extend-as-an-integer-and-not-a-string
#
sub snmp_next {
    my ($oid) = @_;

    my ($oid_prefix, $index) = parse_oid($oid);

    if ($oid_prefix eq OID_PART_NUMBER) {
        return snmp_next(OID_PART_TABLE_ENTRY_INDEX.'.1') if defined $index;
        return snmp_get(OID_PART_NUMBER.'.0');
    } elsif (oid_has_prefix($oid_prefix, OID_PART_TABLE_ENTRY)) {
        return snmp_get(OID_PART_TABLE_ENTRY_INDEX.'.0') if $oid_prefix eq OID_PART_TABLE_ENTRY;
        return snmp_get($oid_prefix.'.1') unless defined $index;

        my $last_index = get_disks_count();
        if ($index < $last_index) {
            return snmp_get($oid_prefix . '.' . ($index + 1));
        }

        my $table_entry = substr($oid_prefix, (length(OID_PART_TABLE_ENTRY)+1));
        if ($table_entry < 5) {
            return snmp_get(OID_PART_TABLE_ENTRY . '.' . ($table_entry + 1) . '.1');
        }
        return
    }

    # catch all
    snmp_next(OID_PART_NUMBER);


    # return snmp_next(0) unless defined $oid_dev;
    # return snmp_get($oid_dev, 0) unless defined $snmp_action;
    # return snmp_get($oid_dev, $snmp_action + 1) if ($snmp_action < OID_ACTION_LAST_WRITE_TIMEINTERVAL);
    # snmp_next($oid_dev + 1);
}

##
# main
#
my %opts;

getopts('h?gn', \%opts) or die("Usage: $0 [-g] [-n] OID");

my $base_dir = "/dev/disk/by-uuid";
chdir($base_dir);

my $oid = $ARGV[0];

snmp_get($oid) if $opts{'g'};
snmp_next($oid) if $opts{'n'};
