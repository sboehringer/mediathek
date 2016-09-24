#!/usr/bin/perl
#
#Sat Sep 24 22:30:07 CEST 2016

use TempFileNames;
use Set;
use IO::File;

# default options
$main::d = { triggerPrefix => '', sep => ':<>:', parse => '-' };
# options
$main::o = [ '+parse=s', 'sep=s' ];
$main::usage = '';
$main::helpText = <<HELP_TEXT.$TempFileNames::GeneralHelp;
	Parse JSON file to pseuso-csv
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
sub fetch { my ($o, $url) = @_;
	my $fh = IO::File->new('youtube-dl -e -g $url |')
	die "could not open: $url" if (!defined($fh));
	my @colIndeces;

	while (<$fh>) {
		print $_;
	}
	$fh->close();
}

#main $#ARGV @ARGV %ENV
	#initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
exit(0);
