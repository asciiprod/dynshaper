#!/usr/bin/perl -I./

use strict;
use Dynshaper::Execute;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

sub usage {
    print <<END;
ds_execute - creating Dynshaper rules

Usage: $0 {start|stop|restart|list|status}
END
}

if (scalar(@ARGV) == 0) {
    usage();
    exit(1);
}
else {
    my $param = shift;

    if ( ($param eq 'start') or
	 ($param eq 'stop') or
	 ($param eq 'restart') or
	 ($param eq 'status') or
	 ($param eq 'list')
	) {
	my $ds = new Dynshaper::Execute;
	$ds->$param();
    }
    else {
	usage();
    }
}

