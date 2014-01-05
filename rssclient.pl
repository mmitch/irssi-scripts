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
     window   => 'rssfeeds', # the irssi window name
     interval => 12,         # check individual feed intervals every n minutes
    );

my @feedlist =
    (
     # for testing (there is some volume here)
     { # for testing
	 name     => '/.',
	 url      => 'http://www.slashdot.org/slashdot.rss',
	 interval => 31
     },
     # only locally retrievable, you won't get this
     {
	 name     => 'psy',
	 url      => 'http://www.mitch.h.shuttle.de/kosmosblog.xml',
	 interval => 44
     },
     # my stuff
     {
	 name     => 'cgarbs.de',
	 url      => 'http://www.cgarbs.de/rssfeed.en.xml',
	 interval => 61
     },
     {
	 name     => 'mitchblog.comments',
	 url      => 'http://www.cgarbs.de/blog/feeds/comments.rss2',
	 interval => 33
     },
     {
	 name     => 'mitchblog',
	 url      => 'http://www.cgarbs.de/blog/feeds/index.rss2',
	 interval => 29
     },
    );

my $poll_event = 0;

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

sub get_win
{
    return Irssi::window_find_name( $settings{window} );
}

sub print_error
{
    Irssi::active_win()->print($_) foreach @_;
}

sub print_text
{
    my $win = get_win();
    if ($win)
    {
	$win->print($_) foreach @_;
    }
    else
    {
	print_error(@_);
    }
}

sub poll_feed
{
    my $feed = shift;

    # individual poll time reached?
    my $lastpoll = exists $feed->{lastpoll} ? $feed->{lastpoll} : 0;
    my $now = time();
    if ($now - $lastpoll > $feed->{interval} * 60)
    {
	print "Checking RSS feed [".$feed->{url}."]...";
	my @new_items = fetch_rss( $feed->{url} );
	if (@new_items)
	{
	    my @old_items = exists $feed->{items} ? @{$feed->{items}} : ();
	    my @delta = delta_rss (\@old_items, \@new_items);
	    foreach my $item (reverse @delta)
	    {
		print_text('"'.$item->{title}.'" :: '.$item->{link});
	    }
	    $feed->{items} = @new_items;
	    $feed->{lastpoll} = $now;
	}
    }
}

sub callback
{
    foreach my $feed (@feedlist)
    {
	poll_feed($feed);
    }
}

sub register_poll_event
{
    Irssi::timeout_remove($poll_event) if $poll_event;
    Irssi::timeout_add($settings{interval}*1000*60, \&callback, [1] );
}

if ( get_win() )
{
    register_poll_event();
    print_text( "$IRSSI{name} initialized: poll interval = $settings{interval}m" );
    callback();
}
else
{
    print_error( "Create a window named `$settings{window}'.  Then, reload $IRSSI{name}." );
    print_error( "Hint: /window new hide ; /window name $settings{window} ; /script load $IRSSI{name}" );
}
