package Dynshaper::Execute;
#######################################################################
#
# description:	setzt die Dynshaper-Parameter in tc-Befehle um
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
use Dynshaper::Const;
use base qw(Dynshaper::Data);

$ENV{PATH} = '/sbin:/bin';

sub new {
    my ($class, %args)	= @_;

    my $self = bless {}, $class;
    
    $self->load_data();

    return $self;
}

sub restart {
    my $self	= shift;
    $self->start();
}


sub start {
    my $self	= shift;
    my $c	= {};
    my $uclass	= 400; #Nutzerklassen beginnen bei 400
    my $cmd	= '';
    my $log	= '';
    my $log2	= '';
    
    if ($self->get('config',1,'conf_adjust')) {
	$self->prepare_config_for_exec()
    }

    for my $option ('mppath','tcpath','devint','devext',
		    'bwext','bwint') {
	$c->{$option} = $self->get('config',1,"conf_$option");
    }

    $self->do_log( $DEBUG{NOTICE}, qq(Starting Dynshaper HTB: ));

    # Laden der benoetigten Module

    $log = qq(mod);
    for my $module ("sch_htb", "cls_u32", "cls_fw") {
	$log2 = qx($c->{mppath} $module 2>&1);
	$self->do_log( $DEBUG{ERROR}, $log2) if $log2;
    }
    $self->do_log( $DEBUG{NOTICE}, qq($log.));

    # jetzt fuer alle Interfaces regeln anlegen

    for my $device ( $c->{devint}, $c->{devext} ) {
	my $bandwidth=0;
	my $exs = $self->get_ptr('excepts');
	my $grps = $self->get_ptr('groups');

	$log = qq( if:$device);
	
	if ($device eq $c->{devint}) {
	    $bandwidth=$c->{bwint};
	}
	else {
	    $bandwidth=$c->{bwext};
	}
	
	# Alle Regeln und Klassen loeschen
	$log2 = qx($c->{tcpath} qdisc del dev $device root 2>&1);

	# Neue Root qdisc mit HTB anlegen
	# default Klasse fuer nicht eingeordneten Traffic 1:30
	# Bandbreite wird mit dem Faktor 10 in Quanten umgerechnet
	$cmd	 = qq($c->{tcpath} qdisc add dev $device root handle 1:);
	$cmd	.= qq( htb default 30 r2q 10);
	$log2	.= qx($cmd 2>&1);

	# Wurzelklasse erzeugen
	$cmd	 = qq($c->{tcpath} class add dev $device parent 1:);
	$cmd	.= qq( classid 1:1 htb rate $bandwidth);
	$log2	.= qx($cmd 2>&1);

	# Linker Zweig (Ausnahmen)
	$cmd	 = qq($c->{tcpath} class add dev $device parent 1:1);
	$cmd	.= qq( classid 1:2 htb rate $bandwidth);
	$log2	.= qx($cmd 2>&1);

	# Rechter Zweig (Nutzerklassen)
	$cmd	 = qq($c->{tcpath} class add dev $device parent 1:1);
	$cmd	.= qq( classid 1:3 htb rate $bandwidth);
	$log2	.= qx($cmd 2>&1);

	# Defaultklasse (minimale Rate 12kbit/s, nach oben nur durch
	# Interface-BB begrenzt) erbt die gesamte freie Bandreite
	$cmd	 = qq($c->{tcpath} class add dev $device parent 1:3);
	$cmd	.= qq( classid 1:30 htb rate 12kbit ceil $bandwidth prio 5);
	$cmd	.= qq( quantum 1500);
	$log2	.= qx($cmd 2>&1);

	$self->do_log( $DEBUG{ERROR}, $log2) if $log2;
	$self->do_log( $DEBUG{NOTICE}, $log);
	#
	# Ausnahmen
	#
	$log2 = '';
	$log = qq( ex:);
	foreach my $except (keys %{$exs}) {
	    $log .= qq($except );

	    my $ex_in	 = $self->get('excepts',$except,'conf_in');
	    my $ex_out	 = $self->get('excepts',$except,'conf_out');
	    my $ex_bound = $self->get('excepts',$except,'conf_bound');
	    my $ex_rate	 = $self->get('excepts',$except,'conf_rate');
	    my $ex_prio	 = $self->get('excepts',$except,'conf_prio');

	    if (( $device eq $c->{devint} && $ex_in ) || 
		( $device eq $c->{devext} && $ex_out)) {
		my $bounded = '';
		$bounded = $ex_bound ? "ceil $ex_rate" : "ceil $bandwidth";

		$cmd	 = qq($c->{tcpath} class add dev $device parent 1:2 );
		$cmd	.= qq( classid 1:2$except htb rate $ex_rate prio $ex_prio $bounded);
		$log2	.= qx($cmd 2>&1);

		if ( $device eq $c->{devint} ) {
		    for my $match (@$ex_in) {
			$cmd   = qq($c->{tcpath} filter add dev $device parent 1:0 );
			$cmd  .= qq(protocol ip prio $ex_prio u32 $match flowid 1:2$except);
			$log2 .= qx($cmd 2>&1);
		    }
		}
		else {
		    for my $match (@$ex_out) {
			$cmd   = qq($c->{tcpath} filter add dev $device parent 1:0 );
			$cmd  .= qq(protocol ip prio $ex_prio u32 $match flowid 1:2$except);
			$log2 .= qx($cmd 2>&1);
		    }
		}
	    }

	    $self->do_log( $DEBUG{ERROR}, $log2) if $log2;
	} # foreach my $except
	$log .= qq(.);
	$self->do_log( $DEBUG{NOTICE}, $log);
	#
	# Nutzerklassen
	#
	$log2 = '';
	$log = qq( grps:);
	foreach my $group (sort {$a <=> $b} keys %{$grps}) {
	    $log .= qq($group );
	    my $grp_in   = $self->get('groups',$group,'conf_in');
	    my $grp_out  = $self->get('groups',$group,'conf_out');
	    my $grp_rate = $self->get('groups',$group,'conf_rate');

	    if (( ($device eq $c->{devint}) && $grp_in ) ||
		( ($device eq $c->{devext}) && $grp_out)) {
		    $cmd  = qq($c->{tcpath} class add dev $device parent 1:3 );
		    $cmd .= qq(classid 1:3$group htb rate $grp_rate ceil $grp_rate);
		    $log2 = qx($cmd 2>&1);

		my $nutzer = $self->get_ptr('users');
		foreach my $user (keys %{$nutzer}) {
		    my $user_group = $self->get('users',$user,'gruppe');
		    if ($group == $user_group) {
			my $umarks = $self->get_ptr('users',$user,'fwmark');
			# Nutzer ueberspringen, wenn keine fwmarks existieren
			# d.h. in der Regel, dass der Nutzer gesperrt ist
			# Kommt nur bei DB-gestutzter Ausfuehrung vor, weil hier
			# alle Nutzer initialisiert werden, egal ob effektiv
			# freigeschaltet oder nicht
			next unless defined $umarks;

			$cmd   = qq($c->{tcpath} class add dev $device parent 1:3$group);
			$cmd  .= qq( classid 1:$uclass htb rate 12kbit ceil $grp_rate prio 7);
			$cmd  .= qq( quantum 1500);
			$log2 .= qx($cmd 2>&1);
			
			my $oldmark = 0;
			foreach my $usermark (@{$umarks}) {
			    next if $usermark == $oldmark;
			    $cmd   = qq($c->{tcpath} filter add dev $device parent 1:0);
			    $cmd  .= qq( protocol ip prio 100 handle $usermark fw );
			    $cmd  .= qq( flowid 1:$uclass);
			    $log2 .= qx($cmd 2>&1);
			
			    $oldmark=$usermark;
			}
			$uclass++;
		    }
		} #foreach my $user
		
		$self->do_log( $DEBUG{ERROR}, $log2) if $log2;

	    } #endif
	    
	} #foreach my $group 

	$log .= qq(.);
	$self->do_log( $DEBUG{NOTICE}, $log);
	
    } # for my $device

    $self->do_log( $DEBUG{NOTICE}, "\n");

}


