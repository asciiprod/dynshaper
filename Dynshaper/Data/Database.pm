package Dynshaper::Data::Database;
#######################################################################
#
# description:	Methoden zum Initialisieren der Datenstrukturen aus
#		einer Datenbank
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
use Storable qw(store retrieve);
use CSN;
use Dynshaper::Const;
use base qw( Dynshaper::Units );

my $TRAFFIC_USER_MEM = "traffic-user-dump";

################## Global initialization ###################

sub DESTROY {
    my $self	= shift;
    my $dbh	= $self->{dbh};
    $dbh->disconnect() if $dbh;
}


sub load_config {
    my $self	= shift;
    my $dbh	= $self->{dbh} || db_connect('traffic_shaper');
    # Wenn wir ein neues DB-Handle erzeugt haben, wollen wir es auch erstmal
    # behalten (man weiss ja nie, wofuer man es noch gebrauchen kann)
    $self->{dbh} = $dbh; 

    # Debugging aus (per default)
    $self->{_DEBUG} = 0;
    $self->{_DEVEL} = 0;
    $self->{_USE_LOGFILE} = 0;
    # global Neuberechnung nur laut config-Paramtern
    $self->{_FINALDAY} = 0;
    # Trafficdaten der Nutzer aus der DB statt einem Dump-File holen
    $self->{_USE_TRAFFIC_DUMP} = 0;


    # globale Configdaten holen
    my $sql = qq(SELECT * from $DB_Tables{config});
    my $sth = db_call($dbh,$sql);

    while (my $r=$sth->fetchrow_hashref()) {
	$self->{ $DB_Tables{config} }{entries}{1}{params}{ $r->{parameter} }{value} = $r->{wert};
	$self->{ $DB_Tables{config} }{entries}{1}{params}{ $r->{parameter} }{changed} = 0;
	$self->{ $DB_Tables{config} }{entries}{1}{changed} = 0;
    }
    $self->{ $DB_Tables{config} }{changed} = 0;

    $sth->finish();


    # globale Gruppendaten holen
    $sql = qq(SELECT * from $DB_Tables{groups} ORDER BY $PKeys{groups});
    $sth = db_call($dbh,$sql);

    $self->{ $DB_Tables{groups} }{entries} = ();
    while (my $r=$sth->fetchrow_hashref()) {

	$self->{ $DB_Tables{groups} }{entries}{ $r->{gruppe} }{params}{ $r->{parameter} }{value} = $r->{wert};
	$self->{ $DB_Tables{groups} }{entries}{ $r->{gruppe} }{params}{ $r->{parameter} }{changed} = 0;
	$self->{ $DB_Tables{groups} }{entries}{ $r->{gruppe} }{changed} = 0;

    }
    $self->{ $DB_Tables{groups} }{changed} = 0;
    $self->{ $DB_Tables{groups} }{new} = 0;
    $self->{ $DB_Tables{groups} }{delete} = 0;

    $sth->finish();


    # Anzahl der Gruppen abspeichern
    my $groupcount = keys %{ $self->{ $DB_Tables{groups} }{entries} };
    $self->{ $DB_Tables{internal} }{entries}{groups}{count} = $groupcount;


    # globale Ausnahmen holen
    $sql = qq(SELECT * from $DB_Tables{excepts});
    $sth = db_call($dbh,$sql);

    $self->{ $DB_Tables{excepts} }{entries} = ();
    while (my $r=$sth->fetchrow_hashref()) {

	if ($r->{parameter} eq 'conf_in' || $r->{parameter} eq 'conf_out' ) {
	    push @{$self->{ $DB_Tables{excepts} }{entries}{ $r->{ausnahme}
		    }{params}{ $r->{parameter} }{value}}, 
		    split(/,/, $r->{wert});
	}
	else {
	    $self->{ $DB_Tables{excepts} }{entries}{ $r->{ausnahme} 
		    }{params}{ $r->{parameter} }{value} = $r->{wert};
	}
	$self->{ $DB_Tables{excepts} }{entries}{ $r->{ausnahme} }{params}{ $r->{parameter} }{changed} = 0;
	$self->{ $DB_Tables{excepts} }{entries}{ $r->{ausnahme} }{changed} = 0;

    }
    $self->{ $DB_Tables{excepts} }{changed} = 0;
    $self->{ $DB_Tables{excepts} }{new} = 0;
    $self->{ $DB_Tables{excepts} }{delete} = 0;

    $sth->finish();

    $self->{ $DB_Tables{internal} }{entries}{excepts}{count} = keys %{ $self->{ $DB_Tables{excepts} }{entries} };

    # Nutzerdaten und Gruppenzugehoerigkeit holen
    $sql = qq(SELECT cn.person_id as person_id, urz_login, gruppe
		FROM $DB_Tables{'cn'} cn 
		INNER JOIN $DB_Tables{'users'} dsn 
		ON cn.$PKeys{'cn'} = dsn.$PKeys{'users'});
    $sth = db_call($dbh,$sql);

    while (my $r = $sth->fetchrow_hashref()) {
	$self->{ $DB_Tables{users} }{entries}{ $r->{person_id} }{gruppe} = $r->{gruppe};
	$self->{ $DB_Tables{users} }{entries}{ $r->{person_id} }{urz_login} = $r->{urz_login};
	$self->{ $DB_Tables{users} }{entries}{ $r->{person_id} }{fwmark} = ();
	$self->{ $DB_Tables{users} }{entries}{ $r->{person_id} }{traffic} = 0;
	$self->{ $DB_Tables{users} }{entries}{ $r->{person_id} }{changed} = 0;
    }
    $self->{ $DB_Tables{users} }{changed} = 0;

    $sth->finish();


    ### uebrige Datenstrukturen initialisieren ###

    # Markierungen fuer die Firewall / tc filter holen
    $sql = qq{SELECT * FROM $DB_Tables{'fw'}
		WHERE $PKeys{'users'} IS NOT NULL
		AND manglemask IS NOT NULL};

    $sth = db_call($dbh,$sql);
    while (my $r = $sth->fetchrow_hashref()) {
	# fwmark aus person_id und Netzklassenbitmaske berechnen
	my $mark = int($r->{person_id}) | int($r->{manglemask});
	$self->append('users',$r->{person_id},'fwmark',$mark);
    }
    $sth->finish();

    # alte Statistikwerte
    $sql = qq(SELECT * FROM $DB_Tables{stats}
		ORDER BY datum DESC, gruppe
		LIMIT $groupcount);
    $sth = db_call($dbh,$sql);

    my $old_datum = undef;
    while (my $r = $sth->fetchrow_hashref() ) {
	    my $datum = $r->{datum};
	    my $old_datum = $datum unless defined $old_datum;

	    if ($old_datum ne $datum) {
		$self->do_log( $DEBUG{WARN}, 
		    "Statistiken von verschiedenen Tagen\n");
	    }

	    for my $statkey ("limit", "nutzer", "faktor", "anstieg", "auslastung") {
		$self->{ $DB_Tables{stats} }{entries}{ $r->{gruppe} }{params}{$statkey}{value} = $r->{$statkey};
		$self->{ $DB_Tables{stats} }{entries}{ $r->{gruppe} }{params}{$statkey}{changed} = 0;
	    }

	    $self->{ $DB_Tables{stats} }{entries}{ $r->{gruppe} }{changed} = 0;

    }
    $self->{ $DB_Tables{stats} }{changed} = 0;

    $sth->finish();

}


