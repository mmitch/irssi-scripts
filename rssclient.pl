#
# this script is partially based in twirssi from http://twirssi.org
# and newsline.pl from http://scripts.irssi.org/html/newsline.pl.html
#

use strict;
use vars qw($VERSION %IRSSI);

use Irssi;

$VERSION = '0.1';
%IRSSI   = (
    authors     => 'Christian Garbs',
    contact     => 'mitch@cgarbs.de',
    name        => 'rssclient',
    description => 'Follow RSS feeds in a separate window.',
    license => 'GNU GPL v3 or later',
    url     => '*unreleased*',
    changed => '*unreleased*',
);

my %settings =
    (
     window   => 'rssfeeds',
     interval => 60,
    );

my $poll_event = 0;

sub getWin
{
    return Irssi::window_find_name( $settings{window} );
}

sub printError
{
    Irssi::active_win()->print($_) foreach @_;
}

sub printText
{
    my $win = getWin();
    if ($win)
    {
	$win->print($_) foreach @_;
    }
    else
    {
	printError(@_);
    }
}

sub callback
{
    printText("It is now ".`date`);
}

sub register_poll_event
{
    Irssi::timeout_remove($poll_event) if $poll_event;
    Irssi::timeout_add($settings{interval}*1000, \&callback, [1] );
}

if ( getWin() )
{
    register_poll_event();
    printText( "$IRSSI{name} initialized: poll interval = $settings{interval}s" );
}
else
{
    printError( "Create a window named `$settings{window}'.  Then, reload $IRSSI{name}." );
    printError( "Hint: /window new hide ; /window name $settings{window} ; /script load $IRSSI{name}" );
}
