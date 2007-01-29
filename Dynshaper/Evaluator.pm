package Dynshaper::Evaluator;
#######################################################################
#
# description:	Klasse zur globale Neuberechnung und
#		Reklassifizierung der Nutzer
#
# author:	(c) 2005 Markus Schade <marks@invalid.email>
#
# version:	$Id: Evaluator.pm 6946 2006-12-02 07:04:57Z marks $
#
# license:	GPLv2
#
#######################################################################

use strict;
use CSN;
use DBI;
use Carp;
use Dynshaper::Const;
use base qw(Dynshaper::Execute);

sub new {
    my $class = shift;
    my $typ = shift;
    my $self = {};

    eval ("require Dynshaper::Evaluator::" . $typ) or croak $@;
    my $subclass = "Dynshaper::Evaluator::" . $typ;
    bless $self, $subclass;

    $self->load_data();
    
    return $self;
}

sub reclassify {
    my $self = shift;

    $self->do_log($DEBUG{NOTICE},"reclassify()\n");

    # Nutzer nach ihrem Traffic umordnen
    $self->reclassify_users();

    # globale Neuberechnung (muss von Subklasse ueberschrieben werden)
    $self->reclassify_global();
}

sub reclassify_users {
    my $self = shift;
    my $traffic_sum = 0;
    my $traffic_per_group;
    my $group_count = $self->get('internal','groups','count');
    my $user_count = 0;
    my $current_traffic = 0;
    my $group = $group_count;

    $self->do_log($DEBUG{INFO},"reclassifying users\n");

    # Trafficwerte laden
    $self->load_traffic_users();

    # Gesamttrafficmenge aller User ermitteln
    foreach my $user (keys %{ $self->{ $DB_Tables{users} }{entries} }) {
	    $traffic_sum += $self->get('users', $user, 'traffic');
    }

    $self->do_log($DEBUG{DEBUG}, "Trafficsumme: $traffic_sum\n");

    # Traffic pro Gruppe berechnen = Trafficsumme/Anzahl Gruppen
    # Div by Zero!
    $traffic_per_group = ($group_count > 0) 
			? $traffic_sum / $group_count
			: $traffic_sum;

    $self->do_log($DEBUG{DEBUG}, 
	"Traffic pro Gruppe: $traffic_per_group\n");

    # User nach Traffic in die Gruppen einsortieren
    my $logstr = '';
    foreach my $user (sort { 
			    $self->{ $DB_Tables{users} }{entries}{$b}{traffic} 
			    <=> 
			    $self->{ $DB_Tables{users} }{entries}{$a}{traffic}  
			    } 
		      keys %{ $self->{ $DB_Tables{users} }{entries} }) {

	    # Aktuelle Gruppe des Nutzers holen
	    my $old_group = $self->{ $DB_Tables{users} }{entries}{$user}{gruppe};

	    # CSN special
	    my $team_ids = $self->get_Aufgabengebiet_IDs('core-team');
	    if (exists $team_ids->{$user}) {
		unless ($old_group == 1) {
		    $self->do_log($DEBUG{DEBUG},
			"promoting user $user to group 1 and skipping\n");
		    $self->change('users',$user,'gruppe',1);
		}
		next;
	    }

	    # Wenn die aktuelle Gruppe nicht der momentan zu 
	    # befuellenden entspricht: neue Gruppe setzen
	    if ($group != $old_group) {
		$self->change('users',$user,'gruppe',$group);
	    }

	    # Trafficmenge des Nutzers zur aktuellen Trafficmenge
	    # der Gruppe addieren
	    my $user_amount = $self->get('users',$user,'traffic');
	    $current_traffic += $user_amount;

	    # Nutzerzahl dieser Gruppe incrementieren
	    $user_count++;

	    # Wenn aktuelle Trafficmenge der Gruppe die berechnete Menge pro
	    # Gruppe ubersteigt,
	    if ($current_traffic >= $traffic_per_group) {

		$self->change('stats', $group, 'limit', int($user_amount) );
		$self->change('stats', $group, 'nutzer', $user_count);
		
		# Auslastungsstats abspeichern
		#
		# erstmal auf 0, weil eigentlich so nicht
		# direkt berechenbar (Man muesste sich merken, in welcher Gruppe
		# jeder Nutzer zwischen den reclassify()-Laeufen war, weil sich
		# das ja jede Stunde aendern kann, und wievel Traffic er waehrend
		# dieser Zeit verbraucht hat. Also sowas wie:
		# 4h in Gruppe 10 mit 150MB, 3h in Gruppe 9 mit 200MB, dann wieder
		# 6h in Gruppe 10 mit 123MB, usw.
		# Ergo: Nicht wie gewuenscht ohne weiteres machbar)
		$self->change('stats', $group, 'auslastung', 0);

		$logstr .= "Gruppe $group: $user_count, ";

		# zur naechsten (hoeheren, in bezug auf Bandbreite) Gruppe
		# weiterschalten.  Ausser wir sind schon in Gruppe 1
		$group-- if $group > 1;
		$current_traffic = 0; $user_count = 0;
	    }
    }
    $logstr .= "\n";
    $self->do_log($DEBUG{INFO},$logstr);

    if ($user_count > 0) {
	$self->change('stats', 1, 'limit', 0);

	# Hier eher quatsch, weil alle abwesenden oder verzogenen Nutzer
	# mitgezaehlt werden.
	$self->change('stats', 1, 'nutzer', $user_count);
	$self->change('stats', 1, 'auslastung', 0);
    }
}

sub reclassify_global {
    my $self = shift;
    croak "Method reclassify_global() not implemented by class " . ref($self) ."!";
}


1;

=head1 NAME

Dynshaper::Evaluator - Auswertung und Umsortierung der Nutzer und 
Anpassung des globalen Faktors

=head1 SYNOPSIS

  use Dynshaper::Evaluator;

Neues Object erzeugen mit der gewuenschten Strategie als 
Parameter (In diesm Fall 'Basic')

  my $shaper = new Dynshaper::Evaluator('Basic');

Methoden aufrufen

  $shaper->reclassify();
  $shaper->global_reclassify(); 
  $shaper->commit();

Die Methode B<global_reclassify()> sollte im Normalfall nicht direkt aufgerufen
werden.  Sie wird automatisch zu dem in der Datenbank konfigurierten Zeitpunkt
mit aufgerufen.  Ein manueller Aufruf sollte also nur gemacht werden, wenn der
Automatismus nicht funktioniert hat.

=over 4

=item B<reclassify()>

Implementiert die Umsortierung der Nutzer nach ihrer angefallenen
Trafficmenge. Sie ruft (taeglich) automatisch die B<global_reclassify()>
Methode auf, um den globalen Shapingfaktor neu zu berechnen.

=item B<global_reclassify()>

berechnet den globalen Shapingfaktor neu. Wie das passiert haengt von der
gewaehlten Strategie ab. Zum jetzigen Zeitpunkt kann die Strategie direkt
bei der Erzeugung des Shaperobjekts angegeben werden.  Denkbar ist jedoch,
das dies automatisch anhand eines Paramters in der Datenbank ausgewuerfelt
wird.

=item B<commit()>

Schreibt die gemachten Aenderungen zurueck in die Datenbank.

=back

=head1 BUGS

Wer welche findet, bitte bescheid sagen, oder, wenn offensichtlich, beheben.

=head1 SEE ALSO

L<Dynshaper>, L<Dynshaper::Config>

=cut

