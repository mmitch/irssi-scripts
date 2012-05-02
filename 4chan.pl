# autodownload 4chan (and similar) links before they disappear
#
# Copyright (C) 2006-2012  Christian Garbs <mitch@cgarbs.de>
# licensed under GNU GPL v2
#
# needs wget and the LWP modules
#
# based on trigger.pl by Wouter Coekaerts <wouter@coekaerts.be>

use strict;
use Irssi 20020324 qw (command_bind command_runsub signal_add_first signal_add_last);
use File::Temp qw(tempfile);
use IO::File;
use vars qw($VERSION %IRSSI);
use POSIX qw(strftime);

use LWP::UserAgent;
use HTTP::Cookies;

$VERSION = '2012-05-02';
%IRSSI = (
	authors  	=> 'Christian Garbs',
	contact  	=> 'mitch@cgarbs.de',
	name    	=> '4chan',
	description 	=> 'autodownload 4chan (and similar) links before they disappear',
	license 	=> 'GPLv2',
	url     	=> 'http://github.com/mmitch/irssi-scripts/',
	changed  	=> $VERSION,
);
my $USERAGENT='Mozilla/4.0 (compatible; MSIE 5.0; Linux) Opera 5.0  [en]';

# activate debug here
my $debug = 0;

sub cmd_help {
	Irssi::print ( <<"SCRIPTHELP_EOF"

$IRSSI{name} - $IRSSI{changed}
$IRSSI{description}
$IRSSI{authors} <$IRSSI{contact}> $IRSSI{url}

configuration variables:
/set 4chan_announce   announce linking sprees
/set 4chan_conffile   configuration file
/set 4chan_downdir    the download directory
/set 4chan_freespace  minimum space to be free
                      in downdir in 1024-blocks
                      (should prevent DoS)
/set 4chan_verbose    show link aquisition
SCRIPTHELP_EOF
   ,MSGLEVEL_CLIENTCRAP);
}

my (%last_nick, %spree_count);
my %spree_text = (
#    3 => 'NICK: Hat Trick',
    5 => 'NICK is on a linking spree',
   10 => 'NICK is on a rampage',
   15 => 'NICK is dominating',
   20 => 'NICK is unstoppable',
   25 => 'NICK is godlike',
   30 => 'NICK: WICKED SICK!',
   );

# "message public", SERVER_REC, char *msg, char *nick, char *address, char *target
signal_add_last("message public" => sub {check_for_link(\@_,1,4,2,0);});
# "message own_public", SERVER_REC, char *msg, char *target
signal_add_last("message own_public" => sub {check_for_link(\@_,1,2,-1,0);});

# "message private", SERVER_REC, char *msg, char *nick, char *address
signal_add_last("message private" => sub {check_for_link(\@_,1,-1,2,0);});
# "message own_private", SERVER_REC, char *msg, char *target, char *orig_target
signal_add_last("message own_private" => sub {check_for_link(\@_,1,2,-1,0);});

# "message irc action", SERVER_REC, char *msg, char *nick, char *address, char *target
signal_add_last("message irc action" => sub {check_for_link(\@_,1,4,2,0);});
# "message irc own_action", SERVER_REC, char *msg, char *target
signal_add_last("message irc own_action" => sub {check_for_link(\@_,1,2,-1,0);});


sub write_irssi($$) {
    my $witem = shift;
    my $text  = shift;

    if (defined $witem) {
	$witem->print($text, MSGLEVEL_CLIENTCRAP);
    } else {
	Irssi::print($text) ;
    }

}

sub write_verbose($$) {
    if (Irssi::settings_get_bool('4chan_verbose')) {
	write_irssi(shift, shift);
    }
}

sub write_debug($$) {
    if ($debug) {
	write_irssi(shift, shift);
    }
}

sub diskfree($) {
    # poor man's df
    # if you want it portable, use Filesys::Statvfs
    my $dir = shift;
    my $size;

    open DF, "df -P $dir|" or warn "can't open df: $!";
    my $line = <DF>; # skip header

    if ( $line = <DF> ) {
	if ($line =~ /\s(\d+)\s+\d{1,3}% (\/.*)$/) {
	    $size = $1;
	}
    } else {
	$size = -1; #some error occurred
    }

    close DF or warn "can't close df: $!";
    return $size;
}