sub load_predictions {
    my $self	= shift;
    my $dbh	= $self->{dbh};

    $self->do_log($DEBUG{NOTICE},
	    "Fetching predictions from database.\n");

    my $sql = qq{SELECT datum, traffic, faktor
		FROM $DB_Tables{predict}
		WHERE 
		    datum BETWEEN 'yesterday'::date
		AND
		    (date_trunc('month',current_date)
		    + '1 month'::interval
		    - '1 day'::interval
		    )::date
		};

    my $sth = db_call($dbh,$sql);

    while ( my $r = $sth->fetchrow_hashref() ) {
	for my $predkey ('traffic', 'faktor') {
	    $self->{ $DB_Tables{predict} }{entries}{ $r->{datum} }{params}{$predkey}{value} = $r->{$predkey};
	    $self->{ $DB_Tables{predict} }{entries}{ $r->{datum} }{params}{$predkey}{changed} = 0;
	}
	$self->{ $DB_Tables{predict} }{entries}{ $r->{datum} }{changed} = 0;
    }
    $self->{ $DB_Tables{predict} }{changed} = 0;
    $self->{ $DB_Tables{predict} }{new} = 0;
    $self->{ $DB_Tables{predict} }{delete} = 0;

    $sth->finish();

    # Anzahl der Vorhersagen abspeichern
    my $predcount = keys %{ $self->{ $DB_Tables{predict} }{entries} };
    $self->{ $DB_Tables{internal} }{entries}{predict}{count} = $predcount;
};


