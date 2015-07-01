package Cachet;
use Exporter 'import';
use strict;
use warnings;
use WWW::Curl::Easy;
use JSON;
use MIME::Base64;

my @ISA = qw(Exporter);
my @EXPORT = ();
my @EXPORT_OK = ('isWorking');


sub new {
	my $pkg = shift;
	my $self = {};
	
	$self->{'baseUrl'} = '';	
	$self->{'email'} = '';
	$self->{'password'} = '';
	$self->{'apiToken'} = '';
	bless($self,$pkg);
	return $self;
}
sub getBaseUrl {
	my $self = shift;
	return $self->{'baseUrl'};
}

sub getEmail {
	my $self = shift;
	return $self->{'email'};
}

sub getPassword {
	my $self = shift;
	return $self->{'password'};
}

sub getApiToken {
	my $self = shift;
	return $self->{'apiToken'};
}


sub setBaseUrl {
	my $self = shift;
	my $url = shift;
	$self->{'baseUrl'} = $url;
}

sub setEmail {
	my $self = shift;
	my $mail = shift;
	$self->{'email'} = $mail;
}

sub setPassword {
	my $self = shift;
	my $pw = shift;
	$self->{'password'} = $pw;
}
sub setApiToken {
	my $self = shift;
	my $token = shift;
	$self->{'apiToken'} = $token;
}

sub sanityCheck {
	my $self = shift;
	my $authorisationRequired = shift;
	if(!$self->{'baseUrl'}) {
		die ('cachet.pm: The base URL is not set for your cachet instance. Set one with the setBaseURL method.');
	}
	#TODO:  base url regex check

	if($authorisationRequired && (!$self->{'apiToken'} && (!$self->{'email'} || !$self->{'password'}))) {
		#TODO:  email regex check
		die ('cachet.pm: The apiToken is not set for your cachet instance. Set one with the setApiToken method. Alternatively, set your email and password with the setEmail and setPassword methods respectively');
	}
}



sub curlGet {
	my $self = shift;
	my $url = shift;
	my $responseBody; 
	my $curl = WWW::Curl::Easy->new;
	
	$curl->setopt(CURLOPT_HEADER,0);
	$curl->setopt(CURLOPT_URL,$url);
	$curl->setopt(CURLOPT_WRITEDATA,\$responseBody);

	my $retcode = $curl->perform;	
	if($retcode == 0) {
		my $decoded = decode_json($responseBody);
		#TODO: Error handling for decode_json
		return $decoded->{'data'};
	} else {
		return $retcode;
	}

}

sub curlPut {
	my $self =shift;
	my $url = shift;
	my $data = shift;
	my $curl = WWW::Curl::Easy->new;
	my $responseBody; 

	$curl->setopt(CURLOPT_HEADER,0);
	$curl->setopt(CURLOPT_URL,$url);
	$curl->setopt(CURLOPT_CUSTOMREQUEST,'PUT');
	$curl->setopt(CURLOPT_POSTFIELDS,$data);
	
	my @HTTPHeader = (); 
	my $authorisationHeader = 'Authorization: Basic ' . encode_base64($self->{'email'} . ':' . $self->{'password'});

	if($self->{'apiToken'}) {
		$authorisationHeader = 'X-Cachet-Token: ' . $self->{'apiToken'};
	}
		
	push(@HTTPHeader,$authorisationHeader);
	$curl->setopt(CURLOPT_WRITEDATA,\$responseBody);
	$curl->setopt(CURLOPT_HTTPHEADER,\@HTTPHeader);
	my $retcode = $curl->perform;
	if($retcode == 0) {
		my $decoded = decode_json($responseBody);
		#TODO: Error handling for decode_json
		return $decoded->{'data'};
	} else {
		return $retcode;
	}
}

sub ping {
	my $self = shift;
	$self->sanityCheck(0);
	
	my $url = $self->{'baseUrl'} . 'ping';
	return $self->curlGet($url);
}

sub get {
	my $self = shift;
	my $type = shift;
	if($type ne 'components' && $type ne 'incidents' && $type ne 'metrics') {
		die('cachet.php: Invalid type specfied. Must be \'components\', \'incidents\' or \'metrics\'');
	}
	$self->sanityCheck(0);
	
	my $url = $self->{'baseUrl'} . $type;
	return $self->curlGet($url);
}


sub getById {
	my $self = shift;
	my $type = shift;
	my $id = shift;
	if($type ne 'components' && $type ne 'incidents' && $type ne 'metrics') {
		die('cachet.pm: Invalid type specfied. Must be \'components\', \'incidents\' or \'metrics\'');
	}
	if(!$id) {
		die('cachet.pm: No id supplied');
	}
	$self->sanityCheck(0);

	my $url = $self->{'baseUrl'} . $type . '/' . $id;
	return $self->curlGet($url);
}


# Exported Functions

sub isWorking() {
	my $self =shift;
	return($self->ping() eq 'Pong!');
}


sub setComponentStatusById {
	my $self =shift;
	my $id = shift;
	my $status = shift;
	$self->sanityCheck(1);
	if (!$id) {
		die('cachet.pm: You attempted to set a component status by ID without specifying an ID.');
	}
	my $url = $self->{'baseUrl'} . 'components/' . $id;
	my $requestData = 'status='.$status;	
	return $self->curlPut($url,$requestData);
}

sub getComponents {
	my $self =shift;
	return $self->get('components');

}

sub getComponentById {
	my $self = shift;
	my $id = shift;
	return $self->getById('components',$id);
}

sub getIncidents {
	my $self =shift;
	return $self->get('incidents');
}

sub getIncidentById {
	my $self = shift;
	my $id = shift;
	return $self->getById('incidents',$id);
}

sub getMetrics {
	my $self =shift;
	return $self->get('metrics');
}

sub getMetricById {
	my $self = shift;
	my $id = shift;
	return $self->getById('metrics',$id);
}


1;