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


# default options
$main::d = {
	config => 'mediathek.cfg',
	'updatedb' => \&update_db,
	createdb => \&create_db,
	dump => \&dump_db,
	search => \&search_db,
	addsearch => \&add_search,
	deletesearch => \&delete_search,
	autofetch => \&auto_fetch_db,
	fetch => \&fetch_from_db,
	prune => \&prune_db,
	dumpschema => \&dump_schema,
	location => "$ENV{HOME}/.local/share/applications/mediathek",
	serverUrl => 'http://zdfmediathk.sourceforge.net/update.xml',
	videolibrary => "$ENV{HOME}/Videos/Mediathek",
	keepForDays => 10,
	refreshServers => 30,
	refreshTvitems => 0,
};
# options
$main::o = [
];
$main::usage = '';
$main::helpText = <<HELP_TEXT.$TempFileNames::GeneralHelp;
	mediathek-worker.pl --createdb
	mediathek-worker.pl --dump
	mediathek-worker.pl --updatedb
	mediathek-worker.pl --fetchall
	mediathek-worker.pl --search query1 query2 ...
	mediathek-worker.pl --fetch query1 query2 ...
	mediathek-worker.pl --dumpschema
	mediathek-worker.pl --addsearch query1 query2 ...
	mediathek-worker.pl --deletesearch id1 ...
	mediathek-worker.pl --autosfetch

	Examples:
	# and
	mediathek-worker.pl --search 'topic:Tatort;channel:ARD;title:!Vorschau%'
	mediathek-worker.pl --addsearch 'channel:ARTE%;title:360%'
	# or
	mediathek-worker.pl --search 'topic:Tatort' 'channel:ARD'
	# permanently add search
	mediathek-worker.pl --addsearch 'topic:Tatort;channel:ARD;title:!Vorschau%'
	# list active searches
	mediathek-worker.pl --addsearch
	# delete search
	mediathek-worker.pl --deletesearch 1

HELP_TEXT

my $sqlitedb = <<DBSCHEMA;
	CREATE TABLE tv_item (
		id integer primary key,
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
		id integer primary key,
		expression text not null,
		UNIQUE(expression)
	);
	CREATE TABLE tv_recording (
		id integer primary key,
		recording integer REFERENCES tv_item(id),
		UNIQUE(recording)
	);
DBSCHEMA

my $dbfile = "$ENV{HOME}/tmp/test.sqlite";
my $dumpdir = "$ENV{HOME}/tmp/Schemas";

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
	return undef if (!@$urls);
	$o = tempFileName("/tmp/perl_tmp_$ENV{USER}/mediathek", '.bz2') if (!defined($o));
	return $o if (-e $o && -M $o < ($c{refetchAfter} || 0));	# time in days

	for (my $i = 0; $i < ($c{retries} || 5); $i++, sleep($c{sleep} || 3)) {
		my $no = $c{seq}? ($i % int(@$urls)): rand(int(@$urls));
		my $url = $urls->[$no];
		Log("Fetching $url --> $o", 4);
		my $response = getstore($url, $o);
		last if ($response == 200);
	}
	Log("Written to: $o", 5);
	return $o;
}

sub prune_db { my ($c) = @_;
	my $s = load_db($c);
	my $now = time();
	my $now_str = strftime("%Y-%m-%d %H:%M:%S", localtime($now));
	my $prune_str = strftime("%Y-%m-%d %H:%M:%S", localtime($now - $c->{keepForDays} * 86400));
	Log("Now: $now_str, pruning older than: $prune_str", 1);
	my $tv = $s->resultset('TvItem');
	my @r = $tv->search({ date => { '<' => $prune_str } });
	Log('About to delete '. int(@r). ' items.', 1);
	$tv->delete();
}

