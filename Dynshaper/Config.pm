package Dynshaper::Config;
#######################################################################
#
# description:	class for global configuration
#
# author:	(c) 2005 Markus Schade <marks@invalid.email>
#
# version:	$Id: Config.pm 6519 2006-04-06 10:35:28Z marks $
#
# license:	GPLv2
#
#######################################################################

use strict;
use Carp;
use CSN;
use base qw(Dynshaper::Execute);

sub new {
    my ($class, %args) = @_;
    my $self = {
	    p => $args{p} || undef,
	    dbh => $args{dbh} || db_connect('traffic_shaper')
    };

    eval ("require Dynshaper::Config::" . $args{type}) or croak $@;
    my $subclass = "Dynshaper::Config::" . $args{type};
    
    bless ( $self, $subclass);

    $self->load_data();
    return $self;
}

sub display {
    my $self	= shift;
    confess "(Abstract) method display() not implemented by class " . ref($self) ."!";
}

1;