sub download_it($$$$$$$$$$$) {

    my ($chan, $board, $file, $url, $downurl, $referrer,
	$witem, $paramchannel, $paramnick, $signal, $server) = (@_);

    write_debug($witem, '$chan='.$chan);
    write_debug($witem, '$board='.$board);
    write_debug($witem, '$file='.$file);
    write_debug($witem, '$url='.$url);
    write_debug($witem, '$downurl='.$downurl);
    write_debug($witem, '$referrer='.$referrer);

    my $now = strftime "%d.%m.%Y %H:%M:%S", localtime;
    $file =~ s/%/%25/g;
	
    my $channel = ($paramchannel == -1) ? '-private-' : $signal->[$paramchannel];
    ## TODO use current nick instead of '*self*'
    my $nick = ($paramnick == -1) ? '*self*' : $signal->[$paramnick];
	
    # handle linking sprees
    if (Irssi::settings_get_bool('4chan_announce')) {
	
	my $context;
	if ($paramchannel!=-1 && $server->channel_find($signal->[$paramchannel])) {
	    $context = $server->channel_find($signal->[$paramchannel]);
	} else {
	    $context = $server;
	}
	
	if ($last_nick{$channel} eq $nick) {
	    $spree_count{$channel}++;
	} else {
	    if ($spree_count{$channel} > 7) {
		$context->command('/SAY C-C-C-Combo breaker!');
	    }
	    $spree_count{$channel} = 1;
	    $last_nick{$channel} = $nick;
	}
	
	if (exists $spree_text{$spree_count{$channel}}) {
	    my $text = $spree_text{$spree_count{$channel}};
	    $text =~ s/NICK/$nick/g;
	    if (! ($text =~ s|\*self\*.\s*|/me |)) {
		$text = "/SAY $text";
	    }
	    $context->command($text);
	}
    }
    
    # do some checks
    my $downdir = Irssi::settings_get_str('4chan_downdir');
    unless (-e $downdir) {
	write_irssi($witem, "%R>>%n 4chan_downdir does not exist!");
	return;
    }
    unless (-d $downdir) {
	write_irssi($witem, "%R>>%n 4chan_downdir exists but is no directory!");
	return;
    }
    unless (-w $downdir) {
	write_irssi($witem, "%R>>%n 4chan_downdir is not writeable!");
	return;
    }
    if (diskfree($downdir) < Irssi::settings_get_int('4chan_freespace')) {
	write_irssi($witem, "%R>>%n 4chan_downdir has not enough free space left!");
	return;
    }
    
    # download
    $file =~ y|'"`*$!?|_|;
    my $filename = "$downdir/$file";
    my $io = new IO::File "$filename.idx", 'a';
    if (defined $io) {
	$io->print("NICK\t$nick\n");
	$io->print("CHANNEL\t$channel\n");
	$io->print("BOARD\t$board\n");
	$io->print("FILE\t$file\n");
	$io->print("URL\t$url\n");
	$io->print("TIME\t$now\n");
	$io->print("CHAN\t$chan\n");
	$io->close;
	$referrer = "--referer=\"$referrer\"" if ($referrer);
	my (undef, $tmpfile) = tempfile('4chan.tmp.XXXXXXXXXXXX', DIR => $downdir);
	$downurl = $url unless ($downurl);
	system("( wget -U \"$USERAGENT\" $referrer -qO \"$tmpfile\" \"$downurl\" && mv \"$tmpfile\" \"$filename\" && chmod =rw \"$filename\" || rm -f \"$tmpfile\" ) &");
	write_verbose($witem, "%R>>%n Saving 4chan link");
    }
}

