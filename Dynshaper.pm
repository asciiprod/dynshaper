package Dynshaper;
#######################################################################
#
# description:	Basisklasse
#
# author:	(c) 2005 Markus Schade <marks@invalid.email>
#
# version:	$Id: Dynshaper.pm 7026 2007-01-29 17:12:02Z marks $
#
# license:	GPLv2
#
#######################################################################

use strict;
use Carp;
use Dynshaper::Const;
use Storable qw(dclone);

################# Lesen/Setzen und Aendern der Datenstruktur #################

sub _check_existance {
    my $self = shift;
    my $table = shift || '';
    my $entry = shift;
    my $param = shift;


# Okay, das ist zum kotzen
# Perl ist so bescheuert, dass es die drueberliegenden
# Schluessel anlegt, wenn man einen tiefen schluessel auf
# Existenz testet. Das nennt sich autovivification
# Zitat aus dem exists-Manual:
# This surprising autovivification in what does not at first--or even
# second--glance appear to be an lvalue context may be fixed in a future
# release.
# Weil wir keine neuen Schluessel versehentlich angelegt haben wollen,
# muessen wir quasi jede Ebenen einzeln pruefen -> *wuerg*

    if (exists $DB_Tables{$table}) {

	# beim internen Scratchpad Autovivifikation erwuenscht
	if ($table eq 'internal' ||
	    (not defined $entry && not defined $param)
	    ) {
	    return 1;
	}

	if (exists $self->{ $DB_Tables{$table} }{entries}{$entry}) {

	    return 1 unless defined $param;
	    
	    if ($table eq 'users') {
		if (exists $self->{ $DB_Tables{$table} }{entries}{$entry}{$param}) {
		    return 1;
		}
	    } 
	    elsif (exists $self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}) {
		    return 1;
	    }
	}
    }

    return 0;
}


sub get {
    my $self	= shift;
    my $table	= shift;
    my $entry	= shift;
    my $param	= shift;


    if ( $self->_check_existance($table,$entry,$param) ) {
	if ( $table eq 'users' || $table eq 'internal' ) {
	    return $self->{ $DB_Tables{$table} }{entries}{$entry}{$param};
	}
	else {
	    return $self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{value};
	}
    }

    $self->do_log($DEBUG{ERROR}, "Failed to access non-existing data\n");
    return 0;
}


sub get_ptr {
    my $self	= shift;
    my $table	= shift;
    my $entry	= shift;
    my $param	= shift;


    if ( $self->_check_existance($table,$entry,$param) ) {
	#reference zurueckgeben
	if (defined $param) {
	    if ( $table eq 'users' || $table eq 'internal' ) {
		return $self->{ $DB_Tables{$table} }{entries}{$entry}{$param};
	    }
	    else {
		return $self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param};
	    }
	}
	elsif (defined $entry) {
	    if ( $table eq 'users' || $table eq 'internal' ) {
		return $self->{ $DB_Tables{$table} }{entries}{$entry};
	    } 
	    else {
		return $self->{ $DB_Tables{$table} }{entries}{$entry}{params};
	    }
	} else {
	    return $self->{ $DB_Tables{$table} }{entries};
	}
    }

    $self->do_log($DEBUG{ERROR}, "Failed to access non-existing data\n");
    return;
}

# set() im Gegensatz zu change() aktualisiert nicht die {change}-Schluessel
sub set {
    my $self	= shift;
    my $table	= shift;
    my $entry	= shift;
    my $param	= shift;
    my $value	= shift;

    for my $meth_par ($table, $entry, $param) {
        $self->do_log( $DEBUG{ERROR}, "Dynshaper->set Undefined access value!\n") 
	    unless defined $meth_par;
    }

    if ( $self->_check_existance($table,$entry,$param) ) {
	if ( $table eq 'users' || $table eq 'internal' ) {
	    $self->{ $DB_Tables{$table} }{entries}{$entry}{$param} = $value;
	    return 1;
	}
	else {
	    $self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{value} = $value;
	    return 1;
	}
    }

    $self->do_log($DEBUG{ERROR}, "Failed to update non-existing data\n");
    return 0
}

