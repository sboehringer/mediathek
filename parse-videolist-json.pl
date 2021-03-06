#!/usr/bin/env perl
#
#Sat Jan  3 21:11:54 CET 2015

# Do not perform full JSON parsing to avoid RAM load
# rely on per line structure of video list
# Much like the xml files the json file is not well designed and can easily break anyway
# No effort is made therefore to achieve a robust solution

use TempFileNames;
use Set;
use Data::Dumper;
use POSIX qw{ceil};

# default options
#	v1: json file format <= 2018
#	v2: json file format > 2018
$main::d = { triggerPrefix => '', sep => ':<>:', parse => '-', version => 'v2' };
# options
$main::o = [ '+parse=s', 'sep=s', 'version=s' ];
$main::usage = '';
$main::helpText = <<HELP_TEXT.$TempFileNames::GeneralHelp;
	Parse JSON file to pseuso-csv
	Usage:
	xzcat file-list | parse-videolist-json.pl --parse - > output
	parse-videolist-json.pl --parse file

HELP_TEXT

my $stringREraw='(?:(?:[_\/\-a-zA-Z0-9.]+)|(?:\"(?:(?:\\\\.)*(?:[^"\\\\]+(?:\\\\.)*)*)\"))';
my $stringRE='(?:([_\/\-a-zA-Z0-9.]+)|(?:\"((?:\\\\.)*(?:[^"\\\\]+(?:\\\\.)*)*)\"))';
sub dequoteBackslash { my ($str) = @_; $str =~ s/\\(.)/$1/g; return $str; }
sub extractString {
	dequoteBackslash(join('', $_[0] =~ m{$stringRE}so))
}
sub jsonArray { my ($s) = @_;
	my @cols = map { extractString($_) } ($s =~ m{(?:($stringREraw)(?:\s*,\s*)?)}sog);
	return @cols;
}
# JSON as of 20.1.2019
#"Filmliste":["Sender","Thema","Titel","Datum","Zeit","Dauer","Größe [MB]","Beschreibung","Url","Website","Url Untertitel","Url RTMP","Url Klein","Url RTMP Klein","Url HD","Url RTMP HD","DatumL","Url History","Geo","neu"],"

my @colSel = ("Sender", "Thema", "Titel", "Datum", "Zeit", "Dauer", "Url HD", "Url", "Website" );
my @colDf = ("channel", "topic", "title", "date", "time", "duration", "url_hd", "url", "homepage" );
my @dbkeys = ('channel', 'topic', 'title', 'date', 'duration', 'url', 'homepage');
my $readLength = firstDef($ENV{PARSE_VIDEOLIST_JSON_READLENGTH}, 8192);
my %re = (
	v1 => {
		header => '(?:.*)Filmliste"\s*:\s*\[("Sender"(?:[^[]*|\[.*?\])*)\](.*)',
		element => '"X":\[((?:[^[]*|\[.*?\])*?)\](.*)'
	},
	v2 => {
		header => '"Filmliste":\[("Sender"(?:[^[]*|\[.*?\])*)\](.*)',
		element => '"X":\[((?:[^[]*|\[.*?\])*?)\](.*)'
	}
);
sub parse { my ($o) =  @_;
	my $fh = ($o->{parse} eq '-')? IO::Handle->new_from_fd(STDIN, "r"): IO::File->new("< $o->{parse}");
	die "could not open:$o->{parse}" if (!defined($fh));
	my @colIndeces;

	my ($this, $prev, $i, $buf, $readBf, $m, $r) = ({}, {}, 0);
	$fh->read($buf, $readLength);
	# determine indeces of relevant columns
	die "No header found" if (!($buf =~ m/$re{$o->{version}}{header}/));
	Log("Column identifiers: $1", 5);
	@colIndeces = which_indeces([@colSel], [jsonArray($1)]);
	$fh->read($readBf, $readLength);
	$buf = $2. $readBf;

	while ($buf =~ m{"X":}so) {
		if (length($buf) < $readLength) {
			$fh->read($readBf, $readLength);
			$buf .= $readBf;
		}
		($m, $buf) = ($buf =~ m{$re{$o->{version}}{element}}so);
		#print("Match: ". $m. "\nBuffer: ". $buf. "\n");

		#my @cols = map { s/\n/ /sog } ($1 =~ m{(?:($stringRE)(?:\s*,\s*)?)}sog);
		my $this = makeHash(\@colDf, [(jsonArray($m))[@colIndeces]]);

		# <p> field carry over
		$this->{channel} = $prev->{channel} if ($this->{channel} eq '');
		$this ->{topic} = $prev->{topic} if ($this->{topic} eq '');
		$prev = $this;

		# <p> skip bogus entries
		next if (!defined($this->{date}) || $this->{date} eq '' || $this->{time} eq '');
		$this->{date} = join('-', reverse(split(/\./, $this->{date}))). ' '. $this->{time};
		next if (!defined($this->{date}) || $this->{date} eq '');

		$this->{duration} = ceil(sum(multiply(split(/\:/, $this->{duration}), (60, 1, 1/60))))
			if (defined($this->{duration}));
		# <!> url_hd interpretation unclear
		#if ($this->{url_hd} ne '') {
		#	# url_hd only contains 
		#	$this->{url} = firstTrue($this->{url_hd}, $this->{url});
		#}

		print join($o->{sep}, @{$this}{@dbkeys}). "\n";
		Log(sprintf("Parsed #%3de3", $i/1e3), 5) if (!(++$i % 1e3));
	}
	$fh->close();
}

#main $#ARGV @ARGV %ENV
	#initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
exit(0);
