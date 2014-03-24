#!/usr/bin/perl
#
#Tue Jan  1 16:21:33 CET 2013

use TempFileNames;
use Set;
use Data::Dumper;
use DBI;
use DBIx::Class::Schema::Loader qw(make_schema_at);
use Module::Load;
use LWP::Simple;
use POSIX qw(strftime mktime);
use POSIX::strptime qw(strptime);
use utf8;


# default options
$main::d = {
	config => 'mediathek.cfg',
	'updatedb' => \&update_db,
	createdb => \&create_db,
	printconfig => \&print_config,
	dump => \&dump_db,
	search => \&search_db,
	addsearch => \&add_search,
	deletesearch => \&delete_search,
	updatesearch => \&update_search,
	autofetch => \&auto_fetch_db,
	fetch => \&fetch_from_db,
	prune => \&prune_db,
	dumpschema => \&dump_schema,
	serverlist => \&serverList,
	location => "$ENV{HOME}/.local/share/applications/mediathek",
	serverUrl => 'http://zdfmediathk.sourceforge.net/update.xml',
	videolibrary => "$ENV{HOME}/Videos/Mediathek",
	keepForDays => 10,
	refreshServers => 0,
	refreshServersCount => 2,
	refreshTvitems => 0,
};
# options
$main::o = [
	'destination=s'
];
$main::usage = '';
$main::helpText = <<'HELP_TEXT'.$TempFileNames::GeneralHelp;
	mediathek-worker.pl --createdb
	mediathek-worker.pl --updatedb
	mediathek-worker.pl --search query1 query2 ...
	mediathek-worker.pl --fetch query1 query2 ...
	mediathek-worker.pl --addsearch query1 query2 ...
	mediathek-worker.pl --addsearch query1 query2 ... --destination destFolder
	mediathek-worker.pl --deletesearch id1 ...
	mediathek-worker.pl --updateearch id1 ... --destination destFolder
	mediathek-worker.pl --autofetch

	Examples:
	# and
	mediathek-worker.pl --addsearch 'topic:Tatort;channel:ARD;title:!Vorschau%' \
		--destination Tatort
	mediathek-worker.pl --addsearch 'channel:ARTE%;title:360%'
	mediathek-worker.pl --addsearch 'channel:ARTE.DE;title:Reiseporträts'
	# or
	mediathek-worker.pl --search 'topic:Tatort' 'channel:ARD'
	# permanently add search
	mediathek-worker.pl --addsearch 'topic:Tatort;channel:ARD;title:!Vorschau%'
	# list active searches
	mediathek-worker.pl --addsearch
	# delete search
	mediathek-worker.pl --deletesearch 1
	# update download destination
	mediathek-worker.pl --updatesearch 1 --destination Sandmännchen

	Debugging functions:
	mediathek-worker.pl --dump
	mediathek-worker.pl --dumpschema

HELP_TEXT

my $sqlitedb = <<DBSCHEMA;
	CREATE TABLE tv_item (
		id integer primary key autoincrement,
		channel text not null,
		topic text,
		title text not null,
		date date not null,
		url text,
		command text,
		UNIQUE(channel, date, title)
	);
	CREATE INDEX tv_item_idx ON tv_item (channel, topic, title, date);
	CREATE INDEX tv_item_topic_idx ON tv_item (topic);
	CREATE INDEX tv_item_title_idx ON tv_item (title);
	CREATE TABLE tv_grep (
		id integer primary key autoincrement,
		expression text not null,
		destination text,
		-- ALTER TABLE tv_grep ADD COLUMN destination text;
		UNIQUE(expression)
	);
	CREATE TABLE tv_recording (
		id integer primary key autoincrement,
		recording integer REFERENCES tv_item(id),
		UNIQUE(recording)
	);
DBSCHEMA

sub instantiate_db { my ($c) = @_;
	my $dbfile = "$c->{location}/mediathek.db";
	return if (-e $dbfile);
	System("mkdir --parents $c->{location} ; echo '$sqlitedb\n.quit' | sqlite3 $dbfile", 2);
	#my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '');
	#my $sth = $dbh->prepare($sqlitedb);
	#$sth->execute();
}