sub stop {
    my $self	= shift;
    my $c = {};
    my $log = '';

    for my $option ('tcpath','devint','devext') {
	$c->{$option} = $self->get('config',1,"conf_$option");
    }
    
    $self->do_log( $DEBUG{NOTICE}, qq(Stopping Dynshaper HTB: ));
    for my $device ( $c->{devint}, $c->{devext} ) {
	$log = qx($c->{tcpath} qdisc del dev $device root 2>&1);
	$self->do_log( $DEBUG{DEBUG}, $log) if $log;
    }
    
    $self->do_log( $DEBUG{NOTICE}, qq(done.\n) );
}


sub list {
    my $self	= shift;
    my $c	= {};
    my $log	= '';

    for my $option ('tcpath','devint','devext') {
	$c->{$option} = $self->get('config',1,"conf_$option");
    }
    for my $device ( $c->{devint}, $c->{devext} ) {
	 $log .= qx($c->{tcpath} qdisc ls dev $device 2>&1);
	 $log .= qx($c->{tcpath} class ls dev $device 2>&1);
	 $log .= qx($c->{tcpath} filter ls dev $device 2>&1);
    }
    $self->do_log( $DEBUG{DEBUG}, $log);
}


sub status {
    my $self= shift;
    my $c   = {};
    my $log = '';
    
    for my $option ('tcpath','devint','devext') {
	$c->{$option} = $self->get('config',1,"conf_$option");
    }
    for my $device ( $c->{devint}, $c->{devext} ) {
	$log .= qx($c->{tcpath} -s qdisc ls dev $device 2>&1);
	$log .= qx($c->{tcpath} -s class ls dev $device 2>&1);
	$log .= qx($c->{tcpath} filter ls dev $device 2>&1);
    }
    $self->do_log( $DEBUG{DEBUG}, $log);
}

1;