# append() im Gegensatz zu set() haengt den uebergebenen
# $value an den Schluessel an
sub append {
    my $self	= shift;
    my $table	= shift;
    my $entry	= shift;
    my $param	= shift;
    my $value	= shift;

    for my $meth_par ($table, $entry, $param) {
        $self->do_log( $DEBUG{ERROR}, "Dynshaper->set Undefined access value!\n") 
	    unless defined $meth_par;
    }

    if ( $self->_check_existance($table,$entry,$param) ) {
	if ( $table eq 'users' || $table eq 'internal' ) {
	    push(@{ $self->{ $DB_Tables{$table} }{entries}{$entry}{$param} }, $value);
	    return 1;
	}
	else {
	    push(@{ $self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{value} }, $value);
	    return 1;
	}
    }

    $self->do_log($DEBUG{ERROR}, "Failed to update non-existing data\n");
    return 0
}

sub change {
    my $self = shift;
    my $table = shift;
    my $entry = shift;
    my $param = shift;
    my $value = shift;

    my $has_changed = 0;

    for my $meth_par ($table, $entry, $param) {
        $self->do_log( $DEBUG{ERROR}, "Dynshaper->change Undefined access value!\n") 
	    unless defined $meth_par;
    }


    my $logval = ref($value) eq 'ARRAY' ? join(',', @$value) : $value;
    $self->do_log( $DEBUG{ALL}, 
	"Trying to change: $table, $entry, $param, [$logval]\n");

    # Wieder der exists mist
    if ( $self->_check_existance($table,$entry,$param) ) {
	if ($table eq 'internal') {
	    $self->set($table,$entry,$param,$value);
	    return 1; # keine Changeflags hier
	}
	elsif ($table eq 'users') {
	    unless ($self->{ $DB_Tables{$table} }{entries}{$entry}{$param} eq $value) {
		# alten Wert holen
		my $oldval = $self->{ $DB_Tables{$table} }{entries}{$entry}{$param};
		
		# alten Wert sichern
		$self->{ $DB_Tables{$table} }{entries}{$entry}{"old_$param"} = $oldval;
		
		# neuen Wert schreiben
		$self->{ $DB_Tables{$table} }{entries}{$entry}{$param} = $value;
		
		# lokales Changeflag setzen
		$has_changed = 1;
	    }
	} 
	else {
	    unless ($self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{value} eq $value) {
		$self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{value} = $value;

		# Das trifft auf die 'user' Tabelle nicht zu,
		# daher explizit den change->Schluessel setzen
		$self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{changed} = 1;
		$has_changed = 1;
	    }
	}


	if ($has_changed == 1) {

	    # hier koennen wir wieder generell (d.h. alle 4 Tabellen)
	    # die uebergeordneten Change-Schluessel setzen und danach
	    # zurueckkehren
	    $self->{ $DB_Tables{$table} }{entries}{$entry}{changed} = 1;
	    $self->{ $DB_Tables{$table} }{changed} = 1;
	}

	$self->do_log($DEBUG{VERBOSE}, 
	    "Change: ($has_changed): $table, $entry, $param, [$logval]\n");
	return 1;
    }
    else {
        $self->do_log($DEBUG{ERROR}, 
	    "Failed to change non-existing data\n");
	return 0;
    }
    
}

