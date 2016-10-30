#!/usr/bin/perl
# ==============================================================================
# This script is invoked by the Nagios "define service" event handler.
# The event handler is defined in the Nagios service definition for each
# item being monitored.  The service definition should look something like this:
#
#     define service {
#         service_description        My Nagios Service Check
#         ...
#         event_handler              cachet_event!MyCachetComponentName
#     }
#
# The corresponding Nagios command definition for the event handler should
# look like this:
#
#     define command {
#         command_name         cachet_event
#         command_line         /path/to/script/cachet_handler.pl $ARG1$ $SERVICEDESC$ $SERVICESTATE$ $SERVICESTATETYPE$ $SERVICEOUTPUT$
#     }
#
# When a Nagios event occurs, it will trigger this script by invoking the
# event handler and pass in the component name, as well as some additional
# Nagios values associated with the service.
#
#
# Additional information about Nagios service definitions can be found here:
# https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/3/en/objectdefinitions.html#service
#
# Additional information about Nagios event handlers can be found here:
# https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/3/en/eventhandlers.html
#
# Additional information about Nagios macro values can be found here:
# https://assets.nagios.com/downloads/nagioscore/docs/nagioscore/3/en/macrolist.html
#
#
#
# This script can be tested from the command line using the following syntax:
#
# Usage:
#     cachet_handler.pl 'compName' 'svcDesc' 'svcState' 'svcStateType' 'svcOutput'
#
# Arguments:
#
#     compName
#         This is the name of the Cachet component.  The script will use this
#         name to search for a component and create or update incidents
#         associated with that component.
#
#     compImpact
#         Impact that a service outage will have on the component (major, partial, or performance).
#         A value of "major" will cause a Major Outage incident to be created.
#         A value of "partial" will cause a Partial Outage incident to be created.
#         A value of "performance" will cause a Performance Outage incident to be created.
#
#     svcDesc
#         A long name/description of the service (i.e. "HTTP Status Check")
#
#     svcState
#         The state of the Nagios service (OK, WARNING, UNKNOWN, or CRITICAL)
#
#     svcStateType
#         The type of Nagios service state (HARD or SOFT)
#         Soft states occur when a service check has transitioned to a new value
#         and is in the process of being retried to verify the state is stable.
#         Hard states occur when a service check has remained stable for a specified
#         number of times.
#
#     svcOutput
#         The first line of text from the service check (i.e. "Ping OK")
#
# ==============================================================================

use strict;
use warnings;
use Cachet;
use Data::Dumper;

# Define the component incident status used by Cachet
my %COMPONENT_STATUS = (
    "operational" => 1,
    "performance" => 2,
    "partial"     => 3,
    "major"       => 4
);


# Parse the command line arguments and verify that all required arguments have
# been passed in.
my ($compName, $compImpact, $svcDesc, $svcState, $svcStateType, $svcOutput) = @ARGV;
if (not defined $compName) {
    die "Cachet component name is a required argument.";
} else {
    print "Component: $compName\n";
}

if (not defined $compImpact) {
    die "Cachet component impact is a required argument.";
} else {
    print "Component: $compImpact\n";
}

if (not defined $svcDesc) {
    die "Nagios service description is a required argument.";
} else {
    print "Svc Desc: $svcDesc\n";
}

if (not defined $svcState) {
    die "Nagios service state is a required argument.";
} else {
    print "Svc State: $svcState\n";
}

if (not defined $svcStateType) {
    die "Nagios service state type is a required argument.";
} else {
    print "Svc State Type: $svcStateType\n";
}
if (not defined $svcOutput) {
    die "Nagios service output is a required argument.";
} else {
    print "Svc Output: $svcOutput\n";
}


# Create an object to connect to the Cachet REST API
my $cachet = Cachet->new;
$cachet->setBaseUrl('https://demo.cachethq.io/api/v1/');
$cachet->setEmail('shawn@staffco.org');
#$cachet->setPassword('');
#$cachet->setApiToken('');

#
# Take action based upon the svcState and svcStateType values.
#
if ($svcState eq "OK") {
    updateCachetIncident($compName, $compImpact, $svcDesc, $svcState, $svcStateType, $svcOutput);
} else {
    createCachetIncident($compName, $compImpact, $svcDesc, $svcState, $svcStateType, $svcOutput);
}


# ==============================================================================
# Create a new Cachet incident (i.e. service down)
#
# @param  compName      Cachet component name to apply the notification to
# @param  compImpact    Component outage status to assign to the incident
# @param  svcDesc       Nagios service definition
# @param  svcState      Nagios staus (OK, WARNING, UNKNOWN, or CRITICAL)
# @param  svcStateType  Nagios status type (HARD or SOFT)
# @parm   svcOutput     First line of text from the Nagios service check
sub createCachetIncident {
    my ($compName, $compImpact, $svcDesc, $svcState, $svcStateType, $svcOutput) = @_;

    my $incidentName = "[Nagios] " . $svcDesc;
    my $notifySubscribers = "false";

    if ($svcStateType eq "HARD") {
        my ($componentHashRef) = getComponentByName($compName);

        # Dereference the hash of component information so we can lookup the ID value
        #print Dumper(@components);
        my %component = %$componentHashRef;

        print "Creating incident for Component ID: " . $component{'id'} . "\n";
        print "Incident name: " . $incidentName . "\n";
        print "Component status: " . $compImpact . " -> " . $COMPONENT_STATUS{$compImpact} . "\n";
        print "Incident message: " . $svcOutput . "\n";
        $cachet->createIncident(
            $incidentName,
            $COMPONENT_STATUS{$compImpact},
            $svcOutput,
            $component{'id'},
            $notifySubscribers);
    } else {
        print "Skip incident creation for SOFT events.\n";
    }

}

# ==============================================================================
# Update an incident (i.e. service recovering or restored)
#
# @param  compName      Cachet component to apply the notification to
# @param  compImpact    Component outage status to assign to the incident
# @param  svcDesc       Nagios service definition
# @param  svcState      Nagios staus (OK, WARNING, UNKNOWN, or CRITICAL)
# @param  svcStateType  Nagios status type (HARD or SOFT)
# @parm   svcOutput     First line of text from the Nagios service check
sub updateCachetIncident {
    my ($compName, $compImpact, $svcDesc, $svcState, $svcStateType, $svcOutput) = @_;

    if ($svcStateType eq "HARD") {
        print "Updating incident to CLOSED.\n";
    } else {
        print "Updating incident to WATCHING.\n";
    }
}


# ==============================================================================
# Query for the component by name and return the component information.
#
# @param  name    Component name
# @return Hash containing component information
sub getComponentByName {
    my ($name) = @_;
    my ($id) = 0;

    # Create a hash of search terms and their target values
    my %searchTerms;
    $searchTerms{'name'} = $name;

    # Perform the component search.  The query returns an array reference,
    # so the result needs to be dereferenced before it can be used.
    my $componentsRef = $cachet->search('components', \%searchTerms);
    #my $componentsRef = $cachet->getComponents;
    my @components = @{$componentsRef};
    my $componentCount = scalar(@components);
    print "Number of components: " . $componentCount . "\n";

    # Ensure that the search criteria returned only one result
    #my $componentCount = scalar @components;
    if ($componentCount < 1) {
        die "Returned no results.\n";
    } elsif ($componentCount > 1) {
        die "Returned " . $componentCount . " results.";
    }

    # Return a reference to the hash containing component information
    return $components[0];
}
