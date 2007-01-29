#!/usr/bin/perl -w
#######################################################################
#
# userconfig_create (C) 2001-2006 by Markus Schade
#
# license:	General Public License version 2
#
#######################################################################


use strict;
use DBI;
use CSN;

sub dsconfig();
sub replace_file($$);

my $DSCONF="/etc/dynshaper/dynshaper.conf";

# begin
#######################################################################

dsconfig();

# end
#######################################################################
# begin subroutines

sub dsconfig() {
	my $dbh = db_connect("traffic_shaper");
	my (%fwconf, %dsallg, %group_info, %excepts);
	my ($sql, $sth, $out);

	# Allgemeine Dynshaper Parameter holen
	$sql = qq{SELECT * from ds_allgemein_v2};
	$sth = db_call($dbh,$sql);
	while (my $r = $sth->fetchrow_hashref()) {
		$dsallg{$r->{parameter}} = $r->{wert};
	}
	$sth->finish;

	# Gruppenparameter holen
	$sql = qq{SELECT * from ds_gruppen_v2};
	$sth = db_call($dbh,$sql);
	while (my $r = $sth->fetchrow_hashref()) {
		$group_info{$r->{gruppe}}{$r->{parameter}} = $r->{wert};
	}
	$sth->finish;

	$sql = qq{SELECT * from ds_ausnahmen_v2};
	$sth = db_call($dbh,$sql);
	while (my $r = $sth->fetchrow_hashref()) {
		$excepts{$r->{ausnahme}}{$r->{parameter}} = $r->{wert};
	}
	$sth->finish;

	# IPs einer zu einer person_id holen (auch für die fw)
	$sql = qq{SELECT * FROM firewall_config
		    WHERE person_id IS NOT NULL
		    AND manglemask IS NOT NULL};

	$sth = db_call($dbh,$sql);
	while (my $r = $sth->fetchrow_hashref()) {
		# fwmark aus person_id und Netzklassenbitmaske berechnen
		my $mark = int($r->{person_id}) | int($r->{manglemask});
		# shaping gruppe der person_id
		$fwconf{$r->{person_id}}{gruppe} = $r->{gruppe};
		# fwmark per IP
		$fwconf{$r->{person_id}}{$r->{ip_adr}} = $mark;
		# fwmarks einer person_id
		push(@{$fwconf{$r->{person_id}}{mark}},$mark);
		# IP Adressen einer person_id
		push(@{$fwconf{$r->{person_id}}{ip}},$r->{ip_adr});
	};
	$sth->finish();
	$dbh->disconnect();


	#################### Shaper Config File generieren ################
	$out =	"#\n# !!! WARNING !!!\n" .
		"# This file is generated automatically by $0\n" .
		"# Modification is futile!\n#\n";

	$out .= "VERSION=\"Dynamic Traffic Shaper v0.70\"\n";
	$out .= "DEVINT=\"" . $dsallg{conf_devint} . "\"\n";
	$out .= "BWINT=\"" . format_bits($dsallg{conf_bwint}) . "\"\n";

	$out .= "DEVEXT=\"" . $dsallg{conf_devext} . "\"\n";
	$out .= "BWEXT=\"" . format_bits($dsallg{conf_bwext}) . "\"\n";


	$out .= "DYNSHAPER=\"" . $dsallg{conf_dspath} . "\"\n";
	$out .= "TC=\"" . $dsallg{conf_tcpath} . "\"\n";
	$out .= "MODPROBE=\"" . $dsallg{conf_mppath} . "\"\n";

	#Gruppenliste
	$out .= "UGROUPS=\""; 
	foreach my $group (sort {$a <=> $b} keys %group_info) 
	{
		$out .= "$group "
	}
	chop $out; $out .= "\"\n";


	foreach my $group (sort {$a <=> $b} keys %group_info) 
	{
		my $rate = $group_info{$group}{conf_rate} * $group_info{$group}{conf_factor};

		# BB jeder Gruppe
		$out .= "RATE[$group]=\"" . format_bits_fine($rate) ."\"\n";

		# FIXME: Minimum BB der beiden Interfaces zum Vergleich nutzen
		# Perl hat keinen Min/Max Operator
	
		# To shape or not to shape (incoming)
		if ($rate > $dsallg{conf_noshape} || $rate > $dsallg{conf_bwint} || !$group_info{$group}{conf_in}) 
		{
			$out .= "IN[$group]=\"\"\n";
		} else {
			$out .= "IN[$group]=\"on\"\n";	
		}

		# to shape or not to shape (outgoing)
		if ($rate > $dsallg{conf_noshape} || $rate > $dsallg{conf_bwext} || !$group_info{$group}{conf_out}) 
		{
		    $out .= "OUT[$group]=\"\"\n";
		} else {
		    $out .= "OUT[$group]=\"on\"\n";
		}

		# Pro Gruppe die FW-Marks schreiben
		$out .= "MARKS[$group]=\"";
		foreach my $uid (keys %fwconf) {
			if ($fwconf{$uid}{gruppe} == $group) {
				$out .= "$uid:";
				$out .= join (",", @{$fwconf{$uid}{mark}});
				$out .= ";";
			}
		}
		chop $out; $out .= "\"\n";
	}

	# und zum schluss die Ausnahmen
	$out .= "EXCEPTS=\""; 
	foreach my $case (sort {$a <=> $b} keys %excepts) {
		$out .= "$case "
	}
	chop $out; $out .= "\"\n";

	foreach my $case (sort {$a <=> $b} keys %excepts) {
		$out .= "ERATE[$case]=\"" . format_bits($excepts{$case}{conf_rate}) ."\"\n";
		$out .= "EPRIO[$case]=\"" . $excepts{$case}{conf_prio} ."\"\n";

		# Mehrere Matches stehen in der DB mit , getrennt
		# Der tc filter will aber ; haben
		$excepts{$case}{conf_in} =~ s/,/;/g;
		$out .= "EIN[$case]=\"" . $excepts{$case}{conf_in} ."\"\n";

		# Mehrere Matches stehen in der DB mit , getrennt
		# Der tc filter will aber ; haben
		$excepts{$case}{conf_out} =~ s/,/;/g;
		$out .= "EOUT[$case]=\"" . $excepts{$case}{conf_out} ."\"\n";
		$out .= "EBOUND[$case]=\"" . $excepts{$case}{conf_bound} ."\"\n";

	}

	replace_file($DSCONF, $out);
	# chown shaper.root $DSCONF
	#my ($login,$pass,$userid,$gid) = getpwnam('shaper')
	#	or die "User 'shaper' not in passwd file";
	#chown $userid, $gid, $DSCONF;

}

#
# Library functions
#

sub replace_file($$) {
	my $file = shift;
	my $data = shift;
	
	my $tmpl_file = "$file.tmpl";
	my $out_file  = "$file.new";
	open OUT, ">$out_file" or die "Cannot open $out_file for writing: $!";
	if (-f $tmpl_file) {
		open TMPL, "<$tmpl_file" or die "Cannot open $tmpl_file for reading: $!";
		while (<TMPL>) {
			/^#RULES#/ or print OUT and next;
			print OUT $data;
		}
		close TMPL;
	} else {
		print OUT $data;
	}
	close OUT;
	rename "$file.new", "$file" or die "Cannot rename $file.new to $file: $!";
}