# Neue Eintraege werden hinter dem letzten/groessten Eintrag angelegt. Evtl.
# wird dadurch eine Loeschung aufgehoben
sub create {
    my $self = shift;
    my $table = shift;
    my $newkey = shift || '';

    $self->do_log( $DEBUG{ERROR}, "Dynshaper->create() table access value undefined!\n")
	unless defined $table;

    $self->do_log( $DEBUG{DEBUG}, "Dynshaper->create() explicit new key: $newkey\n") if $newkey;

    if ( $self->_check_existance($table) ) {
	my $deleted = $self->{ $DB_Tables{$table} }{delete};
	my $added = $self->{ $DB_Tables{$table} }{new};
	my $entries = keys %{$self->{ $DB_Tables{$table} }{entries}};
	my $newent = $newkey eq '' ? $entries + 1 : $newkey;
	# wenn schon was geloescht wurde, dann wird
	# dies durch das create wieder aufgehoben.
	# Andernfalls erhoehen wir die Anzahl neuer Eintraege
	if ($deleted > 0) {
	    $self->{ $DB_Tables{$table} }{delete}--;
	}
	else {
	    $self->{ $DB_Tables{$table} }{new}++;
	}

	# wir erzeugen einen neuen Eintrag anhand der Vorlage
	# aus Dynshaper::Const
	# zuvor ueberpruefen wir aber, ob nicht so ein Eintrag
	# schon existiert. Wenn doch, haben wir Luecken und sollte lieber
	# abbrechen
	if ( $self->_check_existance($table, $newent) ) {
	    $self->do_log($DEBUG{ERROR},
		"The entry about to be created already exists! " .
		"This should only happen if the entries are not in consecutive order. " .
		"In any case it is no longer safe to proceed.\n");
	}
	else {
	    $self->{ $DB_Tables{$table} }{entries}{ $newent } = dclone(
		$DB_Table_Templates{$table} );

	    $self->{ $DB_Tables{$table} }{changed} = 1;
	    $self->do_log( $DEBUG{ALL}, 
		    "Create new entry $newent in table $table\n");
	    return $newent;
	}
    }
    else {
	$self->do_log( $DEBUG{ERROR}, "Dynshaper->create() nonexistent table !\n");
    }
}

# beim Loeschen duerfen keine Loecher zurueckbleiben, d.h. wenn man bei 10
# Dingen das 5. loescht, muessen alle nachruecken, so dass effektiv der 10.
# Eintrag geloescht wird.  Sollte es Einfuegungen gegeben haben, muss diese
# Zahl dekrementiert werden, wodurch sie moeglicherweise beide aufheben und nur
# noch eine Aenderung vorliegt.
sub remove {
    my $self = shift;
    my $table = shift;
    my $entry = shift;

    for my $meth_par ($table, $entry) {
	$self->do_log( $DEBUG{ERROR}, "Dynshaper->delete() undefined access value!\n") 
	    unless defined $meth_par;
    }


    $self->do_log( $DEBUG{ALL}, 
	"Trying to delete: $table, $entry\n");

    # Wieder der exists mist
    if ( $self->_check_existance($table,$entry) ) {
	my $deleted = $self->{ $DB_Tables{$table} }{delete};
	my $added = $self->{ $DB_Tables{$table} }{new};
	my $entries = keys %{$self->{ $DB_Tables{$table} }{entries}};

	if ($added > 0) {
	    $self->{ $DB_Tables{$table} }{new}--;
	}
	else {
	    $self->{ $DB_Tables{$table} }{delete}++;
	}

	for (my $i=$entry; $i < $entries; $i++) {
	    $self->_copy_entry($table,$i+1,$i);
	}
	delete $self->{ $DB_Tables{$table} }{entries}{$entry};
	$self->{ $DB_Tables{$table} }{changed} = 1;
    }
    else {
        $self->do_log($DEBUG{ERROR}, 
	    "Failed to remove non-existing data\n");
	return 0;
    }
}

