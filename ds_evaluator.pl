#!/usr/bin/perl -I./
#######################################################################
#
# description:	Aufruf via Cron oder nach Abschluss des Accountings
#		zur Umsortierung der Nutzer und Neuberechnung der
#		Bandbreitenfaktoren
#
# author:	(c) 2005 Markus Schade <marks@invalid.email>
#
# version:	$Id: ds_evaluator.pl 6608 2006-05-08 08:42:12Z marks $
#
# license:	GPLv2
#
#######################################################################

use strict;
use Dynshaper::Evaluator;
use Data::Dumper;

my $obj = new Dynshaper::Evaluator('Basic');

$obj->set('config',1,'conf_log','./marks_shaper.log');
$obj->use_logfile(1);

$obj->devel(1); # Develmode aktivieren
$obj->debug(7); # Debuglevel (0 = NONE, 7 = ALL)

# Umordnung (stuendlich, und bei Bedarf auch globale Neuberechnung)
$obj->reclassify();

# Aenderungen in der Datenbank speichern
$obj->commit();

