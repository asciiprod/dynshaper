package Dynshaper::Evaluator::Basic;
#######################################################################
#
# description:	class for global reevaluation base on classic math rules
#
# author:	(c) 2005 Markus Schade <marks@invalid.email>
#
# version:	$Id: Basic.pm 6866 2006-09-28 10:48:43Z marks $
#
# license:	GPLv2
#
#######################################################################

use strict;
use Carp;
use Date::Calc qw(:all);
use Dynshaper::Const;
use base qw(Dynshaper::Evaluator);

sub reclassify_global {
    my $self = shift;
    my ($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
    my $days = Days_in_Month($year,$month);
    my $finalday = ( $self->get('config',1,'conf_final') == $hour );

    # set final-day-mode wenn wirklich finalday,
    # damit nur dann neue Statistikwerte eingefuegt werden
    $self->finalday(1) if $finalday;

    if ( $finalday || $self->finalday() ) {
	$self->do_log( $DEBUG{INFO},
	    "Recalculating global params...\n" );

	# Trafficwerte aus der DB laden
	$self->load_traffic_globals;

	# Zuweisen zu lokalen Variablen
	my $month_limit	    = $self->get('config' , 1, 'conf_mlimit');
	my $max_short	    = $self->get('internal', 'traffic', 'max_short');
	my $avg_short	    = $self->get('internal', 'traffic', 'avg_short');
	my $avg_long	    = $self->get('internal', 'traffic', 'avg_long');
	my $group_count	    = $self->get('internal', 'groups', 'count');
	my $diff_limit	    = $self->get('config', 1, 'conf_dgl');

	my $allowed_per_day = $month_limit / $days;

	$self->do_log( $DEBUG{DEBUG},
	    "Tage: $days, Limit: $month_limit ($allowed_per_day) \n");
	$self->do_log( $DEBUG{DEBUG},
	    "Max7: $max_short, Avg7: $avg_short, Avg14: $avg_long \n");


	# Anzahl der Nutzer in der hoechsten (langsamsten) Gruppe
	# Hinweis: dazu muss vorher das reclassify_users() gelaufen sein,
	# was erstaunlich waere, wenn dem nicht so ist.
	my $users_max_group = $self->get('stats',$group_count,'nutzer');
	$users_max_group = $users_max_group > 1 ? $users_max_group : 1;

	# Initial-BB der hoechsten (langsamsten) Gruppe
	my $bb_max_group    = $self->get('groups',$group_count,'conf_rate');


	# Waren wir in den letzten $AVG{short} (z.Z. 7) Tagen
	# ueber dem Tageslimit?
	my $overlimit = ($max_short > $allowed_per_day) ? 1 : 0;


	# Wenn der Durchschnitt der letzten $AVG{long} (14) Tage groesser Null
	# ist (Div by Zero vermeiden! oder wir haben Traffic, juhu!), dann das
	# erlaubte Tageslimit durch diesen dividieren.  Ansonsten auf 1 setzen
	# (entspricht einem Reset)
	my $correction_factor = ($avg_long > 0)
				? $allowed_per_day / $avg_long
				: 1;


	# Differenzierglied oder auch Trafficanstieg
	my $diffglied = ($avg_long > 0) ? $avg_short / $avg_long : 1;

	$self->do_log( $DEBUG{DEBUG},
	    "#Nutzer Grp.$group_count: $users_max_group, " .
	    "Ini-BB $group_count: $bb_max_group bps\n");
	$self->do_log( $DEBUG{DEBUG},
	    "Overlimit: $overlimit, KFak1: $correction_factor " .
	    "Diffglied: $diffglied \n");


	#Faktorgrenzen
	# Es wird mind. ein Paket gesendet
	# wenn BW < MTU wird das Paket trotzdem gesendet.
	# In HTB2 wurde diese Leihgabe wieder zurueckgezahlt.
	# Seit HTB3 nicht mehr. Also muessen wir pro Nase mind. 1 MTU/s erlauben
	# Eth MTU = 1500 Byte = 12kBit
	# ABER default r2q = 10, also muessten es 120kBit sein, um ein Quantum
	# gleich der MTU zu erhalten. Deswegen Quantum manuell festlegen
	my $base_unit = 12000;
	#$self->convert_without_unit(1,'kbit','bps');
	my $min_factor= $base_unit * $users_max_group / $bb_max_group;
	my $max_factor= $self->get('config', 1, 'conf_noshape') / 
			 $self->get('groups', $group_count, 'conf_rate');

	$self->do_log( $DEBUG{DEBUG},
	    "Min-Faktor: $min_factor, Max-Faktor: $max_factor\n");

	# Korrekturfaktor auf den Faktor jeder Gruppe anwenden
	# evtl. Diffglied
	foreach my $group (sort {$a <=> $b} 
	    keys %{ $self->{ $DB_Tables{groups} }{entries} } ) {
	
	    #aktuellen Faktor holen
	    my $current_factor = $self->get('groups',$group,'conf_factor');
	
	    # Faktor mit Korrekturfaktor multiplizieren
	    my $new_factor = $current_factor * $correction_factor;

	    $self->do_log( $DEBUG{DEBUG},
		"Gruppe $group: alter Faktor: $current_factor, " .
		"neuer Faktor (ohne Diffglied) $new_factor\n");

	    # Wenn das Diffglied ueber eine bestimmte Schranke (1.01) steigt,
	    # d.h. es ist ein schneller Anstieg zu verzeichnen,
	    # dann geht das Diffglied in der 4.Potenz ein
	    if ( ( $diffglied > $diff_limit ) && $overlimit ) {
		    $new_factor = $new_factor / ($diffglied ** 4);

		    $self->do_log( $DEBUG{DEBUG},
			"Gruppe $group: Faktor (mit Diffglied): $new_factor\n");
	    }

	    #Faktor begrenzen und runden
	    if ( $new_factor < $min_factor ) {
		$new_factor = $min_factor;
	    }
	    if ( $new_factor > $max_factor ) {
		$new_factor = $max_factor;
	    }

	    my $final_factor = 0;
	    $final_factor = sprintf("%.4f", $new_factor);

	    $self->do_log( $DEBUG{DEBUG},
		    "Endgueltiger Faktor: $final_factor\n");

	    $self->change('stats', $group, 'anstieg', sprintf("%.4f", $diffglied) );
	    $self->change('stats', $group, 'faktor', $final_factor);
	    $self->change('groups', $group, 'conf_factor', $final_factor);

	} # END foreach group


    } # ENDIF $finalday

}

1;
