#!/usr/bin/perl
# ==============================================================================
# This script is invoked by the Nagios "define service" event handler.
# The event handler is defined in the Nagios service definition for each
# item being monitored.  The service definition should look something like this:
#
#     define service {
#         service_description        My Nagios Service Check
#         ...
#         event_handler              cachet_event!/path/to/script/prod.conf!MyCachetComponentName!major
#     }
#
# The corresponding Nagios command definition for the event handler should
# look like this:
#
#     define command {
#         command_name         cachet_event
#         command_line         /path/to/script/cachet_handler.pl $ARG1$ $ARG2$ $ARG3$ $SERVICEDESC$ $SERVICESTATE$ $SERVICESTATETYPE$ $SERVICEOUTPUT$
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
#     cachet_handler.pl 'config' 'compName' 'compImpact' 'svcDesc' 'svcState' 'svcStateType' 'svcOutput'
#
# Arguments:
#
#     config
#         Path to the config file for this script.  The config file contains
#         information for connecting to Cachet.
#
#     compName
#         This is the name of the Cachet component.  The script will use this
#         name to search for a component and create or update incidents
#         associated with that component.
#
#     compImpact
#         Impact that a service outage will have on the component (major, partial, or performance).
#         This field currently does nothing, as all new incidents will cause
#         the component to be updated to "partial outage" until resolved.  However,
#         the impact may be necessary in the future if Cachet functionality improves.
#         TODO: A value of "major" will cause a Major Outage incident to be created.
#         TODO: A value of "partial" will cause a Partial Outage incident to be created.
#         TODO: A value of "performance" will cause a Performance Outage incident to be created.
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
use JSON;
use Config::Simple;
use Data::Dumper;

# Define the component status used by Cachet
my %COMPONENT_STATUS = (
    "operational"   => 1,
    "performance"   => 2,
    "partial"       => 3,
    "major"         => 4
);

# Define the incident status used by Cachet
my %INCIDENT_STATUS = (
    "scheduled"     => 0,
    "investigating" => 1,
    "identified"    => 2,
    "watching"      => 3,
    "fixed"         => 4
);

# Any new incidents opened by a nagios alert should use this status
my $DEFAULT_INCIDENT_STATUS = "investigating";



# Parse the command line arguments and verify that all required arguments have
# been passed in.
my ($config, $compName, $compImpact, $svcDesc, $svcState, $svcStateType, $svcOutput) = @ARGV;
die "Cachet config path is a required argument." if not defined $config;
die "Config file does not exist: " . $config if (! -f $config);
die "Cachet component name is a required argument." if not defined $compName;
die "Cachet component impact is a required argument." if not defined $compImpact;
die "Nagios service description is a required argument." if not defined $svcDesc;
die "Nagios service state is a required argument." if not defined $svcState;
die "Nagios service state type is a required argument." if not defined $svcStateType;
die "Nagios service output is a required argument." if not defined $svcOutput;


# Use the service description to construct the incident name
my $incidentName = "[Nagios] " . $svcDesc;

# Load the Cachet connection information
my $cfg = new Config::Simple($config);

my $cachetBaseUrl  = $cfg->param("base_url");
die "Missing config value: base_url" if not defined $cachetBaseUrl;
my $cachetUsername = $cfg->param("username");
my $cachetApiToken = $cfg->param("api_token");


# Trim the trailing slash off of the base URL
$cachetBaseUrl =~ s/\/$//;

# Construct the Cachet API URL from the base URL
my $cachetApiUrl = $cachetBaseUrl . "/api/v1/";

# Create an object to connect to the Cachet REST API
my $cachet = Cachet->new;
$cachet->setBaseUrl($cachetApiUrl);
$cachet->setEmail($cachetUsername);
$cachet->setApiToken($cachetApiToken);

# Search for any incidents that already exist with that name
my @existingIncidents = searchByName('incidents', $incidentName);
my $existingCount = scalar(@existingIncidents);

