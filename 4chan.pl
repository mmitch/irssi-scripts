# $Id: 4chan.pl,v 1.19 2006-08-11 18:13:06 mitch Exp $
#
# autodownload 4chan (and similar) links before they disappear
#
# (c) 2006 by Christian Garbs <mitch@cgarbs,de>
# licensed under GNU GPL v2
#
# needs GET from libwww-perl
#
# based on trigger.pl by Wouter Coekaerts <wouter@coekaerts.be>

#
# TODO:
# don't overwrite existing file later with an 404
#

use strict;
use Irssi 20020324 qw (command_bind signal_add_first signal_add_last);
use IO::File;
use vars qw($VERSION %IRSSI);
use POSIX qw(strftime);

my $CVSVERSION = do { my @r = (q$Revision: 1.19 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
my $CVSDATE = (split(/ /, '$Date: 2006-08-11 18:13:06 $'))[1];
$VERSION = $CVSVERSION;
%IRSSI = (
	authors  	=> 'Christian Garbs',
	contact  	=> 'mitch@cgarbs.de',
	name    	=> '4chan',
	description 	=> 'autodownload 4chan (and similar) links before they disappear',
	license 	=> 'GPLv2',
	url     	=> 'http://www.cgarbs.de/',
	changed  	=> $CVSDATE,
);

# activate debug here
my $debug = 0;

## TODO help does not work
sub cmd_help {
	Irssi::print ( <<"SCRIPTHELP_EOF"

$IRSSI{name} - $IRSSI{changed}
$IRSSI{description}
$IRSSI{authors} <$IRSSI{contact}> $IRSSI{url}

configuration variables:
/set 4chan_announce   announce linking sprees
/set 4chan_downdir    the download directory
/set 4chan_verbose    show link aquisition
/set 4chan_freespace  minimum space to be free
                      in downdir in 1024-blocks
                      (should prevent DoS)
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
    my ($chan, $url, $board, $file);
    if ( $message =~ m|(http://[a-z]+\.4chan[a-z]*\.org/([a-z]+)/src/(\S+\.[a-z]+))|) {
	$chan = '4chan';
	$url = $1;
	$board = $2;
	$file = $3;
    } elsif ($message =~ m|(http://einskanal.net/images/[0-9]+/(\S+\.[a-z]+))|) {
	$chan = 'Einskanal';
	$url = $1;
	$board = '?';
	$file = $2;
    } elsif ($message =~ m|(http://i.somethingawful.com/(.*/)?([^/]+)/(\S+\.[a-z]+))|) {
	$chan = 'sth awful';
	$url = $1;
	$board = $3;
	$file = $4;
    }

    # download if something was found
    if (defined $chan) {
	my $now = strftime "%d.%m.%Y %H:%M:%S", localtime;
	$file =~ s/%/%25/g;
	
	my $channel = ($paramchannel == -1) ? '-private-' : $signal->[$paramchannel];
	## TODO use current nick instead of '*self*'
	my $nick = ($paramnick == -1) ? '*self*' : $signal->[$paramnick];
	
	# handle linking sprees
	if (Irssi::settings_get_bool('4chan_announce')) {
	    if ($last_nick{$channel} eq $nick) {
		$spree_count{$channel}++;
	    } else {
		$spree_count{$channel} = 1;
		$last_nick{$channel} = $nick;
	    }
	    if (exists $spree_text{$spree_count{$channel}}) {
		my $text = $spree_text{$spree_count{$channel}};
		$text =~ s/NICK/$nick/g;
		if (! ($text =~ s|\*self\*.\s*|/me |)) {
		    $text = "/SAY $text";
		}
		my $context;
		if ($paramchannel!=-1 && $server->channel_find($signal->[$paramchannel])) {
		    $context = $server->channel_find($signal->[$paramchannel]);
		} else {
		    $context = $server;
		}
		$context->command("$text");
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
	my $filename = "$downdir/$file";
	my $io = new IO::File "$filename.idx", "a";
	if (defined $io) {
	    $io->print("NICK\t$nick\n");
	    $io->print("CHANNEL\t$channel\n");
	    $io->print("BOARD\t$board\n");
	    $io->print("FILE\t$file\n");
	    $io->print("URL\t$url\n");
	    $io->print("TIME\t$now\n");
	    $io->print("CHAN\t$chan\n");
	    $io->close;
	    system("GET \"$url\" > \"$filename\" &");
	    write_verbose($witem, "%R>>%n Saving 4chan link");
	}

    }
}

# init

command_bind('4chan',\&cmd_help);
signal_add_first 'default command 4chan' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};

Irssi::settings_add_bool($IRSSI{'name'}, '4chan_announce',  0);
Irssi::settings_add_str( $IRSSI{'name'}, '4chan_downdir',   "$ENV{HOME}/4chan");
Irssi::settings_add_int( $IRSSI{'name'}, '4chan_freespace', 100 * 1024);
Irssi::settings_add_bool($IRSSI{'name'}, '4chan_verbose',   1);
