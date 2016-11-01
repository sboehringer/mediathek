#!/usr/bin/perl
#
#Sun Oct 30 23:21:21 CET 2016

use TempFileNames;

# default options
$main::d = { value => '.', triggerPrefix => 'do', callTriggers => 0 };
# options
$main::o = ['tidy', 'match|m=s', 'value|v=s', 'wget=s', 'credentials', '+trigger=s', '+trigger1'];
$main::usage = '';
$main::helpText = <<HELP_TEXT.$TempFileNames::GeneralHelp;
	there is no specific help.

HELP_TEXT

sub xml { my ($c, @argv) = @_;
	my $xml = `which xmlstarlet 2>/dev/null` ne ''? 'xmlstarlet': 'xml';
	my $prefix = '';
	$prefix .= 'tidy.pl |' if ($c->{tidy});
	my $i = defined($c->{wget})? slurpPipeToTemp('wget -qO- '. qs($c->{wget})): slurpToTemp();
	my $postfix = " -v $c->{value} -n";
	my $cmd = "cat $i | $prefix $xml sel -N w=http://www.w3.org/1999/xhtml -T -t -m $c->{match} $postfix"; 
	System($cmd, 4);
}

#main $#ARGV @ARGV %ENV
	#initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
	xml($c, @ARGV);
exit(0);
