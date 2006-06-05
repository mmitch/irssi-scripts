# $Id: youtube.pl,v 1.2 2006-06-05 23:52:50 mitch Exp $
#
# autodownload youtube videos
#
# (c) 2006 by Christian Garbs <mitch@cgarbs,de>
# licensed under GNU GPL v2
#
# needs wget
#
# based on trigger.pl by Wouter Coekaerts <wouter@coekaerts.be>

use strict;
use Irssi 20020324 qw (command_bind signal_add_first signal_add_last);
use IO::File;
use vars qw($VERSION %IRSSI);
use POSIX qw(strftime);

my $CVSVERSION = do { my @r = (q$Revision: 1.2 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
my $CVSDATE = (split(/ /, '$Date: 2006-06-05 23:52:50 $'))[1];
$VERSION = $CVSVERSION;
%IRSSI = (
	authors  	=> 'Christian Garbs',
	contact  	=> 'mitch@cgarbs.de',
	name    	=> 'youtube',
	description 	=> 'autodownload youtube videos',
	license 	=> 'GPLv2',
	url     	=> 'http://www.cgarbs.de/',
	changed  	=> $CVSDATE,
);

## TODO help does not work
sub cmd_help {
	Irssi::print ( <<SCRIPTHELP_EOF

set youtube_downdir to your desired download directory
set youtube_verbose to show link aquisition

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

   
    if ($message =~ m|(http://www.youtube.com/watch\?(?:.+=.+&)*v=([a-zA-Z0-9]+))|) {
	my $pageurl = $1;
	my $file = $2;
	my $downurl = "http://v100.youtube.com/get_video?video_id=$file";

	my $videotitle = `GET $pageurl | grep 'name="title"'`;
	$videotitle =~ /content="(.*)">/;
	$videotitle = $1;
	$videotitle =~ y/ /_/;
	$file .= "_$videotitle";
	
	# write log and download
	my $filename = Irssi::settings_get_str('youtube_downdir') . "/$file";
	my $cmdline = "wget -O \"$filename\" -q \"$downurl\" &";
	# debug $witem->print("%R>>%n $cmdline", MSGLEVEL_CLIENTCRAP);
	system($cmdline);

	if (defined $witem) {
	    $witem->print("%R>>%n Saved youtube $videotitle", MSGLEVEL_CLIENTCRAP);
	} else {
	    Irssi::print("%R>>%n Saved youtube $videotitle");
	}

    }
}

# init

command_bind('youtube help',\&cmd_help);
command_bind('help youtube',\&cmd_help);
signal_add_first 'default command youtube' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};

Irssi::settings_add_str($IRSSI{'name'}, 'youtube_downdir', "$ENV{HOME}/youtube");
