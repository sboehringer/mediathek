#!/usr/bin/perl
#
#Sat Jan  3 21:11:54 CET 2015

# Do not perform full JSON parsing to avoid RAM load
# rely on per line structure of video list
# Much like the xml files the json file is not well designed and can easily break anyway
# No effort is made therefore to achieve a robust solution

use TempFileNames;
use Set;

# default options
$main::d = { triggerPrefix => '', sep => ':*_*:', parse => '-' };
# options
$main::o = [ '+parse=s', 'sep=s' ];
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
}

my @colSel = ("Sender", "Thema", "Titel", "Datum", "Zeit", "Dauer", "Url_HD", "Url" );
sub parse { my ($o) = @_;
	my $fh = ($o->{parse} eq '-')? IO::Handle->new_from_fd(STDIN, "r"): IO::File->new("< $o->{parse}");
	die "could not open:$o->{parse}" if (!defined($fh));
	my @colIndeces;

	while (<$fh>) {
		# determine indeces of relevant columns
		# <!> rely on last line to contain column names
		if (/^\s*"Filmliste"\s*:\s*\[(.*)\]/) {
			@colIndeces = which_indeces([@colSel], [jsonArray($1)]);
			next;
		}
		next if (!/^\s*"X"\s*:\s*\[(.*)\]/);
		#my @cols = map { s/\n/ /sog } ($1 =~ m{(?:($stringRE)(?:\s*,\s*)?)}sog);
		print join($o->{sep}, (jsonArray($1))[@colIndeces]). "\n";
	}
	$fh->close();
}

#main $#ARGV @ARGV %ENV
	#initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
exit(0);
