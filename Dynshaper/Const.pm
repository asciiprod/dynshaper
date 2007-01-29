package Dynshaper::Const;

use strict;
use Exporter;
use vars qw(
	@ISA
	@EXPORT
	%DB_Tables
	%DB_Table_Templates
	%PKeys
	%AVG
	%VOL_UNITS
	%BW_UNITS
	%UNITS
	%UNIT_NEXT
	%UNIT_PREV
	%UNIT_AMOUNT
	%DEBUG
	$DS_CONFIG
);

@ISA = qw(Exporter);

%DB_Tables = (
    'config'	=> 'ds_allgemein_v2',
    'groups'	=> 'ds_gruppen_v2',
    'excepts'	=> 'ds_ausnahmen_v2',
    'users'	=> 'ds_nutzergruppen_v2',
    'stats'	=> 'ds_statistik_v2',
    'predict'	=> 'ds_vorhersagen_current',
    'cn'	=> 'csn_nutzer',
    't_avg'	=> 'traffic_shaping_avg',
    't_stats'	=> 'trafficstatistik',
    't_art'	=> 'trafficart',
    'fw'	=> 'firewall_config',
    'internal'	=> '_internal',	    # internes Scratchpad, KEINE DB Tabelle!
);

%PKeys = (
    'config'	=> undef,
    'groups'	=> 'gruppe',
    'excepts'	=> 'ausnahme',
    'users'	=> 'person_id',
    'stats'	=> 'gruppe',
    'predict'	=> 'datum',
    'cn'	=> 'person_id',
    't_avg'	=> 'person_id',
    't_stats'	=> undef,
    't_art'	=> 'trafficart_id',
    'fw'	=> 'host_id',
    'internal'	=> undef,	    # internes Scratchpad, KEINE DB Tabelle!
);

%DB_Table_Templates = (
    'groups'	=> {
		'params' => {
			'conf_rate' => {
				'changed' => 1,
				'value' => '0'
			},
			'conf_in' => {
				'changed' => 1,
				'value' => 'on'
			},
			'conf_factor' => {
				'changed' => 1,
				'value' => '1'
			 },
			'conf_out' => {
				'changed' => 1,
				'value' => ''
			}
		},
		'changed' => 1
	    },
    'excepts'	=>  {
		'params' => {
			'conf_prio' => {
				'changed' => 1,
				'value' => '5'
			},
			'conf_rate' => {
				'changed' => 1,
				'value' => '0'
			},
			'conf_quantum' => {
				'changed' => 1,
				'value' => '1500'
			},
			'conf_bound' => {
				'changed' => 1,
				'value' => ''
			},
			'conf_in' => {
				'changed' => 1,
				'value' => []
			},
			'conf_out' => {
				'changed' => 1,
				'value' => []
			}
		},
		'changed' => 1
	    },
    'predict'	=> {
		'params' => {
			'traffic' => {
				'changed' => 1,
				'value' => 0
			},
			'faktor' => {
				'changed' => 1,
				'value' => 1
			}
		},
		'changed' => 1,
		'new' => 1
	    },
);

%AVG = (
	'long'	=> 14,
	'short'	=> 7,
);

%BW_UNITS = (
	'bps'	=> 'B',
	'kbit'	=> 'k',
	'mbit'	=> 'M',
);

%VOL_UNITS = (
	'b'	=> 'B',
	'kb'	=> 'k',
	'mb'	=> 'M',
	'gb'	=> 'G',	    # kennt tc nicht
	'tb'	=> 'T',	    # kennt tc nicht
);

%UNITS = ( %BW_UNITS, %VOL_UNITS );

%UNIT_AMOUNT = (
	'b'	=> 1,
	'bps'	=> 1,
	'kb'	=> 1024,
	'kbit'	=> 1000,
	'mb'	=> 1024**2,
	'mbit'	=> 1000**2,
	'gb'	=> 1024**3,
	'tb'	=> 1024**4
);

%DEBUG = (
    'NONE'	=> 0,
    'ERROR'	=> 1,
    'WARN'	=> 2,
    'NOTICE'	=> 3,
    'INFO'	=> 4,
    'DEBUG'	=> 5,
    'VERBOSE'	=> 6,
    'ALL'	=> 7,
);

$DS_CONFIG = '/var/CSN/dynshaper/dynshaper.conf';

@EXPORT = qw(
	%DB_Tables
	%DB_Table_Templates
	%PKeys
	%AVG
	%VOL_UNITS
	%BW_UNITS
	%UNITS
	%UNIT_NEXT
	%UNIT_PREV
	%UNIT_AMOUNT
	%DEBUG
	$DS_CONFIG
);


