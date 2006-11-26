# $Id: youtube.pl,v 1.15 2006-11-26 02:32:50 mitch Exp $
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
use Irssi 20020324 qw (command_bind command_runsub signal_add_first signal_add_last);
use IO::File;
use vars qw($VERSION %IRSSI);
use POSIX qw(strftime);
use Data::Dumper;

my $CVSVERSION = do { my @r = (q$Revision: 1.15 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
my $CVSDATE = (split(/ /, '$Date: 2006-11-26 02:32:50 $'))[1];
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

sub cmd_help {
	Irssi::print ( <<SCRIPTHELP_EOF

$IRSSI{name} - $IRSSI{changed}
$IRSSI{description}
$IRSSI{authors} <$IRSSI{contact}> $IRSSI{url}

configuration variables:
/set youtube_conffile   configuration file
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


    if ($message =~ m|(http://([-a-zA-Z0-9_.]+\.)*youtube.com/watch\?(?:.+=.+&)*v=([-a-zA-Z0-9_]+))|) {
	my $pageurl = $1;
      # my $subdomain = $2; (unneeded)
	my $file = $3;

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
		$videotitle =~ y|/ |__|;
		$file .= "_$videotitle";
	    }
	    write_debug($witem, "%RD%n xx${request}xx");

	    my $downurl = "http://youtube.com/get_video.php?$request";
	    write_debug($witem, "%RE%n xx${downurl}xx");
	
	    # write log and download
	    my $filename = "$downdir/$file";
	    my $cmdline = "GET \"$downurl\" > \"${filename}.flv\" &";
	    write_debug($witem, "%RF%n xx${cmdline}xx");
	    system($cmdline);
	    write_verbose($witem, "%R>>%n Saving youtube $videotitle");

	}
	
    }
}

sub cmd_save {
    
    my $filename = Irssi::settings_get_str('youtube_conffile');
    my $io = new IO::File $filename, "w";
    if (defined $io) {
	$io->print("DOWNDIR\t"   . Irssi::settings_get_str( 'youtube_downdir')   . "\n");
	$io->print("FREESPACE\t" . Irssi::settings_get_int( 'youtube_freespace') . "\n");
	$io->print("VERBOSE\t"   . Irssi::settings_get_bool('youtube_verbose')   . "\n");
	$io->close;
 	Irssi::print("youtube configuration saved to ".$filename);
    } else {
	Irssi::print("could not write youtube configuration to ".$filename.": $!");
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
    
    my $filename = Irssi::settings_get_str('youtube_conffile');
    my $io = new IO::File $filename, "r";
    if (defined $io) {
	foreach my $line ($io->getlines) {
	    chomp $line;
	    if ($line =~ /^([A-Z]+)\t(.*)$/) {
		if ($1 eq 'DOWNDIR') {
		    Irssi::settings_set_str( 'youtube_downdir',   $2);
		} elsif ($1 eq 'FREESPACE') {
		    Irssi::settings_set_int( 'youtube_freespace', $2);
		} elsif ($1 eq 'VERBOSE') {
		    Irssi::settings_set_bool('youtube_verbose',   $2);
		  }
	    }
	}
	Irssi::print("youtube configuration loaded from ".$filename);
    } else {
	Irssi::print("could not load youtube configuration from ".$filename.": $!");
    }
}

# init

command_bind('help youtube',\&cmd_help);
command_bind('youtube help',\&cmd_help);
command_bind('youtube load',\&cmd_load);
command_bind('youtube save',\&cmd_save);
command_bind 'youtube' => sub {
    my ( $data, $server, $item ) = @_;
    $data =~ s/\s+$//g;
    command_runsub ( 'youtube', $data, $server, $item ) ;
};
signal_add_first 'default command youtube' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};

Irssi::signal_add_first('command script load', 'sig_command_script_unload');
Irssi::signal_add_first('command script unload', 'sig_command_script_unload');
Irssi::signal_add('setup saved', 'cmd_save');

Irssi::settings_add_str( $IRSSI{'name'}, 'youtube_conffile',  Irssi::get_irssi_dir()."/youtube.cf");
Irssi::settings_add_str( $IRSSI{'name'}, 'youtube_downdir',   "$ENV{HOME}/youtube");
Irssi::settings_add_int( $IRSSI{'name'}, 'youtube_freespace', 100 * 1024);
Irssi::settings_add_bool($IRSSI{'name'}, 'youtube_verbose',   1);

cmd_load();
