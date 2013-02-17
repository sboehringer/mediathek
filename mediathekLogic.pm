#
#	mediathekLogic.pm
#Wed Feb  6 21:09:20 CET 2013

use MooseX::Declare;
use MooseX::NonMoose;
use MooseX::MarkAsMethods;

class My::Schema {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use POSIX qw(strftime mktime);
	use POSIX::strptime qw(strptime);

	method greetings() {
		Log("Hello world");
	}

	method prune(Num $keepForDays = 10) {
		my $now = time();
		my $now_str = strftime("%Y-%m-%d %H:%M:%S", localtime($now));
		my $prune_str = strftime("%Y-%m-%d %H:%M:%S",
			localtime($now - $keepForDays * 86400));
		Log("Now: $now_str, pruning older than: $prune_str", 1);
		my $tv = $self->resultset('TvItem');
		my @r = $tv->search({ date => { '<' => $prune_str } });
		Log('About to delete '. int(@r). ' items.', 1);
		$tv->delete();
	}

	# <A> no proper quoting of csv output
	method update($c, $xml) {
		$self->prune($c->{keepForDays});
		#
		# <p> xml parsing of new items
		#
		my $serverList = main::meta_get([$c->{serverUrl}], "$c->{location}/servers.xml",
			refetchAfter => $c->{refreshServers});
		my $servers = "cat $serverList | xml sel -T -t -m //Download_Filme_1 -v . -n";
		Log($servers, 4);
		$xml = main::meta_get([split(/\n/, `$servers`)], "$c->{location}/database_raw.xml.bz2",
			refetchAfter => $c->{refreshTvitems})	# , seq => 1
			if (!defined($xml));
		my $sep = ':_:';
		my $cmd = 'cat '. qs($xml). ' | '
			.'bzcat | perl -pe "tr/\n/ /" | xml sel -T -t -m //X'
			." -v ./b -o $sep -v ./c -o $sep -v ./d -o $sep -v ./e -o $sep -v ./f -o $sep -v ./g -o $sep -o 'flvstreamer --resume ' -v ./i -n";
		#
		# <p> database update
		#
		my @keys = ('channel', 'topic', 'title', 'day', 'time', 'url', 'command');
		my @dbkeys = ('channel', 'topic', 'title', 'date', 'url', 'command');
		my $fh = IO::File->new("$cmd |");
		die "couldn't read '$xml'" if (!defined($fh));
		my @lines = map { substr($_, 0, -1) } (<$fh>);
		my $prev;
		my $tv = $self->resultset('TvItem');
		my $i = 0;
		my $now = time();
		for my $l (@lines) {
			if (!(++$i % 1e3)) {
				$tv->clear_cache();
				Log(sprintf("%3.1eth entry", $i), 3);
			}
			my $this = makeHash(\@keys, [split(/$sep/, $l)]);
			$this->{channel} = $prev->{channel} if ($this->{channel} eq '' && $prev->{channel} ne '');
			next if ($this->{day} eq '' || $this->{time} eq '');
			$this->{date} = join('-', reverse(split(/\./, $this->{day}))). ' '. $this->{time};
			$this->{topic} = $prev->{topic} if ($this->{topic} eq '' && $prev->{topic} ne '');
			$prev = $this;
			next if ($this->{date} eq '' || $now - mktime(strptime($this->{date}, "%Y-%m-%d %H:%M:%S"))
				> $c->{keepForDays} * 86400);

			$tv->find_or_create(makeHash(\@dbkeys, [@{$this}{@dbkeys}]),
				{ key => 'channel_date_title_unique' });
		}
		$fh->close();
	}

	method add_search(@queries) {
		my $query = $self->resultset('TvGrep');
		for my $q (@queries) { $query->create({expression => $q}); }
		return $query->all;
	}

	method delete_search(@ids) {
		my $query = $self->resultset('TvGrep');
		for my $id (@ids) { $query->search({id => $id})->delete(); }
		return $query->all;
	}

	method search(@queries) {
		my $tv_item = $self->resultset('TvItem');
		my @r = map { my $query = $_;
			my %terms = map { /([^:]+):(.*)/, ($1, $2) } split(/;/, $query);
			my %query = map { my ($k, $v, $not) = ($_, $terms{$_});
				($not, $v) = ($v =~ m{^([!]?)(.*)}sog);
				($k, { ($not? 'not like': 'like'), $v })
			} keys %terms;
			main::Log(main::Dumper(\%query), 5);
			my @items = $tv_item->search(\%query);
			@items
		} @queries;
		return @r;
	}

	method fetch(Str $destination, @queries) {
		my @r = $self->search(@queries);
		for my $r (@r) {
			$r->fetchTo($destination);
		}
	}

	method auto_fetch(Str $destination) {
		my @queries = map { $_->expression } $self->resultset('TvGrep')->all;
		my @r = $self->search(@queries);
		for my $r (@r) {
			my $record = $self->resultset('TvRecording')->find_or_new({ recording => $r->id },
				{ key => 'recording_unique' });
			if (!$record->in_storage()) {
				my $ret = $r->fetchTo($destination);
				$record->insert() if (!$ret);
			}
		}
	}
}

class My::Schema::Result::TvItem {
	use TempFileNames;
	use Data::Dumper;

	# default format: day_title
	method fetchTo(Str $dest, Str $fmt = '%D_%T.flv') {
		my $destPath = $dest. '/'. mergeDictToString({
			'%T' => $self->title,
			'%D' => main::dateReformat($self->date, '%Y-%m-%d %H:%M:%S', '%Y-%m-%d')
		}, $fmt, { iterative => 'no' });
		Log("Fetching ". $self->title. " to ". $destPath, 1);
		Mkpath($dest, 5);
		my $command = $self->command();
		$command = 'flvstreamer --resume -r '. $self->url() if (length($command) < 32);
		return System($command. ' -o '. qs($destPath), 2);
	}
  __PACKAGE__->meta->make_immutable(inline_constructor => 0);
}