sub load_traffic_users {
    my $self	= shift;
    my $dbh	= $self->{dbh};


    # Wenn wir im Devel-Mode sind und es ein Dump-File gibt, dann
    # soll dies geladen werden

    if (-s $TRAFFIC_USER_MEM && $self->use_traffic_dump) {
	$self->{$DB_Tables{users}} = retrieve $TRAFFIC_USER_MEM;
    } 
    else {

	# Ansonsten Traffic-Daten aus der Datenbank holen (dauert.. ca. 30s)

	$self->do_log($DEBUG{NOTICE},
		"Fetching traffic data from DB. This will take a while...\n");

	my $sql = qq(SELECT person_id, extdown as traffic 
		    FROM $DB_Tables{t_avg} 
		    WHERE person_id is not null);

	my $sth = db_call($dbh,$sql);

	while ( my $r = $sth->fetchrow_hashref() ) {
	    my $traffic = $self->get('users',$r->{person_id},'traffic');

	    $traffic += $r->{traffic} / $AVG{long};

	    $self->set('users',$r->{person_id},'traffic',$traffic);
	}

	$sth->finish();


# Trafficwerte fuer schnelleren Zugriff persistent im Dump-File speichern

	if ($self->devel) {
	    store $self->{$DB_Tables{users}}, $TRAFFIC_USER_MEM;
	}
    }

}


sub load_traffic_globals {
    my $self	= shift;

    $self->do_log($DEBUG{INFO}, 
	"Loading global traffic values...\n");

    $self->set( 'internal', 'traffic', 'max_short', 
	    $self->get_max_traffic( $AVG{short} )
    );
    $self->set( 'internal', 'traffic', 'avg_short', 
	$self->get_avg_traffic( $AVG{short} )
    );
    $self->set( 'internal', 'traffic', 'avg_long',
	$self->get_avg_traffic( $AVG{long} )
    );
    $self->load_daily_traffic( $AVG{long} );

}


sub get_max_traffic {
    my $self	= shift;
    my $days	= shift;
    my $dbh	= $self->{dbh};

    # hoechsten Wert der letzten $AVG{SHORT} (z.Z. 7) Tage holen
    my $sql = qq|SELECT traffic_down
		FROM $DB_Tables{t_stats}
		INNER JOIN $DB_Tables{t_art} USING ($PKeys{t_art})
		WHERE bezeichnung = 'extern'
		AND age(bis) < '$days days'::interval
		ORDER BY traffic_down DESC
		LIMIT 1
		|;

    my $sth = db_call( $dbh, $sql );

    my $max_traffic = $sth->fetchrow_array();

    $sth->finish();

    return $max_traffic;
}


