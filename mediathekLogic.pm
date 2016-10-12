#
#	mediathekLogic.pm
#Wed Feb  6 21:09:20 CET 2013

use MooseX::Declare;
use MooseX::NonMoose;
use MooseX::MarkAsMethods;

class My::Schema::Result::TvType {
	use base qw{ DBIx::Class::Core };
	__PACKAGE__->load_components(qw{DynamicSubclass Core});
	__PACKAGE__->table('tv_type');
	__PACKAGE__->add_column(qw{id name parameters});
	__PACKAGE__->typecast_map(name => {
		'youtube' => 'My::Schema::Result::TvType::Youtube',
		'mediathek' => 'My::Schema::Result::TvType::Mediathek'
	});

	method name() { return('generic'); }

	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvType::Base extends My::Schema::Result::TvType {
	use TempFileNames;
	use Data::Dumper;
	use Set;
	use utf8;
	use PropertyList;

	has 'pars' => ( isa => 'HashRef', is => 'rw', lazy => 1, builder => 'builderPars' );

	method builderPars() {
		my $dict = propertyFromString($self->parameters());
		return $dict;
	}
	method setParameters(HashRef $newPars) { $self->pars({ %{$self->pars}, %$newPars }); }
	method par(Str $key) { return $self->pars()->{$key}; }
	method schema() { return $self->result_source->schema; }
	method resultset(Str $name) { return $self->schema->resultset($name); }

	method search($queries, $extraTerms) {
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
			my %queryF = (%query, type => $self->id, defined($extraTerms)? %$extraTerms: {});
			Log(Dumper(\%query), 5);
print(Dumper(\%queryF));
			my @items = $tv_item->search({ %queryF });
			@items
		} @$queries;
		return @r;
	}

	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvType::Youtube extends My::Schema::Result::TvType::Base {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use utf8;
	use POSIX qw{strftime};
	__PACKAGE__->add_column(qw{id name parameters});

	method fetch() { Log('fetch: youtube'); }
	method updateChannel($channel) {
		my $sep = ':<>:';	# fetch-parse-youtube.pl
		my $cmd = './fetch-parse-youtube.pl --fetch https://www.youtube.com/channel/'. $channel->witness;
		#
		# <p> database update
		#
		# keys as of fetch-parse-youtube; id -> url; date, type manually added
		my @keys = ( 'url', 'channel', 'title', 'date', 'type' );
		my $fh = IO::File->new("$cmd |");
		die "couldn't fetch channel list [$channel]" if (!defined($fh));
		my $icnt = 0;	# insert count
		my $now = time();
		my $tv = $self->resultset('TvItem');
		while (my $l = substr(<$fh>, 0, -1)) {
			my $item = main::makeHash(\@keys,
				[(split(/$sep/, $l), strftime('%Y-%m-%d %H:$M:%S', localtime($now)), $self->id)]);
			print $l;
			my $item0 = $tv->find_or_new($item, { key => 'url_unique' });
			$item0->insert, $icnt++ if (!$item0->in_storage);
		}
		Log("Youtube: $icnt items inserted.", 4);
	}
	method update() {
		Log("Updating youtube channels", 3);
		my @channels = $self->resultset('TvGrep')->search( { type => $self->id } )->all;
		for my $q ( @channels ) {
			Log("Fetching channel: ". $q->witness, 3);
			$self->updateChannel($q);
		}
	}
	method auto_fetch() {
		my @channels = $self->resultset('TvGrep')->search( { type => $self->id } )->all;
		for my $q ( @channels ) {
			Log("Fetching channel: ". $q->witness, 3);
			my @items = $self->search([$q->expression], { channel => $q->witness });
print(Dumper([@items]));
		}
	}

	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvType::Mediathek extends My::Schema::Result::TvType::Base {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use utf8;
	use POSIX qw{mktime strftime};
	use POSIX::strptime qw(strptime);
	use warnings;

	__PACKAGE__->add_column(qw{id name parameters});

	method fetch() { Log('fetch: mediathek'); }

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

	method serverList() {
		my $serverList = main::meta_get([$self->par('serverUrl')], $self->par('location'). "/servers.xml",
			refetchAfter => $self->par('refreshServers'));
		#my $servers = "cat $serverList | xml sel -T -t -m //URL -v . -n | grep -E '_$td|_$yd'";
		my @serverList = split(/\n/, `cat $serverList | xml sel -T -t -m //URL -v . -n`);
		Log('SeverList fetch: '. join("\n", @serverList), 5);
		return @serverList;
	}

	method updateWithJson($path) {
		#
		# <p> xml parsing of new items
		#
		$self->prune($self->par('keepForDays'));
		my $sep = ':<>:';	# as of parse-videolist-json.pl
		my $cmd = 'xzcat '. qs($path). ' | '. './parse-videolist-json.pl --parse -';
		#
		# <p> database update
		#
		my @dbkeys = ('channel', 'topic', 'title', 'date', 'duration', 'url', 'homepage');
		my $fh = IO::File->new("$cmd |");
		die "couldn't read '$path'" if (!defined($fh));
		my ($i, $icnt) = (0, 0);
		my $now = time();
		my $tv = $self->resultset('TvItem');
		my $deadline = $now - $self->par('keepForDays') * 86400;
		while (my $l = substr(<$fh>, 0, -1)) {
			no warnings;
			if (!(++$i % 1e3)) {
				$self->resultset('TvItem')->clear_cache();
				Log(sprintf("%3de3th entry", $i/1e3), 4);
			}
			my $item = {%{makeHash(\@dbkeys, [split(/$sep/, $l)])}, type => $self-> id};
			my $itemTime = mktime(strptime($item->{date}, "%Y-%m-%d %H:%M:%S"));
			next if ($itemTime < $deadline);
			#my $i = $tv->find_or_create($item, { key => 'channel_date_title_unique' });
			#my $item0 = $tv->find_or_new($item, { key => 'channel_date_title_type_unique' });
			my $item0 = $tv->find_or_new($item);
			($item0->insert, $icnt++) if (!$item0->in_storage);
		}
		$fh->close();
		Log(sprintf('Added %d items.', $icnt), 3);
	}
	method update() {
		my @serverList = $self->serverList();
 		Log("Number of servers to probe: ". $self->par('refreshServersCount'), 5);

 		$self->updateWithJson(main::meta_get([$serverList[0]],
 			$self->par('location')."/database-json.xz",
 				refetchAfter => $self->par('refreshTvitems'), seq => 0))
 					if (!$self->par('refreshServersCount'));
 
		for (my $i = 0; $i < $self->par('refreshServersCount'); $i++) {
			my $dbFile = main::meta_get([@serverList], $self->par('location'). "/database-json-$i.xz",
				refetchAfter => $self->par('refreshTvitems'), seq => 0);
			$self->updateWithJson($dbFile);
		}
	}

	method auto_fetch() {
		Log("Autofetching mediathek...", 5);
		my $destination = $self->par('videolibrary');
		my $tags = $self->par('tidy-inline-tags');
		if (!-e $destination) {
			Log(sprintf('VideoLibrary "%s" does not exist.', $destination), 4);
			return;
		}
		for my $q ( ($self->resultset('TvGrep')->search({ type => $self->id })) ) {
			for my $r ( ($self->schema->search($q->expression)) ) {
				my $record = $self->resultset('TvRecording')->find_or_new({ recording => $r->id },
					{ key => 'recording_unique' });
				if (!$record->in_storage()) {
					my $ret = $r->fetchTo($destination. '/'. $q->destination, $q->witness, $tags);
					$record->insert() if (!$ret);
					Log(sprintf('Recording success [%s]: %d', $r->title, $ret), 5);
				} else {
					Log(sprintf('Recording [%s] already recorded.', $r->title), 5);
				}
			}
		}
	}
	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}


class My::Schema {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use POSIX qw(strftime mktime ceil);
	use utf8;

	method greetings() {
		Log("Hello world");
	}

	method iterate_sources(@methods) {
		if (ref($methods[0]) ne 'ARRAY') {
			@methods = ([@methods]);
		}
		my @types = ($self->resultset('TvType')->all);
		Log("# TvTypes == ". int(@types), 5);
		my @r = map { my $t = $_;
			for my $m (@methods) {
				my ($method, @args) = ($m->[0], @$m[1..$#$m]);
				Log("Calling $method on ". $_->name, 5);
				$t->$method(@args)
			}
		} @types;
		return @r;
	}

	method call($method, $c, $type) {
		if (!defined($type)) {
			$self->iterate_sources(['setParameters', $c], [$method]);
		} else {
			my $t = $self->resultset('TvType')->search( { name => $type } )->next;
			$t->setParameters($c);
			$t->$method();
		}
	}

	method update($c, $type) { $self->call('update', $c, $type); }
	method auto_fetch($c, $type) { $self->call('auto_fetch', $c, $type); }

	method add_search($queries, $destination = '', $witness = '', $type = 'mediathek') {
		my $query = $self->resultset('TvGrep');
		my $t = $self->resultset('TvType')->search( { name => $type } )->next;
		Log("Type: $type", 2);
		for my $q (@$queries) { $query->create(
			{ main::hashPrune(%{{expression => $q,
				destination => $destination, witness => $witness, type => $t->id }}) }
		); }
		return $self->resultset('TvGrep')->search({}, { prefetch => 'type'})->all;
		#return $query->all;
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
			.circumfix(join(',', defined($tags)? @$tags: ()), '--new-inline-tags ', ' | ')
			."xml sel -N w=http://www.w3.org/1999/xhtml -T -t -m $xpathq -v . -n | perl -pe 's/\n//g'";
		my $annotation = trimmStr(`$urlcmd`);
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
			'%U' => defined($xpath)? prefix($self->annotation($xpath, $tags), '_'): ''
		}, $fmt, { iterative => 'no' });
		Log("Fetching ". $self->title. " to ". $destPath, 1);
		Mkpath($dest, 5);

		return System($self->commandWithOutput($destPath), 2);
	}

	__PACKAGE__->meta->make_immutable(inline_constructor => 0);
}

class My::Schema::Result::TvItem {
	use base qw{ DBIx::Class::Core };
	__PACKAGE__->load_components(qw{DynamicSubclass Core});
	__PACKAGE__->table('tv_type');
	__PACKAGE__->add_column(qw{id type});
	__PACKAGE__->typecast_map(type => {	# <!> hardcoded id's
		1 => 'My::Schema::Result::TvItem::Mediathek',
		2 => 'My::Schema::Result::TvItem::Youtube'
	});

	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvItem::Base extends My::Schema::Result::TvItem {
	use TempFileNames;
	use Data::Dumper;
	use utf8;
	use PropertyList;

	has 'pars' => ( isa => 'HashRef', is => 'rw', lazy => 1, builder => 'builderPars' );

	method builderPars() {
		my $dict = propertyFromString($self->parameters());
		return $dict;
	}
	method setParameters(HashRef $newPars) {
		$self->pars({ %{$self->pars}, %$newPars });
		return $self;
	}
	method par(Str $key) { return $self->pars()->{$key}; }
	method schema() { return $self->result_source->schema; }
	method resultset(Str $name) { return $self->schema->resultset($name); }

	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvItem::Youtube extends My::Schema::Result::TvItem::Base {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use utf8;
	use POSIX qw{strftime};
	__PACKAGE__->add_column(qw{id name parameters});

	method fetch() { Log('fetch: youtube'); }
	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvItem::Mediathek extends My::Schema::Result::TvItem::Base {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use utf8;
	use POSIX qw{strftime};
	__PACKAGE__->add_column(qw{id name parameters});

	method fetch() { Log('fetch: Mediathek'); }
	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}
