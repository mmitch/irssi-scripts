# collect links and write them to an HTML file for browser access
#
# Copyright (C) 2012  Christian Garbs <mitch@cgarbs.de>
# licensed under GNU GPL v2
#
#                   based on 4chan.pl   by Christian Garbs  <mitch@cgarbs.de>
# which in turn was based on trigger.pl by Wouter Coekaerts <wouter@coekaerts.be>

use strict;
use Irssi 20020324 qw (command_bind command_runsub signal_add_first signal_add_last);
use IO::File;
use vars qw($VERSION %IRSSI);
use POSIX qw(strftime);

$VERSION = '2012-05-02';
%IRSSI = (
	authors  	=> 'Christian Garbs',
	contact  	=> 'mitch@cgarbs.de',
	name    	=> 'urlgatherer',
	description 	=> 'collect links and write them to an HTML file for browser access',
	license 	=> 'GPLv2',
	url     	=> 'http://github.com/mmitch/irssi-scripts/',
	changed  	=> $VERSION,
);
my $USERAGENT='Mozilla/4.0 (compatible; MSIE 5.0; Linux) Opera 5.0  [en]';

# activate debug here
my $debug = 0;
## TODO: write better debugging. all debug strings are concatenated and then thrown away if $debug is disables, this wastes CPU

sub cmd_help {
	Irssi::print ( <<"SCRIPTHELP_EOF"

$IRSSI{name} - $IRSSI{changed}
$IRSSI{description}
$IRSSI{authors} <$IRSSI{contact}> $IRSSI{url}

configuration variables:
/set urlgatherer_conffile   configuration file
/set urlgatherer_expire    delete links after this many hours
/set urlgatherer_file       the output file (HTML)
/set urlgatherer_refresh    wait at least this many seconds
                            before refreshing the output file
/set urlgatherer_verbose    show link aquisition
SCRIPTHELP_EOF
   ,MSGLEVEL_CLIENTCRAP);
}

my @urlgatherer_links = ();
my $urlgatherer_last_write = 0;

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
    if (Irssi::settings_get_bool('urlgatherer_verbose')) {
	write_irssi(shift, shift);
    }
}

sub write_debug($$) {
    if ($debug) {
	write_irssi(shift, shift);
    }
}

