# $Id: youtube.pl,v 1.8 2006-07-18 18:44:44 mitch Exp $
#
# autodownload youtube videos
#
# (c) 2006 by Christian Garbs <mitch@cgarbs,de>
# licensed under GNU GPL v2
#
# needs GET from libwww-perl
#
# based on trigger.pl by Wouter Coekaerts <wouter@coekaerts.be>
# download strategy revised using
# http://www.kde-apps.org/content/show.php?content=41456

#
# TODO:
# don't overwrite existing file later with an 404
#

use strict;
use Irssi 20020324 qw (command_bind signal_add_first signal_add_last);
use IO::File;
use vars qw($VERSION %IRSSI);
use POSIX qw(strftime);

my $CVSVERSION = do { my @r = (q$Revision: 1.8 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
my $CVSDATE = (split(/ /, '$Date: 2006-07-18 18:44:44 $'))[1];
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

# activate debug here
my $debug = 0;

## TODO help does not work
sub cmd_help {
	Irssi::print ( <<SCRIPTHELP_EOF

$IRSSI{name} - $IRSSI{changed}
$IRSSI{description}
$IRSSI{authors} <$IRSSI{contact}> $IRSSI{url}

configuration variables:
/set youtube_downdir    the download directory
/set youtube_verbose    show link aquisition
/set youtube_freespace  minimum space to be free
                        in downdir in 1024-blocks
                        (should prevent DoS)
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
    if (Irssi::settings_get_bool('youtube_verbose')) {
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


    my $witem;
    if (defined $server) {
	$witem = $server->window_item_find($target);
    } else {
	$witem = Irssi::window_item_find($target);
    }


    if ($message =~ m|(http://www.youtube.com/watch\?(?:.+=.+&)*v=([-a-zA-Z0-9_]+))|) {
	my $pageurl = $1;
	my $file = $2;

	# do some checks
	my $downdir = Irssi::settings_get_str('youtube_downdir');
	unless (-e $downdir) {
	    write_irssi($witem, "%R>>%n youtube_downdir does not exist!");
	    return;
	}
	unless (-d $downdir) {
	    write_irssi($witem, "%R>>%n youtube_downdir exists but is no directory!");
	    return;
	}
	unless (-w $downdir) {
	    write_irssi($witem, "%R>>%n youtube_downdir is not writeable!");
	    return;
	}
	if (diskfree($downdir) < Irssi::settings_get_int('youtube_freespace')) {
	    write_irssi($witem, "%R>>%n youtube_downdir has not enough free space left!");
	    return;
	}

	my $string = `GET $pageurl | grep '/watch_fullscreen'`;

        write_debug($witem, "%RA%n $pageurl xx${string}xx");
	if ($string =~ m/watch_fullscreen\?(.*)&fs/) {
	    write_debug($witem, "%RB%n xx${1}xx");
	    my $request = $1;
	    my $videotitle = $file;

	    if ($string =~ m/&title=" \+ "([^"]*)"/) {
		write_debug($witem, "%RC%n xx${1}xx");
		$videotitle = $1;
		$videotitle =~ y/ /_/;
		$file .= "_$videotitle";
	    }
	    write_debug($witem, "%RD%n xx${request}xx");

	    my $downurl = "http://youtube.com/get_video.php?$request";
	    write_debug($witem, "%RE%n xx${downurl}xx");
	
	    # write log and download
	    my $filename = "$downdir/$file";
	    my $cmdline = "GET \"$downurl\" > \"$filename\" &";
	    write_debug($witem, "%RF%n xx${cmdline}xx");
	    system($cmdline);
	    write_verbose($witem, "%R>>%n Saving youtube $videotitle");

	}
	
    }
}

# init

command_bind('youtube',\&cmd_help);
signal_add_first 'default command youtube' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};

Irssi::settings_add_str( $IRSSI{'name'}, 'youtube_downdir',   "$ENV{HOME}/youtube");
Irssi::settings_add_int( $IRSSI{'name'}, 'youtube_freespace', 100 * 1024);
Irssi::settings_add_bool($IRSSI{'name'}, 'youtube_verbose',   1);
