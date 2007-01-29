package Dynshaper::Units;
#######################################################################
#
# description:	zur Einheitenkonvertierung genutzte Funktionen
#
# author:	(c) 2005 Markus Schade <marks@invalid.email>
#
# version:	$Id: Units.pm 6515 2006-04-06 10:32:08Z marks $
#
# license:	GPLv2
#
#######################################################################

use strict;
use Carp;
use Dynshaper::Const;
use base qw( Dynshaper );

sub convert_unit {
    my $self	= shift;
    my $value	= shift;
    my $from	= shift;
    my $to	= shift;
    my $result	= 0;

    $result = $self->convert_without_unit($value,$from,$to);
    $result .= lc($to) if $result != 0;

    return $result;
}

sub convert_without_unit {
    my $self	= shift;
    my $value	= shift;
    my $from	= shift;
    my $to	= shift;
    my $result	= $value;

    $self->do_log( $DEBUG{VERBOSE}, "Konvertiere $value $from nach $to\n");

    if ( $self->unit_check($from) && $self->unit_check($to) ) {
	$from = lc($from);
	$to = lc($to);
    }
    else {
	return 0;
    }

    $self->do_log( $DEBUG{VERBOSE}, "Konvertiere $UNITS{$from} ($UNIT_AMOUNT{$from}) " .
	"nach $UNITS{$to} ($UNIT_AMOUNT{$to})\n");

    if ( $UNITS{$from} ne $UNITS{$to} ) {
	if ( $UNIT_AMOUNT{$from} > $UNIT_AMOUNT{$to} ) {
	    $result = $value * ( $UNIT_AMOUNT{$from} / $UNIT_AMOUNT{$to} );
	}
	else {
	    $result = $value / ( $UNIT_AMOUNT{$to} / $UNIT_AMOUNT{$from} );
	}
    }

    $self->do_log( $DEBUG{VERBOSE}, "Konvertiert: $value $from = $result $to\n");

    return $result;
}

sub unit_check {
    my $self	= shift;
    my $unit	= shift;

    $unit = lc($unit);

    if ( exists $UNITS{$unit} ) {
	return 1;
    }

    return 0;
}

sub split_unit {
    my $self	= shift;
    my $param	= shift;
    my $type	= shift || 'bw';	# Typ: Bandbreite oder Volumen
    my $value	= 0;
    my $unit	= '';
    
    if ( $param =~ m/^(\d+[\.,]?\d+?)(\s+)?([a-zA-Z]+)?$/ ) {
	$value = $1;
	$unit  = lc($3);

	if ( $unit eq '' ) {
	    if ( $type eq 'bw' ) {
		$unit = 'bps';
	    }
	    else {
		$unit = 'b';
	    }
	}
	if ( exists $UNITS{$unit} ) {
	    return ($value,$unit);
	}
    }

    $self->do_log( $DEBUG{ERROR},
	"Kann $param nicht in Wert und Einheit aufsplitten!\n");

    return (-1,'bps');
}

sub format_speed {
    my $self	= shift;
    my $val	= shift;

    return 0 if $val eq "-1";
    
    if ($val > 10*(1000**2)) {
	return sprintf ("%d"."mbit", ( $val/(1000**2) ) );
    } 
    elsif ($val > 1000**2) {
	return sprintf ("%d"."kbit", ($val/1000) );
    } 
    elsif ($val > 1000) {
	return sprintf ("%d"."kbit", ($val/1000) );
    } 
    else {
	return sprintf ("%d"."bps", ($val) );
    }
}

sub format_volume {
    my $self	= shift;
    my $val	= shift;

    return 0 if $val eq "-1";
    
    if ($val > 10*(1024**3)) {
	return sprintf ("%d"."GB", ( $val/(1024**3) ) );
    } 
    elsif ($val > (1024**2)) {
	return sprintf ("%d"."MB", ( $val/(1024**2) ) );
    } 
    elsif ($val > 1024) {
	return sprintf ("%d"."KB", ($val/1024) );
    } 
    else {
	return sprintf ("%d"."B", ($val) );
    }
}

1;
