#!/usr/bin/perl
#
#Sat Sep 24 22:30:07 CEST 2016

#./fetch-parse-youtube.pl --fetch https://www.youtube.com/channel/UCKQ_j0fm3NioMRE3i-1CryA
#youtube-dl -j --get-title --flat-playlist https://www.youtube.com/channel/UCKQ_j0fm3NioMRE3i-1CryA

use TempFileNames;
use Set;
use IO::All;
use Data::Dumper;

# default options
$main::d = { triggerPrefix => '', sep => ':<>:', parse => '-',
	cache => firstDef($ENV{MEDIATHEK_YOUTUBE_CACHE},
		"$ENV{HOME}/.local/share/applications/mediathek/youtube-"),
	minOverlap => 1,
	Nmax => 3
};
# options
$main::o = [ '+fetch=s', 'sep=s' ];
$main::usage = '';
$main::helpText = <<HELP_TEXT.$TempFileNames::GeneralHelp;
	fetch youtube playlist/channel, parse

	Usage:
	xzcat file-list | parse-videolist-json.pl --parse - > output
	fetch-parse.youtube.pl --fetch channel/list

HELP_TEXT

my $stringREraw='(?:(?:[_\/\-a-zA-Z0-9.]+)|(?:\"(?:(?:\\\\.)*(?:[^"\\\\]+(?:\\\\.)*)*)\"))';
my $stringRE='(?:([_\/\-a-zA-Z0-9.]+)|(?:\"((?:\\\\.)*(?:[^"\\\\]+(?:\\\\.)*)*)\"))';
my $keyValueRE = "$stringRE\s*:\s*$stringRE";
sub dequoteBackslash { my ($str) = @_; $str =~ s/\\(.)/$1/g; return $str; }
sub extractString {
	dequoteBackslash(join('', $_[0] =~ m{$stringRE}so))
}
sub Chop { substr($_[0], 0, -1) }

my @colSel = ('id', 'channel', 'title' );
my $prefixChannel = 'https://www.youtube.com/channel/';
my $prefix = 'https://www.youtube.com/';
sub fetch { my ($o) = @_;
	my $url = $o->{fetch};
	#my $channel = splitPathDict($url)->{file};
	my $channel = (substr($url, 0, length($prefixChannel)) eq $prefixChannel)
		? substr($url, length($prefixChannel)): substr($url, length($prefix) - 1);
	my $cmd = "youtube-dl -j --get-title --flat-playlist $url";
	my $r = System($cmd, 2, undef, { returnStdout => 'YES' } );
	my @lines = split("\n", $r->{output});

	foreach my $l (@lines) {
		my %el = (grep { $_ ne '' } ($l =~ m[$stringRE]sg), channel => $channel);
		#print(Dumper(\%el));
		print join($o->{sep}, @el{@colSel}), "\n";
	}
}

#main $#ARGV @ARGV %ENV
	#initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
exit(0);
