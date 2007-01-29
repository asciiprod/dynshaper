package Dynshaper::Config::Web;
#######################################################################
#
# description:	Webbased Configuration Backend
#
# author:	(c) 2006 Markus Schade <marks@invalid.email>
#
# version:	$Id$
#
# license:	GPLv2
#
#######################################################################

use strict;
use CGI::Carp qw(fatalsToBrowser);
use Dynshaper::Const;
use GUI::TabWidget;
use GUI::Wizard;

use base qw(Dynshaper::Config);

sub add_tabs {
    my $self = shift;
    my $p = $self->{p};
    $self->{tw} = new GUI::TabWidget('page', '/intern/ds_manager.pl', $p->{q});
    $self->{tw}->addTab('Allgemein','general','general');
    $self->{tw}->addTab('Gruppen','groups','groups');
    $self->{tw}->addTab('Ausnahmen','excepts','excepts');
    $self->{tw}->setDefaultTab('general');
	
}

sub display {
    my $self	= shift;
    my $p	= $self->{p};
    my $cgi	= $p->{q};
    my $html	= '';
    
    $self->add_tabs();    
    my $tw	= $self->{tw};
    my $tab	= $tw->getTab();

    if ($tab->{link} eq 'excepts') {
	$html .= $self->display_excepts();
    }
    elsif ($tab->{link} eq 'groups') {
	$html .= $self->display_groups();
    }
    else {
	$html .= $self->display_common(); 
    }

    return $tw->to_html($html);
}

sub display_common {
    my $self	= shift;
    my $p	= $self->{p};
    my $html	= '';

    my $w = new GUI::Wizard('dsweb_allg', $p->{q});
    eval "require Application::Dynshaper::Allgemein" or croak $@;		    
    my $wp = new Application::Dynshaper::Allgemein;
    $w->addPage($wp);
    $w->{data}{ds} = $self;

    $html .= $w->run();
    return $html;
}

sub display_groups {
    my $self	= shift;
    my $p	= $self->{p};
    my $html	= '';

    eval "require Application::Dynshaper::Groups" or croak $@;		    
    my $grp = new Application::Dynshaper::Groups( p => $p, ds => $self );

    $html .= $grp->to_html();
    return $html;
}

sub display_excepts {
    my $self	= shift;
    my $p	= $self->{p};
    my $cgi	= $p->{q};
    my $html	= '';
					
    my $f = new GUI::formular;
    $f->addhelp(qq(<h1>Ausnahmen</h1>));

    my $s = new GUI::formularsection('Ausnahmen');
    
    $f->addsection($s);
    
    $html .= $f->to_html();
    return $html;
}

1;