# Only create an incident if one does not already exist
if ($existingCount == 0) {
    # Only create an incident if the service is failing
    if ($svcState ne "OK") {
        createCachetIncident($compName, $compImpact, $incidentName, $svcDesc, $svcState, $svcStateType, $svcOutput);
    }
} else {
    updateCachetIncident($compName, $compImpact, $incidentName, $svcDesc, $svcState, $svcStateType, $svcOutput);
}


# ==============================================================================
# Create a new Cachet incident (i.e. service down)
#
# @param  compName      Cachet component name to apply the notification to
# @param  compImpact    Component outage status to assign to the incident
# @param  incidentName  Incident name
# @param  svcDesc       Nagios service definition
# @param  svcState      Nagios staus (OK, WARNING, UNKNOWN, or CRITICAL)
# @param  svcStateType  Nagios status type (HARD or SOFT)
# @parm   svcOutput     First line of text from the Nagios service check
sub createCachetIncident {
    my ($compName, $compImpact, $incidentName, $svcDesc, $svcState, $svcStateType, $svcOutput) = @_;

    my $visible = "1";
    my $notifySubscribers = "false";

    if ($svcStateType eq "HARD") {
        my ($componentHashRef) = getByName('components', $compName);

        # Dereference the hash of component information so we can lookup the ID value
        #print Dumper(@components);
        my %component = %$componentHashRef;

        my $response = $cachet->createIncident(
            $incidentName,
            $INCIDENT_STATUS{$DEFAULT_INCIDENT_STATUS},
            $svcOutput,
            $component{'id'},
            $COMPONENT_STATUS{$compImpact},
            $notifySubscribers,
            $visible);
    }

}

# ==============================================================================
# Update an incident (i.e. service recovering or restored)
#
# @param  compName      Cachet component to apply the notification to
# @param  compImpact    Component outage status to assign to the incident
# @param  incidentName  Incident name
# @param  svcDesc       Nagios service definition
# @param  svcState      Nagios staus (OK, WARNING, UNKNOWN, or CRITICAL)
# @param  svcStateType  Nagios status type (HARD or SOFT)
# @parm   svcOutput     First line of text from the Nagios service check
sub updateCachetIncident {
    my ($compName, $compImpact, $incidentName, $svcDesc, $svcState, $svcStateType, $svcOutput) = @_;

    # Get the incident information
    my ($incidentHashRef) = getByName('incidents', $incidentName);

    # Dereference the hash so we can lookup the ID value
    my %incident = %$incidentHashRef;

    # Update the incident status based on the service information
    my $oldIncidentStatus = $incident{'status'};
    my $newIncidentStatus = undef;
    if ($svcState eq "OK") {
        if ($svcStateType eq "HARD") {
            $newIncidentStatus = $INCIDENT_STATUS{'fixed'};
        } else {
            $newIncidentStatus = $INCIDENT_STATUS{'watching'};
        }
    } else {
        $newIncidentStatus = $INCIDENT_STATUS{'investigating'};
    }

    if ($oldIncidentStatus != $newIncidentStatus) {
        my $response = $cachet->updateIncident(
            $incident{'id'},
            $incident{'name'},
            $newIncidentStatus,
            $incident{'message'},
            $incident{'component_id'},
            $COMPONENT_STATUS{$compImpact},
            $incident{'notify'},
            $incident{'visible'});
    }

    # Update the component status based on the remaining incidents
    updateCachetComponentStatus($incident{'component_id'});
}


