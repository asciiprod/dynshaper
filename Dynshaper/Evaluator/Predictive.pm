package Dynshaper::Evaluator::Predictive;
#######################################################################
#
# description:	class for global distribution based on CBR rules
#
# author:	(c) 2005 Markus Schade <marks@invalid.email>
#
# version:	$Id: Predictive.pm 7215 2008-06-13 14:52:35Z marks $
#
# license:	GPLv2
#
#######################################################################

use strict;
use Carp;
use Date::Calc qw(:all);
use POSIX;
use Dynshaper::Const;
use base qw(Dynshaper::Evaluator);

sub reclassify_global {
    my $self = shift;
    my ($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
    my $days = Days_in_Month($year,$month);
    my $days_left = ($days - $day) + 1;
    my ($yyear,$ymonth,$yday) = Add_Delta_Days($year,$month,$day,-1);
    my $finalday = ( $self->get('config',1,'conf_final') == $hour );

    # set final-day-mode wenn wirklich finalday,
    # damit nur dann neue Statistikwerte eingefuegt werden
    $self->finalday(1) if $finalday;

    if ( $finalday || $self->finalday() ) {
	$self->do_log( $DEBUG{INFO},
	    "Recalculating global params...\n" );

	# Trafficwerte aus der DB laden
	$self->load_traffic_globals;
	# Vorhersagen laden
	$self->load_predictions;

	# letzter Tag im Monat -> neue Vorhersage erstellen
	# und letztes Mal Vorhersage korrigieren
	if ($days_left == 1) {
		$self->create_traffic_schedule();
	}

	# Zuweisen zu lokalen Variablen
	my $month_limit	    = $self->get('config' , 1, 'conf_mlimit');
	my $max_short	    = $self->get('internal', 'traffic', 'max_short');
	my $avg_short	    = $self->get('internal', 'traffic', 'avg_short');
	my $avg_long	    = $self->get('internal', 'traffic', 'avg_long');
	my $group_count	    = $self->get('internal', 'groups', 'count');
	my $diff_limit	    = $self->get('config', 1, 'conf_dgl');
	my $allowed_per_day = $month_limit / $days;
	# Waren wir in den letzten $AVG{short} (z.Z. 7) Tagen
	# ueber dem Tageslimit?
	my $overlimit	    = ($max_short > $allowed_per_day) ? 1 : 0;
	
	my $today	     = sprintf('%d-%02d-%02d',$year,$month,$day);
	my $yesterday	     = sprintf('%d-%02d-%02d',$yyear,$ymonth,$yday);
	my $t_real_yesterday = $self->get('t_stats',$yesterday,'traffic') || 0;
	my $t_pred_yesterday = $self->get('predict',$yesterday,'traffic');
	my $anstieg	     = ($avg_long > 0) ? $avg_short / $avg_long : 1;
	my $auslastung	     = ($t_pred_yesterday > 0) 
				    ? $t_real_yesterday/$t_pred_yesterday
				    : 1;
	$self->do_log( $DEBUG{DEBUG},
	    "t_Real: $t_real_yesterday, t_pred: $t_pred_yesterday " .
	    "ratio: $auslastung rise: $anstieg\n");

	if ($t_real_yesterday == 0) {
	    $self->do_log( $DEBUG{WARNING},
		"Keine Accountingwerte fuer den vergangenen Tag!\n");
	    # Wenn wir keine Trafficwerte haben,
	    # dann müssen wir mind. das geplante Volumen annehmen.
	    # Andere Werte würden zu grosse Fehlsteuerungen
	    # hervorrufen
	    $auslastung = 1;
	}

	# am ersten Tag letzten Monat abschliessen
	# und vorhersagewert zuweisen
	if ($day != 1) {

	    # Differenz zwischen realem und vorhergesagtem Traffic ermitteln
	    my $t_diff	     = $t_real_yesterday - $t_pred_yesterday;
	    # verteilung der Abweichung auf die verbleibenden Tage
	    # wenn es weniger als ein Zyklus ist, also weniger als eine Woche
	    my $d_diff	     = $days_left > 7 ? $t_diff / 7 : $t_diff / $days_left;
	    my $d_days	     = $days_left > 7 ? 7 : $days_left;
	    $self->do_log( $DEBUG{DEBUG},
		"Days left: $days_left, Limit: $month_limit \n");
	    $self->do_log( $DEBUG{DEBUG},
		"Trafficdiff: $t_diff, Diff days: $d_days, Diff per day: $d_diff \n");
#	$self->do_log( $DEBUG{DEBUG},
#	    "Max7: $max_short, Avg7: $avg_short, Avg14: $avg_long \n");

	    #Faktorgrenzen
	    # Es wird mind. ein Paket gesendet wenn BW < MTU wird das Paket
	    # trotzdem gesendet.  In HTB2 wurde diese Leihgabe wieder
	    # zurueckgezahlt.  Seit HTB3 nicht mehr. Also muessen wir pro Nase
	    # mind. 1 MTU/s erlauben d.h. der minimum faktor darf die BB nicht
	    # unter 12Kbit * Anzahl der Nutzer in Gruppe 10 bringen (Ini-BBs
	    # steigen schneller als Nutzer, deswegen reicht das)
	    # Eth MTU = 1500 Byte = 12kBit
	    # ABER default r2q = 10, also muessten es 120kBit sein, um ein
	    # Quantum gleich der MTU zu erhalten. Deswegen Quantum manuell
	    # festlegen
	    my $base_unit = 12000;

	    # Anzahl der Nutzer in der hoechsten (langsamsten) Gruppe
	    # Hinweis: dazu muss vorher das reclassify_users() gelaufen sein
	    my $users_max_group = $self->get('stats',$group_count,'nutzer');
	    $users_max_group = $users_max_group > 1 ? $users_max_group : 1;

	    # Initial-BB der hoechsten (langsamsten) Gruppe
	    my $bb_max_group    = $self->get('groups',$group_count,'conf_rate');

	    $self->do_log( $DEBUG{DEBUG},
		"#Nutzer Grp.$group_count: $users_max_group, " .
		"Ini-BB $group_count: $bb_max_group bps\n");

	    #$self->convert_without_unit(12,'kbit','bps');
	    my $min_factor= $base_unit * $users_max_group / $bb_max_group;
	    my $max_factor= $self->get('config', 1, 'conf_noshape') / 
			     $self->get('groups', $group_count, 'conf_rate');

	    $self->do_log( $DEBUG{DEBUG},
		"Min-Faktor: $min_factor, Max-Faktor: $max_factor\n");

	    #
	    # Korrektur der Vorhersagen
	    #

	    for (my $i = 0; $i < $days_left; $i++) {
		my $day_current = $day + $i;
		my $current_date = sprintf('%d-%02d-%02d',$year,$month,$day_current);
		my $traffic_pred_old = $self->get('predict',$current_date,'traffic');
		my $factor_pred_old = $self->get('predict',$current_date,'faktor');

		# Trafficvorhersage korrigieren
		my $traffic_pred_new = $i < $d_days 
					    ? $traffic_pred_old - $d_diff
					    : $traffic_pred_old;

		# Faktor anpassen
		my $factor_pred_new = $factor_pred_old;
		if ($auslastung > 1) {
		    my $malus = 1;
		    #sprintf('%d',($auslastung - 1)*10);
		    $malus = $auslastung > 1.1 ? 4 : 1;
		    $factor_pred_new = $factor_pred_new / ( $auslastung**$malus );
		}
		else {
		    $factor_pred_new = $factor_pred_new / $auslastung;
		    if (($anstieg > $diff_limit) && $overlimit ) {
			$factor_pred_new = $factor_pred_new / ($anstieg**4);
		    }
		}

		# Traffic runden (halbe bytes?)
		$traffic_pred_new = floor($traffic_pred_new);
		
		#Faktor begrenzen und runden
		if ( $factor_pred_new < $min_factor ) {
		    $factor_pred_new = $min_factor;
		}
		if ( $factor_pred_new > $max_factor ) {
		    $factor_pred_new = $max_factor;
		}

		my $factor_pred_final = 1;
		$factor_pred_final = sprintf("%.4f", $factor_pred_new);

		$self->do_log( $DEBUG{DEBUG},
		    "Update Prediction for: $current_date " .
		    "was: t=$traffic_pred_old f=$factor_pred_old " .
		    "now: t=$traffic_pred_new f=$factor_pred_final \n");

		$self->change('predict',$current_date,'traffic',$traffic_pred_new);
		$self->change('predict',$current_date,'faktor',$factor_pred_final);
	    }
	}


	# neuen Faktor auf jede Gruppe anwenden
	foreach my $group (sort {$a <=> $b} 
	    keys %{ $self->{ $DB_Tables{groups} }{entries} } ) {
	
	    # aktuellen Faktor holen
	    my $current_factor = $self->get('groups',$group,'conf_factor');
	
	    # neuen Faktor mit holen
	    my $new_factor = $self->get('predict',$today,'faktor');

	    $self->do_log( $DEBUG{DEBUG},
		"Gruppe $group: alter Faktor: $current_factor, " .
		"neuer Faktor: $new_factor\n");

	    $self->change('stats', $group, 'anstieg', sprintf("%.4f", $anstieg) );
	    $self->change('stats', $group, 'auslastung', sprintf("%.4f", $auslastung) );
	    $self->change('stats', $group, 'faktor', $new_factor);
	    $self->change('groups', $group, 'conf_factor', $new_factor);

	} # END foreach group


    } # ENDIF $finalday

}

sub create_traffic_schedule {
    my $self		= shift;
    my $old_tsum	= 0;
    my $shares		= 0;
    my ($year,$month,$day, $hour,$min,$sec) = Today_and_Now();
    my $days		= Days_in_Month($year,$month);

    # Beginn naechster Monat
    my ($nyear,$nmonth,$nday) = Add_Delta_Days($year,$month,1,$days);
    my $ndays		= Days_in_Month($nyear,$nmonth);

    $self->do_log( $DEBUG{INFO},
	    "Creating new traffic schedule for $nyear-$nmonth-$nday ".
	    "to $nyear-$nmonth-$ndays...\n" );

    # Ein Jahr zurueck (364 Tage)
    my ($yyear,$ymonth,$yday) = Add_Delta_Days($nyear,$nmonth,$nday,-364);

    # Ende des stat-monats (damit sind auch 29. Februare kein Problem)
    my ($eyear,$emonth,$eday) = Add_Delta_Days($yyear,$ymonth,$yday,$ndays-1);

    my $month_limit = $self->get('config' , 1, 'conf_mlimit');
    my $group_count = $self->get('internal', 'groups', 'count');
    my $max_factor  = $self->get('config', 1, 'conf_noshape') /
			     $self->get('groups', $group_count, 'conf_rate');

    my $sched = $self->load_traffic_stats("$yyear-$ymonth-$yday","$eyear-$emonth-$eday");
    my $avg_old_fak = $self->get_avg_bb("$yyear-$ymonth-$yday","$eyear-$emonth-$eday");

    #
    # Berechnung Vorhersage
    #

    # Daten sortiert fuer das Einfuegen des neuen Datums
    foreach my $j (sort {$a <=> $b} keys %$sched) {
	$sched->{$j}{date} = "$nyear-$nmonth-$j";

	# alte Trafficsumme fuer lineare Skalierung bestimmen
	$old_tsum += $sched->{$j}{traffic_old};

	# kompensierenden Faktor (Anteil) berechnen
	# muss bei geringerem Monatslimit vertauscht werden
	$sched->{$j}{comp_fac} = $avg_old_fak / $sched->{$j}{factor_old};

	# Gesamtsumme der komp. Faktoren
	$shares += $sched->{$j}{comp_fac};
    }

    # linearer Skalierungsfaktor
    my $lin_scal = $month_limit / $old_tsum;

    # Differenz aktuelles Limit minus alte Trafficsumme
    my $comp_diff = $month_limit - $old_tsum;

    # Traffic pro Anteil
    my $comp_share = $comp_diff / $shares;


    $self->do_log( $DEBUG{DEBUG},
		"Current Quota: $month_limit | Old Traffic Sum: $old_tsum | " .
		"Ratio: $lin_scal\n");
    $self->do_log( $DEBUG{DEBUG},
		"FreeTraffic: $comp_diff | Shares: $shares | " .
		"Traffic per Share: $comp_share | $avg_old_fak\n");

    my ($lsum,$csum,$hsum) = 0;
#    $self->do_log( $DEBUG{DEBUG},
#	    "Date;BB;Old;Linear;Compensation;Hybrid\n");

    # Hinweis: Das Ergebnis liegt immer paar Byte (<32) unter $month_limit,
    # da floor ja die Nachkommastellen abschneidet
    foreach my $j (sort {$a <=> $b} keys %$sched) {
	    my $date = $sched->{$j}{date};

	    # Lineare Skalierung
	    $sched->{$j}{traffic_lin} = floor(
					    $sched->{$j}{traffic_old} * $lin_scal);
	    $lsum += $sched->{$j}{traffic_lin};

	    # Skalierung durch Kompensation
	    $sched->{$j}{traffic_comp} = floor(
					    ($sched->{$j}{comp_fac} * $comp_share)
					    + $sched->{$j}{traffic_old});
	    $csum += $sched->{$j}{traffic_comp};

	    # Hybride Skalierung (Mittelwert aus
	    # den beiden zuvor ermittelten Werten)
	    $sched->{$j}{traffic_hybrid} = floor(
					    ($sched->{$j}{traffic_lin} 
					    + $sched->{$j}{traffic_comp})
					    /2
					    );
	    $hsum += $sched->{$j}{traffic_hybrid};

	    # Neuer Startfaktor
	    $sched->{$j}{factor_new} = $avg_old_fak > $max_factor
					    ? sprintf("%.4f", $max_factor)
					    : $avg_old_fak;

	    $self->do_log( $DEBUG{DEBUG},
		"$sched->{$j}{date};$sched->{$j}{factor_old};" .
		"$sched->{$j}{traffic_old};" .
		"$sched->{$j}{traffic_lin};" .
		"$sched->{$j}{traffic_comp};" .
		"$sched->{$j}{traffic_hybrid};" .
		"$sched->{$j}{factor_new}\n");

	    # Erzeugen der Datenstrukuren fuer Einfuegen in DB
	    $self->create('predict',$date);

	    # Modifizieren der neuen Eintraege mit den entspr.
	    # Werten
	    $self->change('predict',$date,'traffic',$sched->{$j}{traffic_hybrid});
	    $self->change('predict',$date,'faktor',$sched->{$j}{factor_new});

    }

    # geplante Trafficsumme je Skalierung
#    $self->do_log( $DEBUG{DEBUG},
#	    "Summe;;;$lsum;$csum;$hsum\n");

}

=head1 NAME

Dynshaper::Evaluator::Predictive - Globalregelung mit Vorausplanung

=head1 SYNOPSIS

    use Dynshaper::Evaluator

    my $shaper = new Dynshaper::Evaluator('Predictive');

    $shaper->reclassify();

    $shaper->commit();

=head1 DESCRIPTION

Plugin fuer die Regelung unter Verwendung von Vorausplanung
basierend auf statistischen Traffic- und Shapingdaten

Erzeugt am Ende eines Monats einen neuen Plan, der Zielverbraeuche vorgibt,
welche aus den Vorjahresdaten errechnet werden. Dabei handelt es sich um eine
grobe Abschaetzung des zu erwartenden Verbrauchs, die das zur Verfuegung
stehende Limit zu 99 Prozent ausnutzt. Falls es keine Erhoehung des Limit
innerhalb des vergangenen Jahres gab, stellt die Planung die maximal
zulaessigen Verbrauchswerte dar.

Die Regelung korrigiert an allen Tagen (ausser dem ersten des Monats) die
Planung in Abhaengigkeit vom tatsaechlichen Verbrauch. Die Trafficdifferenz
wird dazu gleichmaessig auf die naechsten 7 oder die verbleibenden Tage des
Monats (falls deren Anzahl geringer ist) aufgeteilt.

Der Bandbreitenfaktor wird entsprechend der Auslastung an allen verbleibenden
Tagen angepasst.

=head1 ARGUMENTS

=over

=item B<reclassify_global()>

wird von der Elternklasse Dynshaper::Evaluator aufgerufen, nachdem die
Neueinordnung der Nutzer vorgenommen wurde.

=item B<create_traffic_schedule()>

wird im Rahmen von B<reclassify_global()> aufgerufen, um am Ende eines Monats
eine neue Trafficplanung zu erstellen.

=head1 BUGS

da bei der Berechnung die Nachkommastellen einfach abgetrennt werden (keine
halben Bytes), hat die Planung einen maximalen Fehlbetrag von 31 Byte (0.x Byte
pro Tag * 31 Tage).

=head1 AUTHOR

Markus Schade <marks@invalid.email>

=cut


1;
