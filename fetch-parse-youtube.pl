#!/usr/bin/perl
#
#Sat Sep 24 22:30:07 CEST 2016

#./fetch-parse-youtube.pl --fetch https://www.youtube.com/channel/UCKQ_j0fm3NioMRE3i-1CryA

use TempFileNames;
use Set;
use IO::All;
use Data::Dumper;

# default options
$main::d = { triggerPrefix => '', sep => ':<>:', parse => '-',
	cache => firstDef($ENV{MEDIATHEK_YOUTUBE_CACHE},
		"$ENV{HOME}/.local/share/applications/mediathek/youtube-"),
	minOverlap => 1
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
sub dequoteBackslash { my ($str) = @_; $str =~ s/\\(.)/$1/g; return $str; }
sub extractString {
	dequoteBackslash(join('', $_[0] =~ m{$stringRE}so))
}
sub Chop { substr($_[0], 0, -1) }

sub fetch { my ($o) = @_;
	my $url = $o->{fetch};
	my $cmd = "youtube-dl -e -g $url";
	Log($cmd, 2);
	my $fh = io($cmd)->pipe;
	die "could not open: $url" if (!defined($fh));

	# <p> read cache
	my @data;
	my $overlap = 0;	# count of urls seen before
	my %urls;
	if (-e $o->{cache}) {
		my $csv = readCsv($o->{cache});
		@data = map { makeHash($csv->{factors}, $_) } @{$csv->{data}};
		%cache = %{dictWithKeys([map { $_->{title} } @data])};
	}
	print(Dumper(\%cache));

	# <p> iterate list (newest -> oldest by assumption)
	for (my $i = 0; my $t = $fh->getline; $i++) {
		# <!> youtube-dl prints url twise
		my ($u, $u2) = ($fh->getline, $fh->getline);
		print "Title: $t";
		my $el = { title => Chop($t), url => Chop($u) };
		if (defined($cache{$el->{title}})) {
			# url is dynamically generated and differs between time points
			$overlap++;
			Log("Title seen before [#:$overlap].", 3);
			last if ($overlap >= $o->{minOverlap});
		} else {
			push(@data, $el);
		}
	}
	$fh->close();
	print(Dumper([@data]));
	writeCsv({ data => [@data] }, $o->{cache});
}

#main $#ARGV @ARGV %ENV
	#initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
exit(0);
