#
# this script is partially based on twirssi from http://twirssi.org
# and rssbot.pl http://oreilly.com/catalog/irchks/chapter/hack66.pdf
#

use strict;
use vars qw($VERSION %IRSSI);

use Irssi;
use LWP::UserAgent;
use XML::RSS;

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
     rss_url  => 'http://www.slashdot.org/slashdot.rss'
    );

my $poll_event = 0;

my @items_seen = ();

# Fetches the RSS from server and returns a list of RSS items.
sub fetch_rss
{
    my $rss_url = shift;

    my $ua = LWP::UserAgent->new (env_proxy => 1, keep_alive => 1, timeout => 30);
    my $request = HTTP::Request->new('GET', $rss_url);
    my $response = $ua->request ($request);
    return unless ($response->is_success);
    my $data = $response->content;
    my $rss = new XML::RSS ();
    $rss->parse($data);
    foreach my $item (@{$rss->{items}}) {
	# Make sure to strip any possible newlines and similiar stuff.
	$item->{title} =~ s/\s/ /g;
    }
    return @{$rss->{items}};
}

# Attempts to find some newly appeared RSS items.
sub delta_rss
{
    my ($old, $new) = @_;
    # If @$old is empty, it means this is the first run and we will therefore not do anything.
    return () unless ($old and @$old);
    # We take the first item of @$old and find it in @$new. Then anything before its position in @$new are the newly appeared items which we return.
    my $sync = $old->[0];

    # If it is at the start of @$new, nothing has changed.
    return () if ($sync->{title} eq $new->[0]->{title});
    my $item;
    for ($item = 1; $item < @$new; $item++) {
	# We are comparing the titles which might not be 100% reliable but RSS
	# streams really should not contain multiple items with same title.
	last if ($sync->{title} eq $new->[$item]->{title});
    }
    return @$new[0 .. $item - 1];
}

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
    my (@new_items);
    print "Checking RSS feed [".$settings{rss_url}."]...\n";
    @new_items = fetch_rss( $settings{rss_url} );
    if (@new_items)
    {
	my @delta = delta_rss (\@items_seen, \@new_items);
	foreach my $item (reverse @delta)
	{
	    printText('"'.$item->{title}.'" :: '.$item->{link});
	}
	@items_seen = @new_items;
    }
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
    callback();
}
else
{
    printError( "Create a window named `$settings{window}'.  Then, reload $IRSSI{name}." );
    printError( "Hint: /window new hide ; /window name $settings{window} ; /script load $IRSSI{name}" );
}