sub get_avg_traffic {
    my $self	= shift;
    my $days	= shift;
    my $dbh	= $self->{dbh};

    # Durchschnittswert der letzten $days (z.Z. 7 und 14) Tage holen
    my $sql = qq|SELECT sum(traffic_down)/$days
		FROM $DB_Tables{t_stats}
		INNER JOIN $DB_Tables{t_art} USING ($PKeys{t_art})
		WHERE bezeichnung = 'extern'
		AND age(bis) < '$days days'::interval
		|;

    my $sth = db_call( $dbh, $sql );

    my $avg_traffic = $sth->fetchrow_array();

    $sth->finish();

    return $avg_traffic;
}


sub load_daily_traffic {
    my $self	= shift;
    my $days	= shift;
    my $dbh	= $self->{dbh};

    # Tageswerte der letzten $days holen
    my $sql = qq|SELECT date(von) as datum, traffic_down
		FROM $DB_Tables{t_stats}
		INNER JOIN $DB_Tables{t_art} USING ($PKeys{t_art})
		WHERE bezeichnung = 'extern'
		AND age(bis) < '$days days'::interval
		|;

    my $sth = db_call( $dbh, $sql );

    while ( my $r = $sth->fetchrow_hashref() ) {
	$self->{ $DB_Tables{t_stats} }{entries}{ $r->{datum} }{params}{traffic}{value} = $r->{traffic_down};
	$self->{ $DB_Tables{t_stats} }{entries}{ $r->{datum} }{params}{traffic}{changed} = 0;
	$self->{ $DB_Tables{t_stats} }{entries}{ $r->{datum} }{changed} = 0;
    }
    $self->{ $DB_Tables{t_stats} }{changed} = 0;

    $sth->finish();

}


sub load_traffic_stats {
    my $self	= shift;
    my $start	= shift;
    my $end	= shift;
    my $sql	= '';
    my $sched	= {};
    my $i	= 0;
    my $dbh	= $self->{dbh};

    $self->do_log( $DEBUG{DEBUG},
	    "LoadTrafSched: Will lookup stats from: $start to $end\n");

    $sql = qq|SELECT traffic_down as traffic_old, faktor as factor_old
	    FROM $DB_Tables{'t_stats'} ts
	    INNER JOIN $DB_Tables{t_art} USING ($PKeys{t_art})
	    INNER JOIN $DB_Tables{'stats'} ds
		ON ts.von=ds.datum
	    WHERE ds.gruppe=1
	    AND bezeichnung = 'extern'
	    AND ds.datum 
		BETWEEN '$start' 
		    AND '$end'
	    ORDER BY datum|;

    my $sth = db_call( $dbh, $sql );

    # Wichtig nach Datum sortiert, damit wir in derselben Reihenfolge
    # nachher auf die neuen Daten mappen koennen
    while ( my $r = $sth->fetchrow_hashref() ) {
	$i++;
	$sched->{$i}{traffic_old} = $r->{traffic_old};
	$sched->{$i}{factor_old} = $r->{factor_old};
    }

    $sth->finish();

    return $sched;
}


sub get_avg_bb {
    my $self	= shift;
    my $start	= shift;
    my $end	= shift;
    my $sql	= '';
    my $dbh	= $self->{dbh};
    my $avgbb	= 0;

    $sql = qq|SELECT trunc(avg(faktor)::numeric, 4) as factor
	    FROM $DB_Tables{'stats'} ds
	    WHERE ds.datum 
		BETWEEN '$start' and '$end'|;

    my $sth = db_call( $dbh, $sql );

    $avgbb = $sth->fetchrow_array();

    $sth->finish();

    return $avgbb;
}

###################  Zurueckschreiben der Aenderungen ###################