# <A> no proper quoting of csv output
sub update_db { my ($c, $xml) = @_;
	# <p> prune first
	prune_db($c);

	# <p> fetch new items
	my $serverList = meta_get([$c->{serverUrl}], "$c->{location}/servers.xml",
		refetchAfter => $c->{refreshServers});
	my $servers = "cat $serverList | xml sel -T -t -m //Download_Filme_1 -v . -n";
	Log($servers, 4);
	$xml = meta_get([split(/\n/, `$servers`)], "$c->{location}/database_raw.xml.bz2",
		refetchAfter => $c->{refreshTvitems})	# , seq => 1
		if (!defined($xml));
	my $sep = ':_:';
	my $cmd = 'cat '. qs($xml). ' | '
		.'bzcat | perl -pe "tr/\n/ /" | xml sel -T -t -m //X'
		." -v ./b -o $sep -v ./c -o $sep -v ./d -o $sep -v ./e -o $sep -v ./f -o $sep -v ./g -o $sep -o 'flvstreamer --resume ' -v ./i -n";
	my @keys = ('channel', 'topic', 'title', 'day', 'time', 'url', 'command');

	my $fh = IO::File->new("$cmd |");
	die "couldn't read '$xml'" if (!defined($fh));
	my @lines = map { substr($_, 0, -1) } (<$fh>);
	my $prev;

	my @dbkeys = ('channel', 'topic', 'title', 'date', 'url', 'command');
	my $s = load_db($c);
	my $tv = $s->resultset('TvItem');
	my $i = 0;
	my $now = time();
	for my $l (@lines) {
		if (!(++$i % 1e3)) {
			$tv->clear_cache();
			Log(sprintf("%3.1eth entry", $i), 3);
		}
		my $this = makeHash(\@keys, [split(/$sep/, $l)]);
		$this->{channel} = $prev->{channel} if ($this->{channel} eq '' && $prev->{channel} ne '');
		$this->{date} = join('-', reverse(split(/\./, $this->{day}))). ' '. $this->{time};
		$this->{topic} = $prev->{topic} if ($this->{topic} eq '' && $prev->{topic} ne '');
		#print join(",", @{$this}{@keys}). "\n";
		if ($this->{topic} eq 'Tatort') {
			print(Dumper($this));
		}
		$prev = $this;
		next if ($now - mktime(strptime($this->{date}, "%Y-%m-%d %H:%M:%S"))
			> $c->{keepForDays} * 86400);

		$tv->find_or_create(makeHash(\@dbkeys, [@{$this}{@dbkeys}]),
			{ key => 'channel_date_title_unique' });
	}
	$fh->close();

#	$tv->populate([\@dbkeys, @items]);
# # 	my $fh = 'readDatabaseFh';
# # 	open($fh, "$cmd |");
# # 		my @lines = (<$fh>);
# # 	close($fh);
}

my %TvTableDesc = ( parameters => { width => 79 },
	columns => {
		channel => { width => -7, format => '%*s' },
		date => { width => 19, format => '%*s' },
		title => { width => -50, format => '%*s' }
	},
	print => ['channel', 'date', 'title']
);
my %TvGrepDesc = ( parameters => { width => 79 },
	columns => {
		id => { width => 4, format => '%*s' },
		expression => { width => -70, format => '%*s' }
	},
	print => ['id', 'expression']
);

sub search { my ($c, @queries) = @_;
	my $s = load_db($c);

	my $tv_item = $s->resultset('TvItem');
	#$literature_item->populate([{ id => 21, name => 'item 1' }]);
	my @r = map { my $query = $_;
		my %terms = map { /([^:]+):(.*)/, ($1, $2) } split(/;/, $query);
		my %query = map { my ($k, $v, $not) = ($_, $terms{$_});
			($not, $v) = ($v =~ m{^([!]?)(.*)}sog);
			($k, { ($not? 'not like': 'like'), $v })
		} keys %terms;
		Log(Dumper(\%query), 5);
		my @items = $tv_item->search(\%query);
		@items
	} @queries;
	return @r;
}

sub search_db { my ($c, @queries) = @_;
	my @r = search($c, @queries);
	my $t = formatTable(\%TvTableDesc, \@r);
	print($t. "\n");
}

sub dateReformat { my ($date, $fmtIn, $fmtOut) = @_;
	return strftime($fmtOut, strptime($date, $fmtIn));
}

sub fetch_from_db { my ($c, @queries) = @_;
	my @r = search($c, @queries);
	for my $r (@r) {
		$r->fetchTo("$ENV{HOME}/Videos");
	}
}

sub add_search { my ($c, @queries) = @_;
	my $s = load_db($c);
	my $query = $s->resultset('TvGrep');
	for $q (@queries) { $query->create({expression => $q}); }
	my $t = formatTable(\%TvGrepDesc, [$query->all]);
	print($t. "\n");
}
sub delete_search { my ($c, @ids) = @_;
	my $s = load_db($c);
	my $query = $s->resultset('TvGrep');
	for my $id (@ids) { $query->search({id => $id})->delete(); }
	print(formatTable(\%TvGrepDesc, [$query->all]). "\n");
}

sub auto_fetch_db { my ($c, @queries) = @_;
	my $s = load_db($c);
	my @queries = map { $_->expression } $s->resultset('TvGrep')->all;
	my @r = search($c, @queries);
	for my $r (@r) {
		my $record = $s->resultset('TvRecording')->find_or_new({ recording => $r->id },
			{ key => 'recording_unique' });
		if (!$record->in_storage()) {
			my $ret = $r->fetchTo($c->{videolibrary});
			$record->insert() if (!$ret);
		}
	}
}

#main $#ARGV @ARGV %ENV
	#initLog(2);
	my $c = StartStandardScript($main::d, $main::o);
exit(0);
