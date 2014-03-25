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
    url     => 'https://github.com/mmitch/irssi-scripts',
    changed => '2014-01-05',
);

my %settings =
    (
     window   => 'rssfeeds', # the irssi window name
     interval => 12,         # check individual feed intervals every n minutes
    );

my @feedlist =
    (
     # for testing (high-volume feeds)
#     {
#	 name     => '/.',
#	 url      => 'http://www.slashdot.org/slashdot.rss',
#	 interval => 11
#     },
#     {
#	 name     => 'heise',
#	 url      => 'http://www.heise.de/newsticker/heise.rdf',
#	 interval => 11
#     },
     # only locally retrievable, you won't get this
     {
	 name     => 'psy',
	 url      => 'http://www.mitch.h.shuttle.de/kosmosblog.xml',
	 interval => 100 + int(rand(100))
     },
     {
	 name     => 'wiki',
	 url      => 'http://www.mitch.h.shuttle.de/mediawiki/index.php?title=Spezial:Letzte_%C3%84nderungen&feed=atom',
	 interval => 20 + int(rand(20))
     },
     # my stuff
     {
	 name     => 'cgarbs',
	 url      => 'http://www.cgarbs.de/rssfeed.en.xml',
	 interval => 150 + int(rand(20))
     },
     {
	 name     => 'mitch.c',
	 url      => 'http://www.cgarbs.de/blog/feeds/comments.rss2',
	 interval => 30 + int(rand(20))
     },
     {
	 name     => 'mitch',
	 url      => 'http://www.cgarbs.de/blog/feeds/index.rss2',
	 interval => 50 + int(rand(20))
     },
     # real feeds
     {
	 name     => 'BS',
	 url      => 'http://beratersprech.de/feed/',
	 interval => 77 + int(rand(33)),
     },
     {
	 name     => 'polloi',
	 url      => 'http://feed43.com/ahoipolloi.xml',
	 interval => 50 + int(rand(20)),
     },
     {
	 name     => 'devops',
	 url      => 'http://devopsreactions.tumblr.com/rss',
	 interval => 50 + int(rand(20)),
     },
     {
	 name     => 'vongestern',
	 url      => 'http://www.vongestern.com/feeds/posts/default',
	 interval => 99 + int(rand(40)),
     },
     {
	 name     => 'virt',
	 url      => 'http://www.biglionmusic.com/feed/',
	 interval => 50 + int(rand(20)),
     },
     {
	 name     => 'fefe',
	 url      => 'http://blog.fefe.de/rss.xml?html',
	 interval => 30 + int(rand(20)),
     },
     {
	 name     => 'nudelmonster',
	 url      => 'http://nudelmonster.blogspot.com/feeds/posts/default',
	 interval => 99 + int(rand(40)),
     },
     {
	 name     => 'leckse',
	 url      => 'https://ssl.animexx.de/weblog/415/rss/',
	 interval => 150 + int(rand(20)),
     },
     {
	 name     => 'nonbiri',
	 url      => 'http://ani.donmai.ch/?feed=rss2',
	 interval => 150 + int(rand(20)),
     },
     {
	 name     => 'ipfreaks',
	 url      => 'http://ipfreaks.de/feed/',
	 interval => 150 + int(rand(20)),
     },
     {
	 name     => 'piratesoflove',
	 url      => 'http://www.pirates-of-love.de/?feed=rss2',
	 interval => 150 + int(rand(20)),
     },
     {
	 name     => 'mrehkopf',
	 url      => 'http://mrehkopf.de/blog/?feed=rss2',
	 interval => 150 + int(rand(20)),
     },
     {
	 name     => 'sd2snes',
	 url      => 'http://sd2snes.de/blog/feed',
	 interval => 150 + int(rand(30)),
     },
     {
	 name     => 'lalufu',
	 url      => 'http://www.skytale.net/blog/feeds/index.rss2',
	 interval => 150 + int(rand(30)),
     },
     {
	 name     => 'niessu',
	 url      => 'http://www.plouf.de/foto/index.php?/feeds/index.rss2',
	 interval => 150 + int(rand(30)),
     },
     {
	 name     => 'ant',
	 url      => 'http://blog.tomodachi.de/feeds/index.rss2',
	 interval => 150 + int(rand(30)),
     },
    );

my $poll_event = 0;

my @colors = qw
    (
     %w%4 %w%1 %w%5 %k%2 %k%3 %k%6 %k%7 %k%1 %k%5 
     %g%4 %g%1 %r%4 %r%2 %r%3 %r%6 %r%7
     %m%4 %m%3 %m%6 %m%7 %y%4 %y%1 %y%5 %R%4 %R%3 
     %G%4 %G%1 %G%5 %c%4 %c%1 %c%5 %C%4 %C%1 %C%5
     %B%4 %M%4 %M%7 %b%2 %b%3 %b%6 %b%7 
    );

# Fetches the RSS from server and returns a list of RSS items.
sub fetch_rss
{
    my $rss_url = shift;

    my $ua = LWP::UserAgent->new (env_proxy => 1, keep_alive => 1, timeout => 30);
    my $request = HTTP::Request->new('GET', $rss_url);
    my $response = $ua->request ($request);
    return unless $response->is_success;
    my $data = $response->content;
    return unless length $data > 0; # TODO: What is the minimum size of a valid RSS feed?
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

sub print_intern
{
    my $win   = shift;
    my $level = shift;

    if (! $win)
    {
	$win = Irssi::active_win();
    }

    $win->print($_, $level) foreach @_;
}

sub print_error
{
    print_intern(Irssi::active_win(), MSGLEVEL_CLIENTERROR, @_);
}

sub print_text
{
    print_intern(get_win(), MSGLEVEL_PUBLIC, @_);
}

sub print_debug
{
#    print_intern(Irssi::window_find_name('(status)'), MSGLEVEL_CLIENTCRAP, @_);
}

sub poll_feed
{
    my $feed = shift;

    # individual poll time reached?
    my $lastpoll = $feed->{lastpoll};
    my $now = time();
    if ($now - $lastpoll > $feed->{interval} * 60)
    {
	print_debug "Checking RSS feed $feed->{name} [$feed->{url}]...";
	my @new_items = fetch_rss( $feed->{url} );
	if (@new_items)
	{
	    my @old_items = @{$feed->{items}};
	    my @delta = delta_rss (\@old_items, \@new_items);
	    foreach my $item (reverse @delta)
	    {
		print_text(
		    $feed->{color} . $feed->{name} . '%n ' .
		    '%_' . $item->{title}. '%_ ' .
		    $item->{link}
		    );
	    }
	    $feed->{items} = \@new_items;
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

sub rainbow_bar
{
    my $colortext = '';
    foreach my $color (@colors)
    {
	my $escaped = $color;
	$escaped =~ s/%/%%/g;
	$colortext .= "$color$escaped%n ";
    }
    print_text( $colortext );
}


### main ignition sequence start

# initialize feeds
my $i = 0;
foreach my $feed (@feedlist)
{
    $feed->{lastpoll} = 0;
    $feed->{items} = [];
    $feed->{color} = $colors[ $i++ % @colors ];
}

# startup
if ( get_win() )
{
    register_poll_event();
    print_text( "$IRSSI{name} initialized: poll interval = $settings{interval}m" );

    # just for color debugging
    # rainbow_bar();

    callback();
}
else
{
    print_error( "Create a window named `$settings{window}'.  Then, reload $IRSSI{name}." );
    print_error( "Hint: /window new hide ; /window name $settings{window} ; /script load $IRSSI{name}" );
}
