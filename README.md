# nagios-cachet-handler
A Nagios event handler to push Nagios notifications to the Cachet API.

## Prerequisites

* A Cachet server
* Perl
* Perl Modules
  * perl-WWW-Curl
  * perl-JSON
  * perl-Config-Simple
* Clone and install the Cachet Perl module
  * git clone https://github.com/sstafford/cachet.pl.git

## Installation

- Get a Cachet API key: Create a new user in Cachet dashboard, login with this user, and get the API key in his profile.
- Copy cachet_notify to /usr/share/nagios3/plugins/eventhandlers (depending on your configuration)
- Change URL and API key in cachet_notification source code
- Try it: `./cachet_handler.pl /nagios/config.properties 'My Cachet component' 'partial' 'My nagios service' CRITICAL HARD 'The service is Critical'`

## Configuration

- Make a Nagios command:
```
  define command {
      command_name    cachet_notify
      command_line    /path/to/script/cachet_handler.pl '$ARG1$' '$ARG2$' '$ARG3$' '$SERVICEDESC$' '$SERVICESTATE$' '$SERVICESTATETYPE$' '$SERVICEOUTPUT$'
  }
```
- Add an event handler on your services:
```
  define service {
      service_description             My nagios service
      ...
      event_handler                   cachet_notify!/path/to/config.properties!My Cachet component!partial
  }
```
- Create a config file
```
base_url = https://demo.cachethq.io/
username = username@yourdomain.com
api_token = iaEZTOx3BM2fcCwsPdRr
```
- Restart nagios
