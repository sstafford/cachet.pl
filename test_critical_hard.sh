#!/bin/bash

scriptdir=`dirname $0`
scriptdir=`cd $scriptdir; pwd`

CONFIGFILE="$scriptdir/cachet_handler.properties"
COMPNAME="TestComponentB"
# major, partial, performance
COMPIMPACT="partial"
SERVICEDESC="http service"
# OK, WARNING, UNKNOWN, CRITICAL
SERVICESTATE="OK"
SERVICESTATETYPE="HARD"
SERVICEOUTPUT="404 file not found"

./cachet_handler.pl "$CONFIGFILE" "$COMPNAME" "$COMPIMPACT" "$SERVICEDESC" "$SERVICESTATE" "$SERVICESTATETYPE" "$SERVICEOUTPUT"