# beim Loeschen ruecken alle nachfolgenden nach.  Es wuerde zwar reichen, die
# Luecke in den Schluesseln zu schliessen, aber das wuerde beim commit() nicht
# die gewuenschten Aenderungen bewirken (UPDATE aller Eintraege > n). Also
# muessen die Werte kopiert werden (get + change), damit sich die Aenderungen
# wie gewuenscht auswirkt. Schliesslich besteht noch die Moeglichkeit, dass
# ueberhaupt nichts geloescht wird, weil nach dem Loeschen ein weiterer Eintrag
# angelegt wird.
sub _copy_entry {
    my $self = shift;
    my $table = shift;
    my $src = shift;
    my $dst = shift;

    for my $meth_par ($table, $src, $dst) {
	$self->do_log( $DEBUG{ERROR}, "Dynshaper->delete() undefined access value!\n") 
	    unless defined $meth_par;
    }


    $self->do_log( $DEBUG{ALL}, 
	"Trying to copy: $src -> $dst in Table $table\n");

    # Wieder der exists mist
    if ( $self->_check_existance($table,$src) &&
	 $self->_check_existance($table,$dst) ) {
	my $src_parms = $self->get_ptr($table,$src);
	my $dst_parms = $self->get_ptr($table,$dst);

	foreach my $param (keys %{$src_parms}) {
	    my $val = $self->get($table,$src,$param);
	    $self->change($table,$dst,$param,$val);
	}
    }
}

##########################  DEBUG Methoden  #####################


sub debug {
    my $self = shift;

    # get
    unless (@_ == 1 ) {
	if (ref($self)) {
	    return $self->{_DEBUG};
	} 
	else {
	    confess "You cannot use this as a class method!";
	}
    }

    # set
    my $level = shift;

    if (ref($self)) {
	$self->{_DEBUG} = $level; # Objekt debugging
    } 
    else {
	confess "object debugging only. You need an object here!";
    }
}


sub devel {
    my $self = shift;
    unless (@_ == 1) {
	if ($self->{_DEVEL} == 1) {
	    return 1;
	} 
	else {
	    return 0;
	}
    }
    $self->{_DEBUG} = 7;
    $self->{_DEVEL} = 1;
}


sub finalday {
    my $self = shift;
    unless (@_ == 1) {
	if ($self->{_FINALDAY} == 1) {
	    return 1;
	} 
	else {
	    return 0;
	}
    }
    $self->do_log($DEBUG{DEBUG}, "SETTING FINAL DAY MODE!\n");
    $self->{_FINALDAY} = 1;
}

sub use_traffic_dump {
    my $self = shift;
    unless (@_ == 1) {
	if ($self->{_USE_TRAFFIC_DUMP} == 1) {
	    return 1;
	} 
	else {
	    return 0;
	}
    }
    $self->{_USE_TRAFFIC_DUMP} = 1;
}

sub use_logfile {
    my $self = shift;

    #get
    unless (@_ == 1) {
	if ($self->{_USE_LOGFILE} == 1) {
	    return 1;
	} 
	else {
	    return 0;
	}
    }

    # set
    my $arg = shift;

    if (ref($self)) {
	$self->{_USE_LOGFILE} = $arg;
    } 
    else {
	confess "object only. You need an object here!";
    }
}


sub do_log {
    my $self = shift;
    my $level = shift;
    my $logmessage = shift;
    my $timestr = "[" . scalar localtime() . "] ";

    if ( $self->debug >= $level ) {
	if ( $self->use_logfile ) {
		my $logfile = $self->get('config','1','conf_log');
		open (MYFD, ">>$logfile") or
		    croak "Error opening logfile $logfile";
		print MYFD "$timestr$logmessage";
		close (MYFD);
	} 
	else {
	    if ( $level == $DEBUG{ERROR} ) {
		print STDERR $logmessage;
	    }
	    else {
		print STDOUT $logmessage;
	    }
	}
    }

    if ( $level == $DEBUG{ERROR} ) {
	confess "Dynshaper-Fehler: $logmessage";
    }

}

1;

=head1 NAME

Dynshaper - stellt gemeinsam benutzte Funktionalitaet bereit

=head1 SYNOPSIS

    # Skript fuer

    use Dynshaper::Evaluator;

    # neues Shaperobjekt erzeugen (erbt u.a von dieser Klasse)
    my $shaper = new Dynshaper::Evaluator('Basic');

    $shaper->devel(1);
    $shaper->debug(0);
    $shaper->use_traffic_dump(1);

    $shaper->change('config',1,'conf_adjust','off');
    $shaper->commit();

    # Skript was die Initialbandbreite der Gruppe 10
    # auf 100 KBit/s setzt und keinen automatischen
    # Neustart des Shapers ausloest.

    use Dynshaper::Config;

    my $shaper = new Dynshaper::Config;

    # Umrechnung von KBit/s in Bit/s
    my $bandwidth = $shaper->convert(100, 'kbit', 'bps');

    $shaper->change('groups', 10, 'conf_rate', $bandwidth);

    $shaper->commit('noreload');

