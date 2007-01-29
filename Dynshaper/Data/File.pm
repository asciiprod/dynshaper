package Dynshaper::Data::File;
#######################################################################
#
# description:	class for parsing config file
#
# author:	(c) 2005 Markus Schade <marks@invalid.email>
#
# version:	$Id$
#
# license:	GPLv2
#
#######################################################################

use strict;
use Carp;
use ConfigFile;
use Dynshaper::Const;
use base qw(Dynshaper::Units);

sub load_config {
    my $self = shift;

    # Debugging aus (per default)
    $self->{_DEBUG} = 0;
    $self->{_DEVEL} = 0;
    # global Neuberechnung nur laut config-Paramtern
    $self->{_FINALDAY} = 0;
    # Trafficdaten der Nutzer aus der DB statt einem Dump-File holen
    $self->{_USE_TRAFFIC_DUMP} = 0;

    my $cf = ConfigFile::read_config_file($DS_CONFIG);
    my %common_keys = (
		    'BWINT'	=> 'conf_bwint',
		    'BWEXT'	=> 'conf_bwext',
		    'DEVEXT'	=> 'conf_devext',
		    'DEVINT'	=> 'conf_devint',
		    'MODPROBE'	=> 'conf_mppath',
		    'TC'	=> 'conf_tcpath',
    );

    foreach my $key (keys %$cf) {
	if (ref($cf->{$key}) eq 'HASH') {
		    foreach my $subkey (keys %{$cf->{$key}}) {
			$cf->{$key}{$subkey} =~ s/"//g;
		    }
	}
	else {
	    $cf->{$key} =~ s/"//g;
	}
    }

    foreach my $key (keys %common_keys) {
	if (exists $cf->{$key}) {
	    $self->{ $DB_Tables{config} }{entries}{1}{params}{ $common_keys{$key} }{value} = $cf->{$key};
	    $self->{ $DB_Tables{config} }{entries}{1}{params}{ $common_keys{$key} }{changed} = 0;
	    $self->{ $DB_Tables{config} }{entries}{1}{changed} = 0;
	}
    }
   
    my @groups = split /,/, $cf->{'UGROUPS'};
    
    $self->{ $DB_Tables{internal} }{entries}{groups}{count} = scalar @groups;
    
    foreach my $group (@groups) {
	for my $key ('IN','OUT','RATE') {
	    my $param_key = 'conf_' . lc($key);
	   
	    $self->{ $DB_Tables{groups} }{entries}{$group}{params}{$param_key}{value} 
		= $cf->{$key}{$group};
	    $self->{ $DB_Tables{groups} }{entries}{$group}{params}{$param_key}{changed} = 0;
	    $self->{ $DB_Tables{groups} }{entries}{$group}{changed} = 0;
 
	}
    }
    $self->{ $DB_Tables{groups} }{changed} = 0;

    my @excepts = split /,/, $cf->{'EXCEPTS'};

    foreach my $except (@excepts) {
	for my $key ('EBOUND', 'ERATE', 'EPRIO') {
	    my $param_key = 'conf_' . substr(lc($key), 1);
	    $self->{ $DB_Tables{excepts} }{entries}{$except}{params}{$param_key}{value} 
		= $cf->{$key}{$except};

	}
	for my $key ('EIN', 'EOUT') {
	    my $param_key = 'conf_' . substr(lc($key), 1);
	    push @{$self->{ $DB_Tables{excepts} }{entries}{$except}{params}{$param_key}{value}}, 
	    split(/;/, $cf->{$key}{$except});
	}
    }
    $self->{ $DB_Tables{excepts} }{changed} = 0;

    foreach my $group (@groups) {
	my @groupmarks = split /;/, $cf->{'MARKS'}{$group};
	foreach my $entry (@groupmarks) {
	    my ($uid, $fwmarks) = split /:/, $entry;
	    my @marks = split /,/, $fwmarks;
	    
	    $self->{ $DB_Tables{users} }{entries}{ $uid }{gruppe} = $group;
	    $self->{ $DB_Tables{users} }{entries}{ $uid }{changed} = 0;
	    
	    foreach my $mark (@marks) {
		push @{ $self->{ $DB_Tables{users} }{entries}{$uid}{fwmark} }, $mark;
	    }

	}
    }
    $self->{ $DB_Tables{users} }{changed} = 0;
}


sub load_traffic_users {
    my $self = shift;

    croak "Method load_traffic_users() not implemented by class " . ref($self) ."!";
}


sub load_traffic_globals {
    my $self	= shift;

    croak "Method load_traffic_globals() not implemented by class " . ref($self) ."!";
}


sub get_max_traffic {
    my $self	= shift;

    croak "Method get_max_traffic() not implemented by class " . ref($self) ."!";
}


sub get_avg_traffic {
    my $self	= shift;

    croak "Method get_avg_traffic() not implemented by class " . ref($self) ."!";
}

###################  Zurueckschreiben der Aenderungen ###################

sub commit {
    my $self = shift;
    
    croak "Method commit() not implemented by class " . ref($self) ."!";
}

1;