# ==============================================================================
# Get the list of all incidents associated with a component and set the
# component status to operational if no incidents exist.  This is a work-around
# to address the fact that the Cachet incident PUT endpoint does not handle
# the update of the component status intelligently.  It does not account
# for the fact that other incidents may exist for the component.
#
# @param   id        Component ID
sub updateCachetComponentStatus {
    my ($id) = @_;

    # Create a hash of search terms and their target values
    my %searchTerms;
    $searchTerms{'component_id'} = $id;

    # Perform the incident search.  The query returns an array reference,
    # so the result needs to be dereferenced before it can be used.
    my $type = "incidents";
    my $arrayRef = $cachet->search($type, \%searchTerms);
    if (defined $arrayRef) {
        my @results = removeInactiveElements($type, $arrayRef);
        my $resultCount = scalar(@results);

        # Set the component as operational if no incidents are open
        if ($resultCount == 0) {
            $cachet->setComponentStatusById($id, $COMPONENT_STATUS{'operational'});
        } else {
            $cachet->setComponentStatusById($id, $COMPONENT_STATUS{'partial'});
        }
    } else {
        $cachet->setComponentStatusById($id, $COMPONENT_STATUS{'operational'});
    }

}


# ==============================================================================
# Query for the component/incident by name and return the information.
#
# @param  type    component or incident
# @param  name    Component or incident name
# @return Hash containing component information
sub getByName {
    my ($type, $name) = @_;
    my ($id) = 0;

    # Create a hash of search terms and their target values
    my %searchTerms;
    $searchTerms{'name'} = $name;

    # Perform the component or incident search.  The query returns an array reference,
    # so the result needs to be dereferenced before it can be used.
    my $arrayRef = $cachet->search($type, \%searchTerms);
    die "No results found for " . $type . " where name=" . $name if ! defined $arrayRef;
    my @results = removeInactiveElements($type, $arrayRef);
    my $resultCount = scalar(@results);

    # Ensure that the search criteria returned only one result
    if ($resultCount < 1) {
        die "Returned no results.\n";
    } elsif ($resultCount > 1) {
        die "Returned " . $resultCount . " results for ". $type . " where name=" . $name;
    }

    # Return a reference to the hash containing component/incident information
    return $results[0];
}


# ==============================================================================
# Query for the component/incident by name and a list of all matches.
#
# @param  type    component or incident
# @param  name    Component or incident name
# @return Reference to an array of hash references
sub searchByName {
    my ($type, $name) = @_;
    my ($id) = 0;

    # Create an array to contain a copy of the results, minus any this method discards
    my @partialResults;

    # Create a hash of search terms and their target values
    my %searchTerms;
    $searchTerms{'name'} = $name;

    # Perform the component or incident search.  The query returns an array reference,
    # so the result needs to be dereferenced before it can be used.
    my $arrayRef = $cachet->search($type, \%searchTerms);
    die "No results found for " . $type . " where name=" . $name if ! defined $arrayRef;

    # Return an array of hash references
    return removeInactiveElements($type, $arrayRef);
}



# ==============================================================================
# Remove any inactive elements from the list and return a new list.
#
# @param  type       component or incident
# @param  arrayRef   Reference to an array of hash references
# @return New array of hash references
sub removeInactiveElements {
    my ($type, $arrayRef) = @_;
    die "Unable to remove inactive " . $type . " elements." if ! defined $arrayRef;

    # Create an array to contain a copy of the results, minus any this method discards
    my @partialResults;

    my @results = @{$arrayRef};
    my $resultIndex = 0;
    my $resultCount = scalar(@results);

    foreach my $hashRef (@results) {
        # If these are incidents, ignore any that are no longer active or visible
        if ($type eq 'incidents') {
            # Discard the current incident if it has already been fixed
            if ($hashRef->{'status'} == $INCIDENT_STATUS{'fixed'}) {
                #print "SSDEBUG: === Discarding fixed incident: " . $hashRef->{'id'} . "\n";
            } elsif ($hashRef->{'visible'} != 1) {
                #print "SSDEBUG: === Discarding hidden incident: " . $hashRef->{'id'} . "\n";
            } else {
                push(@partialResults, $hashRef);
            }

        # If these are components, ignore any that are disabled
        } elsif ($type eq 'components') {
            if ($hashRef->{'enabled'} eq "true") {
                push(@partialResults, $hashRef);
            }
        }
    }


    # Return an array of hash references
    return @partialResults;
}