=head1 DESCRIPTION

=head2 Einleitung

Sowohl fuer die Konfiguration (Webfrontend) als auch fuer die Arbeit des
Evaluators (Umordnung der Nutzer, globale Regelung) und des Executors
(Umsetzung der Berechnungen in tc-Regeln) sind immer wieder die
gleichen Daten erforderlich.

Die Kindklassen L<Dynshaper::Evaluator>, L<Dynshaper::Execute> und
L<Dynshaper::Config> erben von dieser Klasse die gewuenschte Funktionalitaet
und Daten. Bei der Erzeugung eines Objekts dieser Kindklassen wird die ererbte
B<db_init()>-Methode aufgerufen die aus der Datenbank die aktuellen Werte
laedt. Trafficdaten standardmaessig nicht geladen, um die Geschwindigkeit zu
verbessern. Diese werden automatisch beim Umordnen durch den Evaluator
nachgeladen, koennen jedoch auch explizit angefordert werden.

Die B<db_init()>-Methode (ererbt aus L<Dynshaper::Database>) erzeugt eine recht
umfrangreiche Datenstruktur, die einer Erklaerung bedarf.

Die obersten Schluessel sind entweder die Namen der Datenbanktabellen oder
interne Bezeichner (z.B. '_internal'). Darunter befinden sich weitere Ebenen um
einen datenbankartigen Zugriff zu ermoeglichen und gemachte Aenderungen durch
ein Skript zu protokollieren, damit beim Zurueckschreiben nur die
tatsaechlichen Aenderungen an die Datenbank uebergeben werden.

In der 2. Ebene sind die Schluessel die Eintraege, d.h. in der Regel werden hier
die Zeilen anhand ihrer Primaerschluessel abgelegt.
Die 3. Ebene beinhaltet entweder die Spalten oder die Sekundaerschluessel.

Darunter liegen dann endlich die eigentlichen Daten. Je nach Tabelle existieren
noch Zwischenstufen, welche die Informationen von den Verwaltungsdaten (z.B.
Aenderungsflags) trennen.

Zur besseren Verdeutlichung (und als Gedankenstuetze) ein Dump des Teils fuer
die Tabelle B<ds_gruppen_v2> und die Gruppe 10 mit ihren Parametern:

    'ds_gruppen_v2' => {
	'changed' => 0, # Tabelle geaendert?
	'entries' => {
		'10' => { # Gruppe 10
		       'params' => {
			     'conf_rate' => {
				      'changed' => 0, # Parameter geaendert
				      'value' => '2982912'
					    },
			     'conf_in' => {
				    'changed' => 0,
				    'value' => 'on'
					  },

				[ ... ]

			     'conf_factor' => {
					'changed' => 0,
					'value' => '0.1138'
					      },
			   },
		       'changed' => 0 # Eintrag (Gruppe) geaendert?
		     } 

Wie man sieht, gibt es fuer jede Ebene ein B<changed> Schluessel, der anzeigen
kann, ob dieser Wert bzw. unterhalb davon, geaendert wurde.

Im Gegensatz dazu faellt eine Stufe bei der internen Zwischenablage weg.

     '_internal' => {
		  'entries' => {
			     'traffic' => {
					'max_short' => '123123123',
					'avg_long' => '31231231',
					'avg_short' => '2132131'
					  },
			     'groups' => {
					   'count' => 10
					 }
			       }
		    }


=head2 Warum so eine Struktur?

Zum einen muessen eine Menge Daten schnell zugreifbar abgelegt werden, wobei im
Falle der Trafficwerte eher die Datenbank die Bremse ist.
Desweiteren erscheint es logisch, dass man fuer den Zugriff auf eine einzelne
Information in der Regel mindestens 3 Parameter notwendig sind:

	Name der DB-Tabelle, Primaerschluessel und Spaltenname

Also sind mindestens 3 Ebenen notwendig, um direkt eine Information zu
addressieren. Die zusaetzlichen Ebenen dienen zur Abgrenzung und Speicherung
besagter Aenderungsflags.

Weil fuer jede Stufe ein Vermerk existiert, ob der Schluessel geaendert wurde,
ist es uns nun auch moeglich 

=over

=item a) nur die tatsaechlichen Aenderungen zurueckzuschreiben 

=item b) mit nur 3 ineinandergeschachtelten foreach-Schleifen und wenig Code diese
Aenderungen zu extrahieren

