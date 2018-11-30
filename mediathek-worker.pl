#!/usr/bin/env perl
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
use PropertyList;

# default options
$main::d = {
	config => 'mediathek.cfg', configPaths => [ $ENV{MEDIATHEK_CONFIG} ],
	location => firstDef($ENV{MEDIATHEK_DB}, "$ENV{HOME}/.local/share/applications/mediathek"),
	videolibrary => firstDef($ENV{MEDIATHEK_LIBRARY}, "$ENV{HOME}/Videos/Mediathek"),
	itemTable => 'default', searchTable => 'default', triggerPrefix => 'db',
	type => 'mediathek',

	Nfetch => 20, doRefetch => 0,
};
# options
$main::o = [
	'destination=s', 'urlextract=s', 'itemTable=s', 'searchTable=s', 'type=s',
	'Nfetch=s', 'fetchParameters=s',
	'+createdb', '+updatedb',
	'+search', '+addsearch', '+deletesearch', '+updatesearch', '+fetch', '+autofetch',
	'+dump', '+dumpschema', '+printconfig', '+serverlist', '+prune',
	'+iteratesources=s'
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
	mediathek-worker.pl --updatesearch id1 ... --destination destFolder
	mediathek-worker.pl --autofetch
	# urlextract option allows to fetch additional annotation from the movie url
	#	to be added to the file name. Extraction is done using an XPath exprssion
	mediathek-worker.pl --fetch query1 --urlextract XPath-expression

	Examples:
	# and
	mediathek-worker.pl --addsearch 'topic:Tatort;channel:ARD;title:!Vorschau%' \
		--destination Tatort
	mediathek-worker.pl --addsearch 'channel:ARTE%;title:360%'
	mediathek-worker.pl --addsearch 'channel:ARTE.DE;title:Reiseporträts'
	# or
	mediathek-worker.pl --search 'topic:Tatort' 'channel:ARD'
	# list search results with alternate table layout (as defined in config; see wiki)
	mediathek-worker.pl --search 'topic:Tatort' --itemTable wide
	# permanently add search
	mediathek-worker.pl --addsearch 'topic:Tatort;channel:ARD;title:!Vorschau%'
	# list active searches
	mediathek-worker.pl --addsearch
	# list active searches with alternate table layout (as defined in config; see wiki)
	mediathek-worker.pl --addsearch --searchTable xpath
	# delete search
	mediathek-worker.pl --deletesearch 1
	# update download destination
	mediathek-worker.pl --updatesearch 1 --destination Sandmännchen
	# fetch name from show homepage and add to file name
	mediathek-worker.pl --fetch --urlextract '//_:h2[@class="text-thin mb-20"]' 
	# show homepage scraping for autofetches
	mediathek-worker.pl --addsearch 'channel:ARTE%;title:360%;time:08:00:00' --destination Geo --urlextract '//_:h2[@class="text-thin mb-20"]'

	Debugging functions:
	mediathek-worker.pl --dump
	mediathek-worker.pl --dumpschema

HELP_TEXT

my $parsMediathek = stringFromProperty({
	serverUrl => 'http://zdfmediathk.sourceforge.net/update-json.xml',
	keepForDays => 10,
	refreshServers => 0,
	refreshServersCount => 1,
});
my $sqlitedb = <<"DBSCHEMA";
	CREATE TABLE tv_item (
		id integer primary key autoincrement,
		channel text not null,
		topic text,
		title text not null,
		date date not null,
		url_hd text,
		url text,
		url_small text,
		duration integer,
		homepage text,
		type integer REFERENCES tv_type(id) not null,
		UNIQUE(channel, date, title, type),
		UNIQUE(url)
	);
	CREATE INDEX tv_item_idx ON tv_item (channel, topic, title, date);
	CREATE INDEX tv_item_topic_idx ON tv_item (topic);
	CREATE INDEX tv_item_title_idx ON tv_item (title);
	CREATE INDEX tv_item_type_idx ON tv_item (type);
	CREATE TABLE tv_grep (
		id integer primary key autoincrement,
		expression text not null,
		destination text,
		-- extra information to complete a fetch
		witness text,
		type integer REFERENCES tv_type(id) not null,
		-- ALTER TABLE tv_grep ADD COLUMN destination text;
		UNIQUE(type, expression, witness)
	);
	CREATE INDEX tv_grep_type_idx ON tv_grep (type);
	CREATE TABLE tv_recording (
		id integer primary key autoincrement,
		recording integer REFERENCES tv_item(id),
		UNIQUE(recording)
	);
	CREATE INDEX tv_recording_recording_idx ON tv_recording (recording);
	CREATE TABLE tv_type (
		id integer primary key autoincrement,
		name text not null,
		parameters text,
		UNIQUE(name)
	);
	INSERT INTO tv_type (name, parameters) values ('mediathek', '$parsMediathek');
	INSERT INTO tv_type (name, parameters) values ('youtube', '{}');
DBSCHEMA

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
		'type.name' => { width => -10, format => '%*s', rename => 'type', keyPath => 'type.name' },
		expression => { width => -45, format => '%*s' },
		destination => { width => -15, format => '%*s' },
		xpath => { width => -10, format => '%*s' },
	},
	print => ['id', 'expression', 'destination', 'xpath' ]
);

