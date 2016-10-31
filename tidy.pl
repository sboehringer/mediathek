#!/usr/bin/perl
#
#Sun Oct 30 22:33:48 CET 2016

use TempFileNames;
use Data::Dumper;
use Set;

# default options
$main::d = { triggerPrefix => 'do', callTriggers => 0, quiet => 1 };
# options
$main::o = ['simple', 'filter|f=s', 'onOff!', 'credentials', '+trigger=s', '+trigger1'];
$main::usage = '';
$main::helpText = <<HELP_TEXT.$TempFileNames::GeneralHelp;
	there is no specific help.

HELP_TEXT

sub detectUndefinedTagsRaw { my ($f, $tags, $c) = @_;
	my $cmd = "tidy -errors --quote-nbsp no -asxml -utf8 "
		. prefix(join(',', @$tags), '--new-inline-tags '). " $f";
	my $r = System($cmd, 4, undef, { returnStderr => 'YES', returnStdout => 'YES' });
	my @e = ($r->{error} =~ m{Error:\s(.*)}mog);
	Log("Errors:\n". join("\n", @e), 5);
	my @tags = unique(map { m{<(.*)?> is not recognized}; $1 } @e);
	Log("Tags: ". join(" ", @tags), 5);
	return { exit => !!@e, tags => [@tags] };
}

sub detectUndefinedTags { my ($f, $c) = @_;
	my @tags;
	my $Nmax = firstDef($c->{Nmax}, 10);
	my $r;
	do {
		$r = detectUndefinedTagsRaw($f, [@tags], $c);
		push(@tags, @{$r->{tags}});
	} while ($r->{exit} && --$Nmax > 0);
	return @tags;
}

sub tidy { my ($c) = @_;
	my $tf = slurpToTemp();
	my @inlinetags = detectUndefinedTags($tf, $c);
	my $quiet = $c->{quiet}? '2>/dev/null': '';
	my $cmd = "tidy --quote-nbsp no -f /dev/null -asxml -utf8 "
		. prefix(join(',', @inlinetags), '--new-inline-tags '). " $tf $quiet";
	System($cmd, 4);
}

#main $#ARGV @ARGV %ENV
	initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
	tidy($c);
exit(0);
