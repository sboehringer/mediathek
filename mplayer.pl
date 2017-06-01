#!/usr/bin/perl
#
#Tue May 30 22:18:04 CEST 2017;

use TempFileNames;
use Set;
use Data::Dumper;
use File::Slurp;

# default options
$main::d = { config => 'config.cfg', 'hello' => sub { print "hello world\n"; }, triggerPrefix => 'do',
	triggerDefault => undef, doReturn => 0, unlink => 1 };
# options
# mplayer -nolirc URL -dumpstream -dumpfile OUTPUT
$main::o = ['nolirc', 'dumpstream', 'dumpfile=s', 'unlink!'];
$main::usage = '';
$main::helpText = <<HELP_TEXT.$TempFileNames::GeneralHelp;
	mplayer.pl -nolirc file.3u8 -dumpstream -dumpfile a.out --dologonly --no-unlink

HELP_TEXT

#
#	<p> helpers
#

sub option2str { my ($c, $o) = @_;
	my ($n, $a) = ($o =~ m{([a-z][a-z0-9-_]+)(?:=(.))?}soi);
	return defined($c->{$n})? "-$n". ($a ne ''? ' '. qs($c->{$n}): ''): '';
}
sub options2str { my ($c, @o) = @_;
	return join(' ', map { option2str($c, $_) } @o);
}
my @mplayerOptions = ('nolirc', 'dumpstream', 'dumpfile=s');

#
#	<p> mplayer wrappers
#

sub mplayer_m3u { my ($c, $file) = @_;
	my $spM = splitPathDict($file);
	my @files = (grep { ! ($_ =~ m{^#}so) } read_file($file, chomp => 1));
	my @o = map { qs($_) }  map {
		my $i = $_;
		my $f = $files[$i];
		my $sp = splitPathDict($f);
		#my $cmd = sprintf('wget -o %s-%03d.%s '. qs($f), qs($spM->{base}), $i, $sp->{extension});
		my $fo =  sprintf('%s-%03d.%s', $spM->{base}, $i, $sp->{extension});
		my $options = options2str({%$c, dumpfile => $fo}, @mplayerOptions);
		my $cmd = "mplayer $options ". qs($f);
		System($cmd, 4);
		$fo		
	}  (0 .. $#files);
	my $cmd = 'mkvmerge -o '. qs($spM->{base}). '.mkv '. join(' + ', @o);
	System($cmd, 2);
	if ($c->{unlink}) {
		Log("Removing temp files.", 2);
	}
}

sub mplayer_default { my ($c, @args) = @_;
	my $cmd = 'mplayer '. options2str($c, @mplayerOptions). ' '. join(' ', map { qs($_) } @args);
	System($cmd, 2);
}

my %extensionDict = ( m3u => 'm3u', m3u8 => 'm3u' );
sub mplayer { my ($c, @args) = @_;
	my $file = $args[0];
	my $sp = splitPathDict($file);
	my $handler = 'mplayer_'. firstDef($extensionDict{$sp->{extension}}, 'default');
	$handler->($c, @args);
}

#main $#ARGV @ARGV %ENV
	#initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
	mplayer($c, @ARGV);
exit(0);