sub instantiate_db { my ($c) = @_;
	my $dbfile = "$c->{location}/mediathek.db";
	return if (-e $dbfile);
	System("mkdir --parents $c->{location} ", 2);
	System("echo ". qs($sqlitedb). "'\n.quit' | sqlite3 $dbfile", 3);
	#my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", '', '');
	#my $sth = $dbh->prepare($sqlitedb);
	#$sth->execute();
}

sub dbDumpschema { my ($c) = @_;
	my $dbfile = "$c->{location}/mediathek.db";
	# DBIx schema
	my $schemadir = "$c->{location}/schema";
	Log("Dump dir: $schemadir");
	make_schema_at('My::Schema',
		{ debug => 1, dump_directory => $schemadir },
		[ "dbi:SQLite:dbname=$dbfile", '', '']
	);
}

sub dbCreatedb { my ($c) = @_;
	instantiate_db($c);
	dbDumpschema($c);
}

sub dbPrintconfig { my ($c) = @_;
	print(Dumper($c));
}

sub dbServerlist { my ($c) = @_;
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

sub dbDump { my ($c) = @_;
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

sub dbPrune { my ($c) = @_;
	load_db($c)->prune();
}
sub dbUpdatedb { my ($c, $xml) = @_;
	load_db($c)->update($c, $c->{type});
}
sub dbAutofetch { my ($c) = @_;
	load_db($c)->auto_fetch($c, $c->{type});
}
sub dbSearch { my ($c, @queries) = @_;
	#my @r = load_db($c)->search(@queries);
	my @r = load_db($c)->search($c, $c->{type}, @queries);
	print(formatTable(firstDef($c->{itemTableFormatting}{$c->{itemTable}}, \%TvTableDesc), \@r). "\n");
}
sub witnessFromConfig { my ($c) = @_;
	my $wdict = dict2defined({
		defined($c->{fetchParameters})? %{propertyFromString('{'.$c->{fetchParameters}.'}')}: (),
		(urlextract => $c->{urlextract}) });
	return (%$wdict) == 0? undef: stringFromProperty($wdict);
}
sub dbFetch { my ($c, @queries) = @_;
	load_db($c)->fetchSingle($c, $c->{type}, $queries[0], witnessFromConfig($c));
}
sub dbAddsearch { my ($c, @queries) = @_;
	my @searches = load_db($c)->add_search([@queries], $c->{destination}, witnessFromConfig($c), $c->{type});
	print(formatTable(firstDef($c->{searchTableFormatting}{$c->{searchTable}}, \%TvGrepDesc),
		[@searches]). "\n");
}
sub dbDeletesearch { my ($c, @ids) = @_;
	my @searches = load_db($c)->delete_search([@ids]);
	print(formatTable(firstDef($c->{searchTableFormatting}{$c->{searchTable}}, \%TvGrepDesc),
		[@searches]). "\n");
}
sub dbUpdatesearch { my ($c, @ids) = @_;
	my @searches = load_db($c)->update_search([@ids], $c->{destination}, witnessFromConfig($c));
	print(formatTable(firstDef($c->{searchTableFormatting}{$c->{searchTable}}, \%TvGrepDesc),
		[@searches]). "\n");
}

sub dbIteratesources { my ($c) = @_;
	Log('Iterate sources', 2);
	load_db($c)->iterate_sources($c->{iteratesources});	
}

#main $#ARGV @ARGV %ENV
	#initLog(5);
	my $c = StartStandardScript($main::d, $main::o);
exit(0);
