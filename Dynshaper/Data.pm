package Dynshaper::Data;
#######################################################################
#
# description:	Gemeinsam genutzte Funktionen zum Laden und Speichern der
#		Konfiguration
#
# author:	(c) 2005 Markus Schade <marks@invalid.email>
#
# version:	$Id: Database.pm 6443 2006-02-28 16:25:37Z marks $
#
# license:	GPLv2
#
#######################################################################

use strict;
use Carp;
use vars qw(@ISA);

################## Global initialization ###################

sub load_data {
    my $self	= shift;
    
    if (exists $self->{dbh} and defined $self->{dbh}) {
	#Wenn wir schon eine DB-verbindung haben, dann fuegen wir die Methoden
	#mit DB-Zugriff in die Klassenhierarchie ein
	eval ("require Dynshaper::Data::Database;") or croak $@;
	push @ISA, "Dynshaper::Data::Database";
    } else {
	#sonst versuchen wir trotzdem erstmal eine DB-Verbindung zu bekommen
	my $type = 'Database';
	eval ("require Dynshaper::Data::" . $type) or $type = 'File';
	# wenn das fehlschlaegt, dann muessen wir wohl mit einem File vorlieb
	# nehmen
	eval ("require Dynshaper::Data::" . $type) or croak $@;
	push @ISA, "Dynshaper::Data::$type";
    }

    $self->SUPER::load_config();
}


sub prepare_config_for_exec {
    my $self = shift;
    
    # ausnahmen umrechnen
    my $excepts = $self->get_ptr('excepts');
    foreach my $exception ( keys %{$excepts} ) {
	my $val = $self->get('excepts', $exception, 'conf_rate');
	$val = $self->format_speed($val);
	$self->set('excepts', $exception, 'conf_rate',$val);
    }
    
    my $gruppen = $self->get_ptr('groups');
    my $no_shape = $self->get('config', 1, 'conf_noshape');
    my $bw_int = $self->get('config', 1, 'conf_bwint');
    my $bw_ext = $self->get('config', 1, 'conf_bwext');

    foreach my $gruppe ( keys %{$gruppen} ) {
	my $rate = $self->get('groups', $gruppe, 'conf_rate');
	my $fak = $self->get('groups', $gruppe, 'conf_factor');
	$rate *= $fak;

	# Shaping deaktivieren (conf_in/conf_out), wenn
	# die geregelte Bandbreite groesser als conf_noshape ist
	# oder die Bandbreite der Klasse groesser als die Bandbreite des
	# Interfaces oder das Shaping schon deaktiviert ist
	my $conf_in = $self->get('groups', $gruppe, 'conf_in');
	my $conf_out = $self->get('groups', $gruppe, 'conf_out');
    
	# shape or not shape (for real)
	if ( $rate > $no_shape || $rate > $bw_int || !$conf_in ) {
	    $self->set('groups', $gruppe, 'conf_in', 0);
	}
	if ( $rate > $no_shape || $rate > $bw_ext || !$conf_out ) {
	    $self->set('groups', $gruppe, 'conf_out', 0);
	}

	# format bandwidths
	$rate = $self->format_speed($rate);
	$self->set('groups', $gruppe, 'conf_rate',$rate);
    }

    # change globals
    for my $option ('conf_bwext', 'conf_bwint') {
	my $val = $self->get('config', 1, $option);
	$val = $self->format_speed($val);
	$self->set('config', 1, $option, $val);
    }
}

1;

=head1 NAME

Dynshaper::Data - initialisiert die Datenstrukturen entweder aus der DB
oder File und schreibt Aenderungen zurueck in die DB 

=head1 SYNOPSIS

    $shaper->load_data();

=head2 ARGUMENTS

=over 

=item B<load_data()>

Laedt aus der Datenbank/einem File die Konfigurationsdaten in die
entsprechenden Datenstruktur innerhalb des Objekts. Beim Vorhandenensein eines
Datenbankhandles in $obj->{dbh} wird automatisch die DB Unterstützung gewählt.

=back

=head1 DESCRIPTION

Die B<Dynshaper::Data> Klasse ist die Zwischenschicht, um fuer das eigentliche
Objekt transparent ein Laden und Sichern der Konfiguration zu realisieren.
Dazu wird je nach Fall die Klassenhierarchie geringfuegig modifiziert.

=head1 AUTHOR

Markus Schade <marks@invalid.email>

=cut