=item c) ein "generisches" SQL-Statement zu formulieren

=back

=head2 Was heisst das?

Die Datenbanktabellen haben alle eine aehnliche Struktur. Aber man hat das
Problem, das jede Aenderungen an einem Wert oder mehreren Werten jeweils ein
B<UPDATE> erfordert.

Die Aenderung eines Wertes erfordert immer ein Statement in der Art:

	UPDATE ds_gruppen_v2 SET wert=1234 WHERE parameter='conf_rate' AND gruppe=10;
	UPDATE ds_nutzergruppen_v2 SET gruppe=10 WHERE person_id=3234;

In unserem Fall wuerde das generierte Statement dann so:

	UPDATE $table SET wert=$value WHERE parameter=$param AND $PKey{$table}=$entry;

oder so aussehen:

	UPDATE $table SET $param=$value WHERE $PKey{$table}=$entry;


Der findige Leser wird bemerkt haben, dass sich das eigentlich auf fast jeden
Fall anwenden laesst, wo man Daten aus mehreren Tabellen verarbeiten muss.
Aufgrund dieser Konstruktion der Datenstruktur koennen wir effizient Lesen,
Schreiben und nur die Aenderungen wieder an die Datenbank zurueckschreiben.

Eine Alternative waere mittels OO translucency eine Art copy-on-write zu
realisieren,  aber das haette erst recht niemand verstanden.

=head1 ARGUMENTS

=over

=item B<get($table,$entry,$param)>

Liefert den Wert des angebenen Paramters ($param, z.B. 'gruppe') eines Eintrags
($entry, z.B. 3234 = person_id des Nutzers) einer Tabelle ($table, z.B.
'users' fuer ds_nutzergruppen_v2). Beim Zugriff auf die Tabellen wird mit
symbolischen Bezeichnern gearbeitet, d.h. intern sind die Daten unter einem
Schluessel mit dem Namen der echten Datenbanktabelle abgelegt. Der $table
Parameter wird also auf $DB_Tables{$table} gemapped.

=item B<set($table,$entry,$param)>

Aendert den Wert ($value) eines Parameters ($param, z.B. 'conf_rate') eines
Eintrags ($entry, z.B. 10 fuer Gruppe 10) einer Tabelle ($table, z.B.
'groups').  Aktualisiert nicht die Aenderungsflags. Dafuer gedacht eine
initialisierte, aber leere Datenstruktur zu befuellen.

=item B<change($table,$entry,$param,$value)>

Aendert den Wert ($value) eines Parameters ($param, z.B. 'conf_rate') eines
Eintrags ($entry, z.B. 10 fuer Gruppe 10) einer Tabelle ($table, z.B. 'groups').
Als $table werden nicht die realen Schluesslnahmen verwendet, da sich
gegebenenfalls die Namen der Datenbanktabellen auch mal aendern.
Stattdessen werden symbolische Bezeichner uebergeben, die auf die realen
Schluesselnamen gemapped werden. Die Bezeichner und die dazugehoerigen Tabellen
sind in L<Dynshaper::Const> definiert.


=head1 BUGS

Finden und am besten gleich mit Patch an L<marks@invalid.email>
schicken.

=head1 AUTHOR

Markus Schade <marks@invalid.email>

=cut

