#
#	mediathekLogic.pm
#Wed Feb  6 21:09:20 CET 2013

use MooseX::Declare;
use MooseX::NonMoose;
use MooseX::MarkAsMethods;

class My::Schema::Result::TvType::Youtube extends My::Schema::Result::TvType {
	use TempFileNames;
	use Data::Dumper;
	use utf8;

	method name() { return('youtube'); }
	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvType::Mediathek extends My::Schema::Result::TvType {
	use TempFileNames;
	use Data::Dumper;
	use utf8;

	method name() { return('mediathek'); }
	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvType {
	use base qw( DBIx::Class::Core );
	__PACKAGE__->load_components(qw{DynamicSubclass Core});
	__PACKAGE__->table('tv_type');
	__PACKAGE__->add_column(qw{id name});
	__PACKAGE__->typecast_map(name => {
		'youtube' => 'My::Schema::Result::TvType::Youtube',
		'mediathek' => 'My::Schema::Result::TvType::Mediathek'
	});

	method name() { return('generic'); }

	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use POSIX qw(strftime mktime ceil);
	use POSIX::strptime qw(strptime);
	use utf8;

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
		my $tv_rs = $tv->search_rs({ date => { '<' => $prune_str } });
		Log('About to delete '. $tv_rs->count. ' items.', 1);
		$tv_rs->delete();
	}

	method serverList($c) {
		# today, yesterday
		#my ($td, $yd) = (
		#	strftime("%d_%m", localtime(time())), strftime("%d_%m", localtime(time() - 86400))
		#);
		my $serverList = main::meta_get([$c->{serverUrl}], "$c->{location}/servers.xml",
			refetchAfter => $c->{refreshServers});
		#my $servers = "cat $serverList | xml sel -T -t -m //URL -v . -n | grep -E '_$td|_$yd'";
		my @serverList = split(/\n/, `cat $serverList | xml sel -T -t -m //URL -v . -n`);
		Log('SeverList fetch: '. join("\n", @serverList), 5);
		return @serverList;
	}

	method updateWithJson($c, $path) {
		#
		# <p> xml parsing of new items
		#
		$self->prune($c->{keepForDays});
		my $sep = ':<>:';	# as of parse-videolist-json.pl
		my $cmd = 'xzcat '. qs($path). ' | '. './parse-videolist-json.pl --parse -';
		#
		# <p> database update
		#
		# keys as of parse-videolist-json
		my @keys = ('channel', 'topic', 'title',  'day', 'time', 'duration', 'url_hd', 'url', 'homepage' );
		my @dbkeys = ('channel', 'topic', 'title', 'date', 'duration', 'url', 'homepage');
		my @skeys = ( 'channel', 'title' );	# search keys
		my $fh = IO::File->new("$cmd |");
		die "couldn't read '$path'" if (!defined($fh));
		my $prev = {};
		my $i = 0;
		my $icnt = 0;	# insert count
		my $now = time();
		while (my $l = <$fh>) {
			$l = substr($l, 0, -1);
			my $tv = $self->resultset('TvItem');
			if (!(++$i % 1e3)) {
				$self->resultset('TvItem')->clear_cache();
				Log(sprintf("%3de3th entry", $i/1e3), 4);
			}
			my $this = makeHash(\@keys, [split(/$sep/, $l)]);
			# <p> field carry over
			$this->{channel} = $prev->{channel} if ($this->{channel} eq '');
			$this->{topic} = $prev->{topic} if ($this->{topic} eq '');
			$prev = $this;
			# <p> skip bogus entries
			next if (!defined($this->{day}) || $this->{day} eq '' || $this->{time} eq '');
			$this->{date} = join('-', reverse(split(/\./, $this->{day}))). ' '. $this->{time};
			next if (!defined($this->{date})
				|| $this->{date} eq ''
				|| ($now - mktime(strptime($this->{date}, "%Y-%m-%d %H:%M:%S")))
					> $c->{keepForDays} * 86400);
			$this->{duration} = ceil(sum(multiply(split(/\:/, $this->{duration}), (60, 1, 1/60))))
				if (defined($this->{duration}));
			# <!> url_hd interpretation unclear
			#if ($this->{url_hd} ne '') {
			#	# url_hd only contains 
			#	$this->{url} = firstTrue($this->{url_hd}, $this->{url});
			#}

			#my @items = $tv->search(makeHash(\@skeys, [@{$this}{@skeys}]));
			#print 'exists: '. @items. "\n";
			my $item = makeHash(\@dbkeys, [@{$this}{@dbkeys}]);
			#my $i = $tv->find_or_create($item, { key => 'channel_date_title_unique' });
			my $item0 = $tv->find_or_new($item, { key => 'channel_date_title_unique' });
			if (!$item0->in_storage) {
				$icnt++;
				$item0->insert;
			}
			#my $i = $tv->find($item, { key => 'channel_date_title_unique' });
			#print "Defined: ". defined($i). "\n";
			#$i = $tv->create(makeHash(\@dbkeys, [@{$this}{@dbkeys}])) if (!defined($i));
			#print $this->{title}, " ", $this->{channel}, " ", $this->{date}, "\n";
			#Log($i->id. " ".$i->title. " ". $i->channel. " ". $i->date, 6);
		}
		$fh->close();
		Log(sprintf('Added %d items.', $icnt), 3);
	}
	# <A> no proper quoting of csv output
	method update($c, $xml) {
		if (defined($xml)) {
			$self->updateWithJson($c, $xml);
		} else {
			my @serverList = $self->serverList($c);
			$self->updateWithJson($c, main::meta_get([$serverList[0]],
				"$c->{location}/database-json.xz",
					refetchAfter => $c->{refreshTvitems}, seq => 0)) if (!$c->{refreshServersCount});
			Log("Number of servers to probe: $c->{refreshServersCount}", 5);
			for (my $i = 0; $i < $c->{refreshServersCount}; $i++) {
				$xml = main::meta_get([@serverList], "$c->{location}/database-json-$i.xz",
					refetchAfter => $c->{refreshTvitems}, seq => 0);
				$self->updateWithJson($c, $xml);
			}
		}
	}

	method add_search($queries, $destination = '', $xpath = '') {
		my $query = $self->resultset('TvGrep');
		for my $q (@$queries) { $query->create(
			{ main::hashPrune(%{{expression => $q, destination => $destination, xpath => $xpath}}) }
		); }
		return $query->all;
	}

	method delete_search($ids) {
		my $query = $self->resultset('TvGrep');
		for my $id (@$ids) { $query->search({id => $id})->delete(); }
		return $query->all;
	}

	method update_search($ids, $destination = '', $xpath = '') {
		my $query = $self->resultset('TvGrep');
		for my $id (@$ids) {
			$query->search({id => $id})->update(
				{ main::hashPrune(%{{ destination => $destination, xpath => $xpath }}) }
			);
		}
		return $query->all;
	}

	method search(@queries) {
		my $likeKeys = dictWithKeys(['channel', 'topic', 'title'], 1);
		my $tv_item = $self->resultset('TvItem');
		my @r = map { my $query = $_;
			my %terms = map { /([^:]+):(.*)/, ($1, $2) } split(/;/, $query);
			my %query = map { my ($k, $v, $modifier) = ($_, $terms{$_});
				($modifier, $v) = ($v =~ m{^([!<>]?)(.*)}sog);
				$k = 'time(date)' if ($k eq 'time');
				my $isCmp = defined(which($modifier, ['>', '<']));
				my @q = $likeKeys->{$k}
				? ($k, { ($modifier eq '!'? 'not like': 'like'), $v })
				: ($k, $isCmp? { $modifier, $v }: $v);
				@q
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

	method fetchSingle(Str $destination, Str $query, $urlextract, $tags) {
		my @r = $self->search( ($query) );
		for my $r (@r) {
			$r->fetchTo($destination, $urlextract, $tags);
		}
	}

	method auto_fetch(Str $destination, $tags) {
		if (!-e $destination) {
			Log(sprintf('VideoLibrary "%s" does not exist.', $destination), 4);
			return;
		}
		for my $q ( ($self->resultset('TvGrep')->all) ) {
			for my $r ( ($self->search($q->expression)) ) {
				my $record = $self->resultset('TvRecording')->find_or_new({ recording => $r->id },
					{ key => 'recording_unique' });
				if (!$record->in_storage()) {
					my $ret = $r->fetchTo($destination. '/'. $q->destination, $q->xpath, $tags);
					$record->insert() if (!$ret);
					Log(sprintf('Recording success [%s]: %d', $r->title, $ret), 5);
				} else {
					Log(sprintf('Recording [%s] already recorded.', $r->title), 5);
				}
			}
		}
	}

	method iterate_sources() {
		my @types = ($self->resultset('TvType')->all);
		Log("# TvTypes == ". int(@types), 5);
		for my $q ( @types ) {
			Log("Name: ". $q->name(), 5);
		}
	}
}

class My::Schema::Result::TvItem {
	use TempFileNames;
	use Data::Dumper;
	use utf8;

	my %templates = (
		rmtp => 'flvstreamer --resume -r URL -o OUTPUT',
		http => 'mplayer -nolirc URL -dumpstream -dumpfile OUTPUT'
	);
	method commandWithOutput(Str $destPath) {
		Log("URL: ". $self->url(), 2);
		my ($protocol) = ($self->url() =~ m{^([^:]+)://}sog);
		my $command = mergeDictToString({
			URL => $self->url,
			OUTPUT => qs($destPath)
		}, $templates{$protocol});
		#my $command = $self->command();
		#$command = '-r '. $self->url() if (length($command) < 16);
		return $command;
	}

	method annotation($xpath = '', $tags) {
		return '' if (!defined($xpath) || $xpath eq '');
		my $urlq = main::qs($self->homepage());
		my $xpathq = main::qs($xpath);
		my $urlcmd = "wget -qO- $urlq | "
			.'tidy --quote-nbsp no -f /dev/null -asxml -utf8 '
			.main::circumfix(join(',', defined($tags)? @$tags: ()), '--new-inline-tags ', ' | ')
			."xml sel -N w=http://www.w3.org/1999/xhtml -T -t -m $xpathq -v . -n | perl -pe 's/\n//g'";
		my $annotation = main::trimmStr(`$urlcmd`);
		Log("Annotation command: $urlcmd", 2);
		Log("Annotation: $annotation", 2);
		return $annotation;
	}

	# default format: day_title
	method fetchTo($dest, $xpath = '', $tags = [], $fmt = '%D_%T%U.%E') {
		my $destPath = $dest. '/'. mergeDictToString({
			'%T' => $self->title,
			'%D' => main::dateReformat($self->date, '%Y-%m-%d %H:%M:%S', '%Y-%m-%d'),
			'%E' => splitPathDict($self->url)->{extension},
			'%U' => defined($xpath)? main::prefix($self->annotation($xpath, $tags), '_'): ''
		}, $fmt, { iterative => 'no' });
		Log("Fetching ". $self->title. " to ". $destPath, 1);
		Mkpath($dest, 5);

		return System($self->commandWithOutput($destPath), 2);
	}

	__PACKAGE__->meta->make_immutable(inline_constructor => 0);
}
