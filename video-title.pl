# collect links and write them to an HTML file for browser access
#
# Copyright (C) 2020  Christian Garbs <mitch@cgarbs.de>
# licensed under GNU GPL v2 or later
#
#                   based on urlgatherer.pl by Christian Garbs  <mitch@cgarbs.de>
# which in turn was based on 4chan.pl       by Christian Garbs  <mitch@cgarbs.de>
# which in turn was based on trigger.pl     by Wouter Coekaerts <wouter@coekaerts.be>

use strict;
use Irssi 20020324 qw (signal_add_first signal_add_last);
use IO::File;
use vars qw($VERSION %IRSSI);

$VERSION = '2023-05-21';
%IRSSI = (
	authors  	=> 'Christian Garbs',
	contact  	=> 'mitch@cgarbs.de',
	name    	=> 'video-title',
	description 	=> 'show video title above video links ',
	license 	=> 'GPLv2+',
	url     	=> 'http://github.com/mmitch/irssi-scripts/',
	changed  	=> $VERSION,
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
    my ($witem, $text) = @_;

    if (defined $witem) {
	$witem->print($text, MSGLEVEL_CLIENTCRAP);
    } else {
	Irssi::print($text) ;
    }
}

sub write_error($$) {
    my ($witem, $error) = @_;
    my $formatted = '%R>>%n ' . $error;
    write_irssi($witem, $formatted);
}

sub write_title($$) {
    my ($witem, $title) = @_;
    my $formatted = '%K' . $title . '%n'; # or try %m instead of %K
    write_irssi($witem, $formatted);
}

sub check_for_link {
    my ($signal, $parammessage, $paramchannel, $paramnick, $paramserver) = @_;
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
    my ($maxcount, $count) = (32, 0);

    while ($message =~ m,(https?://[^/]*(youtube\..*|youtu.be)/[^ ]+),gi) {
	my $url = $1;

	# sanitize URL
	$url =~ s/(["'<>()])/ sprintf "%%%0x", ord $1 /eg;

	my @commandline = (
	    '/home/mitch/bin/youtube-dl',
	    '--flat-playlist',
	    '--skip-playlist-after-errors', '1',
	    '--playlist-items', '1:1',
	    '--no-playlist',
	    '--retries', '1',
	    '--get-title',
	    $url
	    );
	
	# get title
	open (my $fh, '-|', @commandline) or write_error($witem, "error running \"@commandline\": $!"), next;
	my $title = <$fh>;
	close $fh;

	chomp $title;
	$title =~ s/%/%%/g;
	write_title($witem, $title);

	$count++;
	
	if ($count > $maxcount) {
	    write_error($witem, "too many iterations in youtube-title.pl");
	    last;
	}
    }

}
