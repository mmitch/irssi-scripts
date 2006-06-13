# $Id: 4chan.pl,v 1.9 2006-06-13 12:41:09 mitch Exp $
#
# autodownload 4chan links before they dissappear
#
# (c) 2006 by Christian Garbs <mitch@cgarbs,de>
# licensed under GNU GPL v2
#
# needs GET from libwww-perl
#
# based on trigger.pl by Wouter Coekaerts <wouter@coekaerts.be>

use strict;
use Irssi 20020324 qw (command_bind signal_add_first signal_add_last);
use IO::File;
use vars qw($VERSION %IRSSI);
use POSIX qw(strftime);

my $CVSVERSION = do { my @r = (q$Revision: 1.9 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
my $CVSDATE = (split(/ /, '$Date: 2006-06-13 12:41:09 $'))[1];
$VERSION = $CVSVERSION;
%IRSSI = (
	authors  	=> 'Christian Garbs',
	contact  	=> 'mitch@cgarbs.de',
	name    	=> '4chan',
	description 	=> 'autodownload 4chan links before they dissappear',
	license 	=> 'GPLv2',
	url     	=> 'http://www.cgarbs.de/',
	changed  	=> $CVSDATE,
);

## TODO help does not work
sub cmd_help {
	Irssi::print ( <<"SCRIPTHELP_EOF"

$IRSSI{name} - $IRSSI{changed}
$IRSSI{description}
$IRSSI{authors} <$IRSSI{contact}> $IRSSI{url}

configuration variables:
/set 4chan_downdir  to your desired download directory
/set 4chan_verbose  to show link aquisition
/set 4chan_announce to send comments on link sprees
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


sub check_for_link {
    my ($signal,$parammessage,$paramchannel,$paramnick,$paramserver) = @_;
    my $server = $signal->[$paramserver];
    my $target = $signal->[$paramchannel];
    my $message = ($parammessage == -1) ? '' : $signal->[$parammessage];
    

    my $witem;
    if (defined $server) {
	$witem = $server->window_item_find($target);
    } else {
	$witem = Irssi::window_item_find($target);
    }

   
    if ( ($message =~ m|(http://[a-z]+\.4chan[a-z]*\.org/([a-z]+)/src/(\d+.[a-z]+))|)
	 or
	 ($message =~ m|(http://(eins)kanal.net/images/[0-9]+/(\S+.[a-z]+))|) ){
	my $now = strftime "%d.%m.%Y %H:%M:%S", localtime;
	my $url = $1;
	my $board = $2;
	my $file = $3;
	$file =~ s/%/%25/g;
	
	my $channel = ($paramchannel == -1) ? '-private-' : $signal->[$paramchannel];
	## TODO use current nick instead of '*self*'
	my $nick = ($paramnick == -1) ? '*self*' : $signal->[$paramnick];
	
	# linking sprees
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

	# write log and download
	my $filename = Irssi::settings_get_str('4chan_downdir') . "/$file";
	my $io = new IO::File "$filename.idx", "a";
	if (defined $io) {
	    $io->print("NICK\t$nick\n");
	    $io->print("CHANNEL\t$channel\n");
	    $io->print("BOARD\t$board\n");
	    $io->print("FILE\t$file\n");
	    $io->print("URL\t$url\n");
	    $io->print("TIME\t$now\n");
	    $io->close;
	    system("GET \"$url\" > \"$filename\" &");

	    if (Irssi::settings_get_bool('4chan_verbose')) {
		if (defined $witem) {
		    $witem->print("%R>>%n Saved 4chan link", MSGLEVEL_CLIENTCRAP);
		} else {
		    Irssi::print("%R>>%n Saved 4chan $filename");
		}
	    }

	}

    }
}

# init

command_bind('4chan',\&cmd_help);
signal_add_first 'default command 4chan' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};

Irssi::settings_add_str( $IRSSI{'name'}, '4chan_downdir',  "$ENV{HOME}/4chan");
Irssi::settings_add_bool($IRSSI{'name'}, '4chan_verbose',  '1');
Irssi::settings_add_bool($IRSSI{'name'}, '4chan_announce', '0');