sub check_for_link {
    my ($signal,$parammessage,$paramchannel,$paramnick,$paramserver) = @_;
    my $server = $signal->[$paramserver];
    my $target = $signal->[$paramchannel];
    my $message = ($parammessage == -1) ? '' : $signal->[$parammessage];

    # where are we, where do we print to?
    my $witem;
    if (defined $server) {
	$witem = $server->window_item_find($target);
    } else {
	$witem = Irssi::window_item_find($target);
    }

    # scan for URLs
    my ($chan, $url, $board, $file, $downurl);
    my $referrer = '';
    study $message;
    return if $message =~ m|/nosave|;

    my ($maxcount, $count) = (32, 0);
    

    while ($message =~ m|(https?://[a-z]+\.4chan[a-z]*\.org/([a-z0-9]+)/src(?:\.cgi)?/(?:cb-nws/)?(\S+\.[a-z]+))|g) {
	$chan = '4chan';
	$url = $1;
	$board = $2;
	$file = $3;
	$url =~ s|/src.cgi/|/src/|;
	$url =~ s|/src/cb-news/|/src/|;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://4chanarchive\.org/images/([a-z0-9]+)/\d+/(\d+\.[a-z]+))|g) {
	$chan = '4chanarchive';
	$url = $1;
	$board = $2;
	$file = $3;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://4chanarchive\.org/images/\d+/(\d+\.[a-z]+))|g) { # still needed?
	$chan = '4chanarchive';
	$url = $1;
	$board = '?';
	$file = $2;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://img\.fapchan\.org/([a-z0-9]+)/src/(\S+\.[a-z]+))|g) {
	$chan = 'fapchan';
	$url = $1;
	$board = $2;
	$file = $3;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    } 

    while ($message =~ m|(http://(www.)?krautchan.net/files/(\S+\.[a-z]+))|g) {
	$chan = 'Krautchan';
	$url = $1;
	$board = '?';
	$file = $3;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while  ($message =~ m|(http://(www.)?krautchan.net/download.pl/(\S+\.[a-z]+)/)|g) {
	$chan = 'Krautchan';
	$url = $1;
	$board = '?';
	$file = $3;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    } 

    while ($message =~ m|(http://i.somethingawful.com/(.*/)?([^/]+)/(\S+\.[a-z]+))|g) {
	$chan = 'sth awful';
	$url = $1;
	$board = $3;
	$file = $4;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m;(http://z0r.de/(\d+));g) {
	$chan = 'z0r.de';
	$url = $1;
	$referrer = $1;
	$board = '-';
	$file = "z0r-de_$2.swf";
	if ($2 < 2000) {
	    $downurl = "http://raz.z0r.de/L/$file";
	} else {
	    $downurl = "http://z0r.de/L/$file";
	}

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://[a-z]+\.2chan\.net/([a-z0-9]+)/src/(\S+\.[a-z]+))|g) {
	$chan = '2chan';
	$url = $1;
	$board = $2;
	$file = $3;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://[a-z]+\.7chan\.org/([a-z0-9]+)/src/(\S+\.[a-z]+))|g) {
	$chan = '7chan';
	$url = $1;
	$board = $2;
	$file = $3;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://[a-z]+\.gurochan\.net/([a-z0-9]+)/src/(\S+\.[a-z]+))|g) {
	$chan = 'gurochan';
	$url = $1;
	$board = $2;
	$file = $3;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://.*mexx\.onlinewelten\.com)/.*fotos/(\d+)/(\d+)/(\d+)(\.gross)?\.jpg|g) {
	$chan = 'animexx';
	$url = "$1/fotos/$2/$3/$4.gross.jpg";
	$board = '-';
	$file = "$2_$3_$4.jpg";

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://lh\d\.\S+\.\S+/abramsv/\S{11}/\S{11}/\S{11}/s.+)(/(\S+.jpg))|g) {
	$chan = 'Dark Roasted Blend';
	$url = "$1$2";
	$board = '-';
	$file = $3;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://rule63.nerdramblingz.com/index.php\?q=/post/view/(\d+))|g) {
	$chan = 'rule#63';
	$url = $1;
	$referrer = $url;
	$board = '-';
	$downurl = "http://rule63.nerdramblingz.com/index.php?q=/image/$2.jpg";
	$file = "r63_$2.jpg";

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://rule34.paheal.net/post/view/\d+)|g) {
	$chan = 'rule#34';
	$url = $1;
	$referrer = $url;
	$board = '-';
	$downurl = `GET "$1" | grep "<img.*id='main_image'" | sed -e "s|^.*src='||" -e "s/'.*\$//"`;
	chomp $downurl;
	$file = $downurl;
	$file =~ s|^.*/(\d+).*(\.[a-z]+)$|r34_$1$2|;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m|(http://(?:www\.)?wurstball\.de/(\d+)/)|g) {
	$chan = 'wurstball';
	$url = $1;
	$referrer = $url;
	my $number = $2;
	$board = '-';
	$downurl = `GET "$1" | grep '<img.*src="http://wurstball.de/static/ircview/pictures/' | sed -e 's|^.*http://|http://|' -e 's|".*||'`;
	chomp $downurl;
	$file = $downurl;
	$file =~ s|^.*\.|.|;
	$file = $number . $file;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m;(http://pics.nase-bohren.de/(.*\.(?:jpg|gif|png)));g) {
	$chan = 'nase-bohren';
	$url = $1;
	$referrer = 'http://pics.nase-bohren.de/';
	$board = '-';
	$file = $2;
	$downurl = $referrer . `GET "$url" | grep 'alt="$file' | sed -e 's/^.*src="//' -e 's/".*//'`;
	chomp $downurl;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m;(http://(?:www\.)?fukung\.net/v/(\d+)/(.+\.(?:jpg|gif|png)));g) {
	$chan = 'fukung.net';
	$url = $1;
	$referrer = $1;
	$board = '-';
	$file = $3;
	$downurl = "http://media.fukung.net/images/$2/$3";

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m;(http://naurunappula.com/\d+/(.+?\.(?:jpg|gif|png)));g) {
	$chan = 'naurunappula';
	$url = $1;
	$referrer = $1;
	$board = '-';
	$file = $2;
	$downurl = `GET "$url" | grep -A 11 'div id="viewembedded"' | grep "document.write('.*" `;
	$downurl =~ s/document.write\('//g;
	$downurl =~ s/'\);//g;
	$downurl =~ tr/\012//d;
	$downurl =~ s/^.*?src="//;
	$downurl =~ s/".*?$//;

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    while ($message =~ m;((http://(?:www\.)?ircz\.de)/(?:p/)?[0-9a-z]+);g) {

	$url = $1;
	$referrer = $1;
	$board = '-';
	$downurl =  $2;

	# needs login cookie
	# TODO: cache this!
	my $ua = LWP::UserAgent->new('agent' => 'Mozilla/5.0');
	my $jar = HTTP::Cookies->new();
	$ua->cookie_jar($jar);
	$ua->post('http://ircz.de', {'wat' => 'yes'});
	my $response = $ua->get($url);
	if ($response->content() =~ /<img id="pic".*src="([^"]+)"/) {
	    $chan = 'ircz.de';
	    $file = $1;
	    $downurl .= $file;
	    $file =~ s,^.*/,,;
	}

	download_it($chan, $board, $file, $url, $downurl, $referrer,
		    $witem, $paramchannel, $paramnick, $signal, $server);
	last if ++$count > $maxcount;
    }

    if ($count > $maxcount) {
	write_irssi($witem, "%R>>%n endless loop in 4chan.pl!");
    }

}

sub cmd_save {
    
    my $filename = Irssi::settings_get_str('4chan_conffile');
    my $io = new IO::File $filename, 'w';
    if (defined $io) {
	$io->print("ANNOUNCE\t"  . Irssi::settings_get_bool('4chan_announce')  . "\n");
	$io->print("DOWNDIR\t"   . Irssi::settings_get_str( '4chan_downdir')   . "\n");
	$io->print("FREESPACE\t" . Irssi::settings_get_int( '4chan_freespace') . "\n");
	$io->print("VERBOSE\t"   . Irssi::settings_get_bool('4chan_verbose')   . "\n");
	$io->close;
 	Irssi::print("4chan configuration saved to ".$filename);
    } else {
	Irssi::print("could not write 4chan configuration to ".$filename.": $!");
    }
    
}

# save on unload
sub sig_command_script_unload {
    my $script = shift;
    if ($script =~ /(.*\/)?$IRSSI{'name'}(\.pl)?$/) {
        cmd_save();
    }
}

sub cmd_load {
    
    my $filename = Irssi::settings_get_str('4chan_conffile');
    my $io = new IO::File $filename, 'r';
    if (defined $io) {
	foreach my $line ($io->getlines) {
	    chomp $line;
	    if ($line =~ /^([A-Z]+)\t(.*)$/) {
		if ($1 eq 'ANNOUNCE') {
		    Irssi::settings_set_bool('4chan_announce',  $2);
		} elsif ($1 eq 'DOWNDIR') {
		    Irssi::settings_set_str( '4chan_downdir',   $2);
		} elsif ($1 eq 'FREESPACE') {
		    Irssi::settings_set_int( '4chan_freespace', $2);
		} elsif ($1 eq 'VERBOSE') {
		    Irssi::settings_set_bool('4chan_verbose',   $2);
		  }
	    }
	}
	Irssi::print("4chan configuration loaded from ".$filename);
    } else {
	Irssi::print("could not load 4chan configuration from ".$filename.": $!");
    }
}

# init

command_bind('help 4chan',\&cmd_help);
command_bind('4chan help',\&cmd_help);
command_bind('4chan load',\&cmd_load);
command_bind('4chan save',\&cmd_save);
command_bind '4chan' => sub {
    my ( $data, $server, $item ) = @_;
    $data =~ s/\s+$//g;
    command_runsub ( '4chan', $data, $server, $item ) ;
};
signal_add_first 'default command 4chan' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};

Irssi::signal_add_first('command script load', 'sig_command_script_unload');
Irssi::signal_add_first('command script unload', 'sig_command_script_unload');
Irssi::signal_add('setup saved', 'cmd_save');

Irssi::settings_add_bool($IRSSI{'name'}, '4chan_announce',  0);
Irssi::settings_add_str( $IRSSI{'name'}, '4chan_conffile',  Irssi::get_irssi_dir()."/4chan.cf");
Irssi::settings_add_str( $IRSSI{'name'}, '4chan_downdir',   "$ENV{HOME}/4chan");
Irssi::settings_add_int( $IRSSI{'name'}, '4chan_freespace', 100 * 1024);
Irssi::settings_add_bool($IRSSI{'name'}, '4chan_verbose',   1);

cmd_load();