sub update_html_file($$) {

    my ($witem, $now) = (@_);

    write_debug($witem, "starting housekeeping");

    # do housekeeping, expire old entries
    my $expiredate = $now - (Irssi::settings_get_int('urlgatherer_expire') * 3600);
    while ($urlgatherer_links[0]->{TIME} < $expiredate) {
	write_debug($witem, "removing <$urlgatherer_links[0]->{TIMESTR}> -> <$urlgatherer_links[0]->{URL}>");
	shift @urlgatherer_links;
    }
    write_debug($witem, scalar(@urlgatherer_links) . ' entries left in database');

    my $io = new IO::File Irssi::settings_get_str('urlgatherer_file'), 'w';
    if (defined $io) {
	write_debug($witem, 'writing HTML file');
	$io->print('<html><head><title>urlgatherer for irssi</title><meta http-equiv="refresh" content="'
		   . Irssi::settings_get_int('urlgatherer_refresh') . '"></title></head><body>');
	$io->print('<table><thead><tr><th>time</th><th>channel</th><th>user</th><th>url</th></tr></thead><tbody>');
	foreach my $link (reverse @urlgatherer_links) {
	    $io->print("<tr><td>$link->{TIMESTR}</td><td>$link->{CHANNEL}</td><td>$link->{NICK}</td><td><a href=\"$link->{URL}\">$link->{URL}</a></td></tr>\n");
	}
	$io->print('</tbody></table></body></html>');
	$io->close;

	$urlgatherer_last_write = $now;
    } else {
	write_irssi($witem, "%R>>%n urlgatherer could not write to html file: $!");
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

    # don't log private channels (TODO: make this configurable)
    if ($paramchannel == -1) {
	write_debug($witem, 'private channel, exit');
	return;
    }

    # scan for URLs
    my ($maxcount, $count) = (32, 0);

    my $now = time;
    my $now_str = strftime "%d.%m.%Y %H:%M:%S", localtime;

    while ($message =~ m,(?:((?:http|https|ftp|file)://.*)\s?|(www\..*)\s?),gi) {
	my $url = $1;
	if ($url =~ /^www\./i) {
	    $url = 'http://'.$url;
	}

	# sanitize URL
	$url =~ s/(["'<>()])/ sprintf "%%%0x", ord $1 /eg;

	push @urlgatherer_links, {
	    'URL' => $url,
	    'TIME' => $now,
	    'TIMESTR' => $now_str,
	    ## TODO use current nick instead of '*self*'
	    'NICK' => ($paramnick == -1) ? '*self*' : $signal->[$paramnick],
	    'CHANNEL' => ($paramchannel == -1) ? '-private-' : $target,
	};

	write_verbose($witem, "%R>>%n Saving urlgatherer link");
	write_debug($witem, "added url <$url>");

	last if ++$count > $maxcount;
    }

    if ($count > $maxcount) {
	write_irssi($witem, "%R>>%n endless loop in urlgatherer.pl!");
    }

    # now check if the HTML file needs to be rewritten
    write_debug($witem, "now=$now, last_write=$urlgatherer_last_write, refresh=".Irssi::settings_get_int('urlgatherer_refresh'));
    if ($now > $urlgatherer_last_write + Irssi::settings_get_int('urlgatherer_refresh')) {
	write_debug($witem, 'BAR');
	update_html_file($witem, $now);
    }

}

sub cmd_save {
    
    my $filename = Irssi::settings_get_str('urlgatherer_conffile');
    my $io = new IO::File $filename, 'w';
    if (defined $io) {
	$io->print("EXPIRE\t"  . Irssi::settings_get_int( 'urlgatherer_expire')  . "\n");
	$io->print("FILE\t"    . Irssi::settings_get_str( 'urlgatherer_file')    . "\n");
	$io->print("REFRESH\t" . Irssi::settings_get_int( 'urlgatherer_refresh') . "\n");
	$io->print("VERBOSE\t" . Irssi::settings_get_bool('urlgatherer_verbose') . "\n");
	$io->close;
 	Irssi::print("urlgatherer configuration saved to ".$filename);
    } else {
	Irssi::print("could not write urlgatherer configuration to ".$filename.": $!");
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
    
    my $filename = Irssi::settings_get_str('urlgatherer_conffile');
    my $io = new IO::File $filename, 'r';
    if (defined $io) {
	foreach my $line ($io->getlines) {
	    chomp $line;
	    if ($line =~ /^([A-Z]+)\t(.*)$/) {
		if ($1 eq 'EXPIRE') {
		    Irssi::settings_set_int('urlgatherer_expire',  $2);
		} elsif ($1 eq 'FILE') {
		    Irssi::settings_set_str( 'urlgatherer_refresh',   $2);
		} elsif ($1 eq 'REFRESH') {
		    Irssi::settings_set_int( 'urlgatherer_refresh', $2);
		} elsif ($1 eq 'VERBOSE') {
		    Irssi::settings_set_bool('urlgatherer_verbose',   $2);
		  }
	    }
	}
	Irssi::print("urlgatherer configuration loaded from ".$filename);
    } else {
	Irssi::print("could not load urlgatherer configuration from ".$filename.": $!");
    }
}

# init

command_bind('help urlgatherer',\&cmd_help);
command_bind('urlgatherer help',\&cmd_help);
command_bind('urlgatherer load',\&cmd_load);
command_bind('urlgatherer save',\&cmd_save);
command_bind 'urlgatherer' => sub {
    my ( $data, $server, $item ) = @_;
    $data =~ s/\s+$//g;
    command_runsub ( 'urlgatherer', $data, $server, $item ) ;
};
signal_add_first 'default command urlgatherer' => sub {
	# gets triggered if called with unknown subcommand
	cmd_help();
};

Irssi::signal_add_first('command script load', 'sig_command_script_unload');
Irssi::signal_add_first('command script unload', 'sig_command_script_unload');
Irssi::signal_add('setup saved', 'cmd_save');

Irssi::settings_add_str( $IRSSI{'name'}, 'urlgatherer_conffile',  Irssi::get_irssi_dir()."/urlgatherer.cf");
Irssi::settings_add_int( $IRSSI{'name'}, 'urlgatherer_expire', 96);
Irssi::settings_add_str( $IRSSI{'name'}, 'urlgatherer_file', '/tmp/urlgatherer.html');
Irssi::settings_add_int( $IRSSI{'name'}, 'urlgatherer_refresh', 1);
Irssi::settings_add_bool($IRSSI{'name'}, 'urlgatherer_verbose',   1);
## TODO: add CSS variable

cmd_load();