sub commit {
    my $self = shift;
    my $arg = shift || 'reload_after_commit';
    my $dbh = $self->{dbh};
    my @sql = ();

    $self->do_log($DEBUG{NOTICE},"Saving changes...\n");
    # Erzeuge ein UPDATE Statement fuer jeden geaenderten Schluessel
    # oder ein INSERT fuer neue Werte (statistik)

    for my $table ("config","groups","excepts") {
	if ($self->{ $DB_Tables{$table} }{changed}) {
	    my $db_entry_count = 0;
	    my $current_entry_count = 0;
	    $self->do_log($DEBUG{NOTICE},"Table $table changed\n");

	    if ($table eq 'groups' || $table eq 'excepts') {
		$db_entry_count = $self->get('internal',$table,'count');
		$current_entry_count = keys %{ $self->{ $DB_Tables{$table} }{entries} };
	    }

	    if ($self->{ $DB_Tables{$table} }{delete}) {
		my $deletes = $self->{ $DB_Tables{$table} }{delete};
		for (my $i = $db_entry_count; $i > $current_entry_count; $i--) {
			my $sqlstr = qq(DELETE FROM $DB_Tables{$table} WHERE );
			$sqlstr .= qq($PKeys{$table}=$i);
			push @sql, $sqlstr;
		}
	    }

	    foreach my $entry (keys %{ $self->{ $DB_Tables{$table} }{entries} } ) {
		if ($self->{ $DB_Tables{$table} }{entries}{$entry}{changed}) {

		    $self->do_log($DEBUG{INFO},
			"Entry $entry (Table: $table) changed\n");


		    foreach my $param (keys %{ $self->{ $DB_Tables{$table} }{entries}{$entry}{params} }) {
			if ($self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{changed}) {
				my $sqlstr = '';
				my $tval = '';
				if (ref($self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{value}) eq 'ARRAY' ) {
				    $tval = join(',', @{ $self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{value} });
				}
				else {
				    $tval = $self->{ $DB_Tables{$table} }{entries}{$entry}{params}{$param}{value};
				}
				my $value = $dbh->quote($tval, DBI::SQL_VARCHAR);

				$self->do_log( $DEBUG{DEBUG},
				    "Parameter $param (Entry: $entry, Table: $table) changed to $value\n");

				my $parameter = $dbh->quote($param, DBI::SQL_VARCHAR);

				# zusaetzliche AND Bedingung bei 2 Tabellen (groups,excepts) notwendig
				my $and = '';
				if ($PKeys{$table}) {
				    $and = qq(AND $PKeys{$table}=$entry);
				}

				if ($self->{ $DB_Tables{$table} }{new} and ($entry > $db_entry_count)) {
				    $sqlstr = qq(INSERT INTO $DB_Tables{$table} );
				    $sqlstr .=  qq{($PKeys{$table},parameter,wert) };
				    $sqlstr .=  qq{VALUES ($entry, $parameter, $value)};
				}
				else {
				    $sqlstr = qq(UPDATE $DB_Tables{$table} );
				    $sqlstr .=  qq(SET wert=$value );
				    $sqlstr .=  qq(WHERE parameter=$parameter $and);
				}
				push @sql, $sqlstr;
			}
		    }

		}
	    }

	}
    }

    # Users

    if ($self->{$DB_Tables{users}}{changed}) {

	$self->do_log($DEBUG{NOTICE},"User classifications changed\n");

	foreach my $person (keys %{ $self->{ $DB_Tables{users} }{entries} } ) {
	    if ($self->{ $DB_Tables{users} }{entries}{$person}{changed}) {

		my $logstr = "User $self->{$DB_Tables{users}}{entries}{$person}{urz_login} ".
		    "($person) changed - old_group: ".
		    "$self->{$DB_Tables{users}}{entries}{$person}{old_gruppe}, ".
		    "now $self->{$DB_Tables{users}}{entries}{$person}{gruppe}\n";

		$self->do_log($DEBUG{DEBUG}, $logstr);

		my $parameter = $dbh->quote($self->{$DB_Tables{users}}{entries}{$person}{gruppe},
		    DBI::SQL_VARCHAR);

		my $sqlstr = qq(UPDATE $DB_Tables{users} SET gruppe=$parameter,);
		$sqlstr   .= qq(seit='now' WHERE $PKeys{users}=$person);
		push @sql, $sqlstr;
	    }
	}
    }

    # Predictions

    if ($self->{$DB_Tables{predict}}{changed}) {
	my $db_entry_count = $self->get('internal','predict','count');
	my $current_entry_count = keys %{ $self->{ $DB_Tables{'predict'} }{entries} };

	$self->do_log($DEBUG{NOTICE},"Predictions changed\n");

	foreach my $date (keys %{ $self->{ $DB_Tables{predict} }{entries} } ) {
	    if ($self->{ $DB_Tables{predict} }{entries}{$date}{new}) {
		my $sqlstr = '';
		my $tval = 0;
		my $fval = 1;

		$self->do_log($DEBUG{INFO},
			"Commit: New prediction for $date\n");

		$tval = $self->{$DB_Tables{predict}}{entries}{$date}{params}{traffic}{value};
		$fval = $self->{$DB_Tables{predict}}{entries}{$date}{params}{faktor}{value};

		my $tqval = $dbh->quote($tval, DBI::SQL_VARCHAR);
		my $fqval = $dbh->quote($fval, DBI::SQL_VARCHAR);
		my $datum = $dbh->quote($date, DBI::SQL_VARCHAR);
		$sqlstr = qq|INSERT INTO $DB_Tables{predict} (datum,traffic,faktor) |;
		$sqlstr .= qq|VALUES ($datum,$tqval,$fqval)|;
		push @sql, $sqlstr;
	    }
	    elsif ($self->{ $DB_Tables{predict} }{entries}{$date}{changed}) {

		$self->do_log($DEBUG{INFO},
			"Predictions for $date changed\n");

		foreach my $param (keys %{ $self->{ $DB_Tables{predict} }{entries}{$date}{params} }) {
		    if ($self->{ $DB_Tables{predict} }{entries}{$date}{params}{$param}{changed}) {
			my $sqlstr = '';
			my $tval = 0;
			
			$tval = $self->{$DB_Tables{predict}}{entries}{$date}{params}{$param}{value};
			my $value = $dbh->quote($tval, DBI::SQL_VARCHAR);

			 $self->do_log($DEBUG{DEBUG}, 
			    "Prediction for $param on $date changed to $value\n");

			my $parameter = $dbh->quote($date, DBI::SQL_VARCHAR);

			$sqlstr = qq(UPDATE $DB_Tables{predict} SET $param=$value);
			$sqlstr .= qq( WHERE $PKeys{predict}=$parameter);
			push @sql, $sqlstr;
		    }
		}
	    }
	}
    }


    # Statistik

    if ( $self->{ $DB_Tables{stats} }{changed} && $self->finalday() ) {

	$self->do_log($DEBUG{NOTICE},"Statistics changed\n");

	# Die weitere Ueberpruefung nach Aenderungsflags spar ich mir,
	# weil immmer ein kompletter Datensatz neu eingefuegt wird

	foreach my $entry (keys %{ $self->{ $DB_Tables{stats} }{entries} } ) {
	    my $sqlstr = qq(INSERT INTO $DB_Tables{stats} );
	    $sqlstr .= qq|(gruppe,"limit",nutzer,faktor,anstieg,auslastung,datum) |;
	    $sqlstr .= qq|VALUES ($entry,|;
	    for my $param ("limit", "nutzer", "faktor", "anstieg", "auslastung") {
		my $parameter = $dbh->quote($self->{$DB_Tables{stats}}{entries}{$entry}{params}{$param}{value},
		    DBI::SQL_VARCHAR);
		$sqlstr .= qq($parameter,);
	    }
	    $sqlstr .= "'today')";
	    push @sql, $sqlstr;
	}
    }

    my $no_statements = scalar @sql;
    $self->do_log( $DEBUG{ALL}, "Ready to commit $no_statements Statement(s).\n");
    foreach my $statement (@sql) {
	    $self->do_log( $DEBUG{ALL}, "SQL2DB: $statement\n");
    }

    unless ($self->devel) {
	foreach my $statement (@sql) {
	    $dbh->do($statement) or $self->{error} .= $dbh->errstr;
	}

	($dbh->commit() or $self->{error} .= $dbh->errstr) unless $self->{error};
	$self->do_log( $DEBUG{ERROR}, "Commit Errors: $self->{error}\n") if $self->{error};
    } 
    else {
	$self->do_log( $DEBUG{DEBUG}, 
	    "DEVEL mode: _not_ committing changes to DB.\n");
    }

    if (@sql && !$self->{error} && $arg ne 'noreload' && !$self->devel) {
	$self->restart();
    }
    else {
	$self->do_log( $DEBUG{DEBUG}, 
	    "No reload after commit.\n");
    }
}

1;

=head1 NAME

Dynshaper::Database - initialisiert die Datenstrukturen aus der DB
und schreibt Aenderungen zurueck in die DB

=head1 SYNOPSIS

    use Dynshaper::Execute;

    my $ds = new Dynshaper::Execute;
    $ds->load_traffic_globals();

    my $avg14 = $ds->get('internal','traffic','avg_long');
    print "14 Tage Durchschnitt: $avg14\n";

    $ds->change('config',1,'conf_mlimit',5*(1024**4));
    $ds->commit('noreload');

=head1 DESCRIPTION

Das Database-Modul ist ein Sublayer der Data-Modulschicht, was das Lesen und Schreiben
der Daten von und zur Datenbank realisiert.

=head1 ARGUMENTS

=over 

=item B<load_config()>

Laedt aus der Datenbank die Werte aus den in B<$Dynshaper::Const::DB_Tables>
definierten Tabellen in die oben angegebene Datenstruktur innerhalb des
Objekts. Erfordert entweder ein vorhandenes Datenbankhandle in $obj->{dbh} oder
erzeugt automatisch selber eins falls keins vorhanden.

=item B<load_traffic_users()>

Laedt die Trafficwerte der Nutzer aus der Datenbank oder einem temporaeren File
(wenn B<< $self->use_traffic_dump >> gesetzt ist). Bei gesetztem B<<
$self->devel >> werden nach dem Lesen der Trafficdaten aus der Datenbank die
Daten in einem File zum schnelleren Zugriff waehrend der Entwicklung
zwischengespeichert.

=item B<load_traffic_globals()>

Laedt aus der Datenbank die Werte fuer den hoechsten Traffic der letzten
B<$Dynshaper::Const::AVG{short}> Tage und den Durchschnittstraffic der letzten
B<$Dynshaper::Const::AVG{short}> und B<$Dynshaper::Const::AVG{long}> Tage mittels
der Funktionen B<get_max_traffic()> und B<get_avg_traffic()>

=item B<get_max_traffic($days)>

Laedt den hoechsten Trafficwert der letzten B<$days> Tage aus der Datenbank.

=item B<get_avg_traffic($days)>

Laedt den Durchschnittswert des Traffics fuer die letzten B<$days> aus der
Datenbank.

=item B<commit($arg)>

Schreibt I<alle> geaenderten Wertzurueck in die Datenbank.  Loest automatisch
einen Neustart des Shapers aus, wenn a) sich etwas geaendert hat b) keine
Fehler beim Aktualisieren der DB aufgetreten sind und c) nicht 'noreload' als
B<$arg> uebergeben wurde.

=back

=head1 AUTHOR

Markus Schade <marks@invalid.email>

=cut


#########################################################################################
#
# CSN Special
#
#########################################################################################

sub get_Aufgabengebiet_IDs {
    my $self	= shift;
    my $job	= shift;
    my $dbh	= $self->{dbh};
    my $persons = {};

    my $sql = qq(SELECT cn.person_id
		FROM csn_nutzer cn
		INNER JOIN hat_aufgabe ha
		    ON cn.person_id=ha.person_id
		INNER JOIN aufgabengebiet ag
		    ON ha.aufg_id=ag.aufg_id
		WHERE aufgbez='$job');

    my $sth = db_call($dbh,$sql);

    while (my $r=$sth->fetchrow_hashref()) {
	$persons->{ $r->{person_id} } = $r->{person_id};
    }

    $sth->finish();

    return $persons;
}
