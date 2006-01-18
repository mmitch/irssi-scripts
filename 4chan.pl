# $Id: 4chan.pl,v 1.4 2006-01-18 20:33:54 mitch Exp $
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

my $CVSVERSION = do { my @r = (q$Revision: 1.4 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
my $CVSDATE = (split(/ /, '$Date: 2006-01-18 20:33:54 $'))[1];
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

sub cmd_help {
	Irssi::print ( <<SCRIPTHELP_EOF

set 4chan_downdir to your desired download directory

SCRIPTHELP_EOF
   ,MSGLEVEL_CLIENTCRAP);
}


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

   
    if ($message =~ m|(http://[a-z]+\.4chan[a-z]*\.org/([a-z]+)/src/(\d+.[a-z]+))|) {
	my $now = strftime "%d.%m.%Y %H:%M:%S", localtime;
	my $url = $1;
	my $board = $2;
	my $file = $3;
	
	my $channel = ($paramchannel == -1) ? '-private-' : $signal->[$paramchannel];
	my $nick = ($paramnick == -1) ? '*self*' : $signal->[$paramnick];
	
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
	    if (defined $witem) {
		$witem->print("Saved 4chan link", MSGLEVEL_CLIENTCRAP);
	    } else {
		Irssi::print("Saved 4chan $filename");
	    }
	}

    }
}

# init

command_bind('4chan help',\&cmd_help);
command_bind('help 4chan',\&cmd_help);
signal_add_first 'default command 4chan' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};

Irssi::settings_add_str($IRSSI{'name'}, '4chan_downdir', "$ENV{HOME}/4chan");