sub dump_schema { my ($c) = @_;
	my $dbfile = "$c->{location}/mediathek.db";
	# DBIx schema
	my $schemadir = "$c->{location}/schema";
	Log("Dump dir: $schemadir");
	make_schema_at('My::Schema',
		{ debug => 1, dump_directory => $schemadir },
		[ "dbi:SQLite:dbname=$dbfile", '', '']
	);
}

sub create_db { my ($c) = @_;
	instantiate_db($c);
	dump_schema($c);
}

sub print_config { my ($c) = @_;
	print(Dumper($c));
}

sub serverList { my ($c) = @_;
	my @servers = load_db($c)->serverList($c);
	print(Dumper([@servers]));
}

sub load_db { my ($c) = @_;
	my $dbfile = "$c->{location}/mediathek.db";
	my $schemadir = "$c->{location}/schema";
	unshift(@INC, $schemadir);
	load('My::Schema');
	load('mediathekLogic');
	my $schema = My::Schema->connect("dbi:SQLite:dbname=$dbfile", '', '');
	return $schema;
}

sub dump_db { my ($c) = @_;
	my $s = load_db($c);

	my $tv_item = $s->resultset('TvItem');
	#$literature_item->populate([{ id => 21, name => 'item 1' }]);
	my @items = $tv_item->search({});
	print(Dumper([map { $_->id() } @items]));
}

sub meta_get { my ($urls, $o, %c) = @_;
	my $total = int(@$urls);
	return undef if (!$total);
	%c = (seq => 0, sleep => 5, retries => 5, %c);
	$o = tempFileName("/tmp/perl_tmp_$ENV{USER}/mediathek", '.bz2') if (!defined($o));
	return $o if (-e $o && -M $o < ($c{refetchAfter} || 0));	# time in days

	for (my $i = 0; $i < ($c{retries} || 5); $i++, sleep($c{sleep})) {
		my $no = $c{seq}? ($i % int(@$urls)): int(rand($total));
		my $url = $urls->[$no];
		Log("Fetching $url --> $o [No: $no/$total]", 4);
		my $response = getstore($url, $o);
		last if ($response == 200);
	}
	Log("Written to: $o", 5);
	return $o;
}

sub prune_db { my ($c) = @_;
	load_db($c)->prune();
}

# <A> no proper quoting of csv output
sub update_db { my ($c, $xml) = @_;
	load_db($c)->update($c, $xml);
}

%main::TvTableDesc = ( parameters => { width => 79 },
	columns => {
		channel => { width => -7, format => '%*s' },
		date => { width => 19, format => '%*s' },
		title => { width => -50, format => '%*s' }
	},
	print => ['channel', 'date', 'title']
);
%main::TvGrepDesc = ( parameters => { width => 79 },
	columns => {
		id => { width => 4, format => '%*s' },
		expression => { width => -50, format => '%*s' },
		destination => { width => -20, format => '%*s' },
	},
	print => ['id', 'expression', 'destination' ]
);

sub dateReformat { my ($date, $fmtIn, $fmtOut) = @_;
	return strftime($fmtOut, strptime($date, $fmtIn));
}

sub search_db { my ($c, @queries) = @_;
	my @r = load_db($c)->search(@queries);
	print(formatTable(firstDef($c->{itemTableFormatting}, \%TvTableDesc), \@r). "\n");
}

sub fetch_from_db { my ($c, @queries) = @_;
	load_db($c)->fetch($c->{videolibrary}, @queries);
}

sub add_search { my ($c, @queries) = @_;
	my @searches = load_db($c)->add_search([@queries], $c->{destination});
	print(formatTable(firstDef($c->{searchTableFormatting}, \%TvGrepDesc), [@searches]). "\n");
}
sub delete_search { my ($c, @ids) = @_;
	my @searches = load_db($c)->delete_search([@ids]);
	print(formatTable(firstDef($c->{searchTableFormatting}, \%TvGrepDesc), [@searches]). "\n");
}
sub update_search { my ($c, @ids) = @_;
	my @searches = load_db($c)->update_search([@ids], , $c->{destination});
	print(formatTable(firstDef($c->{searchTableFormatting}, \%TvGrepDesc), [@searches]). "\n");
}

sub auto_fetch_db { my ($c) = @_;
	load_db($c)->auto_fetch($c->{videolibrary});
}

#main $#ARGV @ARGV %ENV
	#initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
exit(0);
