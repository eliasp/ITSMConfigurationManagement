#!/usr/bin/perl
# --
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

# TODO:
# Remove this after the script has been migrated to a console moddule
## nofilter(TidyAll::Plugin::OTRS::Perl::BinScripts)

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);
use lib dirname($RealBin) . '/Custom';

use Getopt::Long;

use Kernel::System::VariableCheck qw(IsArrayRefWithData);
use Kernel::System::ObjectManager;

# create object manager object
local $Kernel::OM = Kernel::System::ObjectManager->new(
    'Kernel::System::Log' => {
        LogPrefix => 'otrs.ITSMConfigItemListDuplicates.pl',
    },
);

print "\n";
print "otrs.ITSMConfigItemListDuplicates.pl\n";
print "List ConfigItems which have a non-unique name.\n";
print "Copyright (C) 2001-2015 OTRS AG, http://otrs.com/\n\n";

my $Help      = '';
my $Class     = '';
my $Scope     = '';
my $AllStates = '';

GetOptions(
    'help'      => \$Help,
    'class=s'   => \$Class,
    'scope=s'   => \$Scope,
    'allstates' => \$AllStates,
);

# show usage
if ($Help) {
    print "Usage: $0 [options] \n\n";
    print "  Options are as follows:\n";
    print "  --help                             display this option help\n";
    print "  --class name                       check only config items of this class\n";
    print "  --scope (global|class)             define the scope for the uniqueness check\n";
    print
        "  --allstates                          also check config items in non-productive states\n\n";
    exit 1;
}

# make sure, the supplied 'scope' is valid
if ( $Scope && $Scope ne 'class' && $Scope ne 'global' ) {
    print "The provided scope is not valid, please use 'class' or 'global'\n";
    exit 1;
}

my %SearchCriteria;

if ($Class) {

    # get class list
    my $ClassList = $Kernel::OM->Get('Kernel::System::GeneralCatalog')->ItemList(
        Class => 'ITSM::ConfigItem::Class',
    );

    # invert the hash to have the classes' names as keys
    my %ClassName2ID = reverse %{$ClassList};

    # check, whether this class exists
    if ( $ClassName2ID{$Class} ) {
        my $ID = $ClassName2ID{$Class};

        # get ids of this class' config items
        $SearchCriteria{ClassIDs} = [$ID];
    }
    else {
        print "Unable to find class name $Class.\n";
    }
}

if ( !$AllStates ) {

    my $StateList = $Kernel::OM->Get('Kernel::System::GeneralCatalog')->ItemList(
        Class       => 'ITSM::ConfigItem::DeploymentState',
        Preferences => {
            Functionality => [ 'preproductive', 'productive' ],
        },
    );

    my $DeploymentStateIDs = [ keys %{$StateList} ];

    $SearchCriteria{DeplStateIDs} = [ keys %{$StateList} ];
}

# get all config items ids
my @ConfigItemIDs = @{ $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->ConfigItemSearch(%SearchCriteria) };

# get number of config items
my $CICount = scalar @ConfigItemIDs;

# if there are any CI to check
if ($CICount) {

    # if the scope was explicitely defined, set it, otherwise this script will fall back to the
    # value set in SysConfig
    if ($Scope) {
        $Kernel::OM->Get('Kernel::Config')->Set(
            Key   => 'UniqueCIName::UniquenessCheckScope',
            Value => $Scope,
        );
    }

    if ($Class) {
        print "Checking config items of class $Class...\n";
    }
    else {
        print "Checking all config items...\n";
    }

    my $DuplicatesFound = 0;

    # check config items
    CONFIGITEMID:
    for my $ConfigItemID (@ConfigItemIDs) {

        # get the attributes of this config item
        my $ConfigItem = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->ConfigItemGet(
            ConfigItemID => $ConfigItemID,
        );

        next CONFIGITEMID if !$ConfigItem->{LastVersionID};

        # get the latest version of this config item
        my $Version = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->VersionGet(
            VersionID  => $ConfigItem->{LastVersionID},
            XMLDataGet => 1,
        );

        next CONFIGITEMID if !$Version;

        if ( !$Version->{Name} ) {
            print "Skipping ConfigItem $ConfigItemID as it doesn't have a name\n";
            next CONFIGITEMID;
        }

        my $Duplicates = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->UniqueNameCheck(
            ConfigItemID => $ConfigItemID,
            ClassID      => $ConfigItem->{ClassID},
            Name         => $Version->{Name}
        );

        if ( IsArrayRefWithData($Duplicates) ) {

            $DuplicatesFound = 1;

            my @DuplicateData;

            for my $DuplicateID ( @{$Duplicates} ) {

                # get the # of the duplicate
                my $DuplicateConfigItem = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->ConfigItemGet(
                    ConfigItemID => $DuplicateID,
                );

                my $DuplicateVersion = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->VersionGet(
                    VersionID => $DuplicateConfigItem->{LastVersionID},
                );

                push @DuplicateData, $DuplicateVersion;
            }

            print "ConfigItem $Version->{Number} (Name: $Version->{Name}, ConfigItemID: "
                . "$Version->{ConfigItemID}) has the following duplicates:\n";

            # list all the details of the duplicates
            for my $DuplicateVersion (@DuplicateData) {
                print "\t$DuplicateVersion->{Number} (ConfigItemID: "
                    . "$DuplicateVersion->{ConfigItemID})\n";
            }
        }
    }

    if ($DuplicatesFound) {
        print "Finished checking for duplicate names\n";
    }
    else {
        print "No duplicate names found\n";
    }
}
else {
    print "There are NO config items to check.\n";
}

print "\n";

1;
