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

	method queryFromExpression($query) {
		my $likeKeys = dictWithKeys(['channel', 'topic', 'title'], 1);
		my @terms = map { /([^:]+):(.*)/; [($1, $2)] } grep { $_ ne '' } split(/;/, $query);
		my @query = map { my ($k, $v, $modifier) = ($_->[0], $_->[1]);
			($modifier, $v) = ($v =~ m{^([!<>]?)(.*)}sog);
			$k = 'time(date)' if ($k eq 'time');
			my $isCmp = defined(which($modifier, ['>', '<']));
			my $q = { ($likeKeys->{$k} && $v =~ m{[%]}os)
			? ($k, { ($modifier eq '!'? 'not like': 'like'), $v })
			: ($k, $isCmp? { $modifier, $v }: $v) };
			$q
		} @terms;
		return @query;
	}

	method search($queries, $extraTerms = []) {
		#$extraTerms = [] if (!defined($extraTerms));
		my $tv_item = $self->resultset('TvItem');
		my @r = map { my $query = $_;
			my @query = $self->queryFromExpression($query);
			# print(Dumper([@query]));
			push(@$extraTerms, { 'tv_recording.recording' => { '=' , undef } }) if (!$self->par('doRefetch'));
			my @queryF = (@query,
				{ type => $self->id }, @$extraTerms);
			my @items = $tv_item->search({ -and => \@queryF },
				{ join => 'tv_recording', rows => $self->par('Nfetch') });
			Log("Number of items to be fetched: ". @items, 2);
			@items
		} @$queries;
		return @r;
	}

	method fetchPars() { return {}; }
	method constraints($q) { return []; }

	method auto_fetch() {
		Log("Autofetching type". $self->id. "...", 5);
		my $destination = $self->par('videolibrary');
		my $fetchPars = $self->fetchPars;
		if (!-e $destination) {
			Log(sprintf('VideoLibrary "%s" does not exist.', $destination), 4);
			return;
		}
		for my $q ( ($self->resultset('TvGrep')->search({ type => $self->id })) ) {
			Log("Fetching expression: ". $q->expression, 3);
			for my $r ( ($self->search([$q->expression], $self->constraints($q))) ) {
				my $pars = $q->witness eq ''? {}: propertyFromString($q->witness);
				my $ret = $r->fetchTo($destination. '/'. $q->destination, {%$fetchPars, %$pars });
				$self->resultset('TvRecording')->create({ recording => $r->id }) if (!$ret);
				Log(sprintf('Recording success [%s]: %d', $r->title, $ret), 5);
			}
		}
	}

	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvType::Youtube extends My::Schema::Result::TvType::Base {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use utf8;
	use POSIX qw{strftime};
	use warnings;
	__PACKAGE__->add_column(qw{id name parameters});

	method fetch() { Log('fetch: youtube'); }
	method updateChannel($channel) {
		my $ct = [grep { my @k = keys %{$_}; $k[0] eq 'channel' }
			$self->queryFromExpression($channel->expression)]->[0]{channel};
		Log("Channel update: $ct", 3);
		my $url = 'https://www.youtube.com'. (substr($ct, 0, 1) eq '/'? $ct: ('/channel/'. $ct));
		my $cmd = './fetch-parse-youtube.pl --fetch '. $url;
		#
		# <p> database update
		#
		my $sep = ':<>:';	# fetch-parse-youtube.pl
		# keys as of fetch-parse-youtube; id -> url; date, type manually added
		my @keys = ( 'url', 'channel', 'title', 'date', 'type' );
		my $fh = IO::File->new("$cmd |");
		die "couldn't fetch channel list [$channel]" if (!defined($fh));
		my $icnt = 0;	# insert count
		my $now = time();
		my $tv = $self->resultset('TvItem');
		no warnings;
		while (my $l = substr(<$fh>, 0, -1)) {
			my $item = main::makeHash(\@keys,
				[(split(/$sep/, $l), strftime('%Y-%m-%d %H:%M:%S', localtime($now)), $self->id)]);
			#print $l;
			my $item0 = $tv->find_or_new($item, { key => 'url_unique' });
			$item0->insert, $icnt++ if (!$item0->in_storage);
		}
		Log("Youtube: $icnt items inserted.", 4);
	}
	method update() {
		Log("Updating youtube channels", 3);
		my @channels = $self->resultset('TvGrep')->search()->all;
		for my $q ( @channels ) {
			$self->updateChannel($q);
		}
	}
#	method constraints($q) { return [{ channel => $q->witness }]; }
# 	method auto_fetch() {
# 		my @channels = $self->resultset('TvGrep')->search()->all;
# 		for my $q ( @channels ) {
# 			Log("Fetching channel: ". $q->witness, 3);
# 			my @items = ($self->search([$q->expression], [{ channel => $q->witness }]))
# 				[0 .. $self->par('youtubeMaxCount')];
# 		}
# 	}
	method fetchPars() { return { fmt => '%(title)s.%(ext)s' }; }

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
		my $cmd = 'xzcat '. qs($path). ' | '. './parse-videolist-json.pl --parse - --logLevel '
			. $TempFileNames::__verbosity;
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
	method fetchPars() { return { fmt => '%D_%T%U.%E' }; }

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
		@methods = ([@methods]) if (ref($methods[0]) ne 'ARRAY');
		my @types = ($self->resultset('TvType')->all);
		Log("# TvTypes == ". int(@types), 5);
		my @r = map { my $t = $_;
			my @r;
			for my $m (@methods) {
				my ($method, @args) = ($m->[0], @$m[1..$#$m]);
				Log("Calling $method on ". $_->name, 5);
				@r = $t->$method(@args)
			}
			@r
		} @types;
		return @r;
	}

	method call($method, $c, $type) {
		$method = [$method] if (ref($method) ne 'ARRAY');
		if (!defined($type)) {
			$self->iterate_sources(['setParameters', $c], $method);
		} else {
			my $t = $self->resultset('TvType')->search( { name => $type } )->next;
			$t->setParameters($c);
			my ($m, @args) = ($method->[0], @$method[1 .. $#$method]);
			$t->$m(@args);
		}
	}

	method update($c, $type) { $self->call('update', $c, $type); }
	method auto_fetch($c, $type) { $self->call('auto_fetch', $c, $type); }
	method search($c, $type, @queries) { $self->call(['search', [@queries]], $c, $type); }

	method add_search($queries, $destination = '', $witness = '', $type = 'mediathek') {
		my $query = $self->resultset('TvGrep');
		my $t = $self->resultset('TvType')->search( { name => $type } )->next;
		Log("Type: $type", 2);
		for my $q (@$queries) { $query->create(
			{ hashPrune(%{{expression => $q,
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

	method update_search($ids, $destination = '', $witness) {
		my $query = $self->resultset('TvGrep');
		for my $id (@$ids) {
			$query->search({id => $id})->update(
				{ hashPrune(%{{ destination => $destination, witness => $witness }}) }
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

	method fetchSingle($c, $type, Str $query, $pars) {
		#my @r = $self->search( ($query) );
		my @r = $self->call(['search', [$query]], $c, $type);
		$pars = { %{$self->call(['fetchPars'], $c, $type)}, defined($pars)? %$pars: () };
		#print(Dumper($pars));
		for my $r (@r) {
			$r->fetchTo($c->{videolibrary}, $pars);
		}
	}
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
	use Set;

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

	method annotation($pars) {
		return '' if (!defined($pars->{urlextract}) || $pars->{urlextract} eq '');
		my $urlcmd = "xml.pl --wget ". qs($self->homepage()). " --tidy -m ". qs($pars->{urlextract});
		my $annotation = trimmStr(`$urlcmd`);
		Log("Annotation command: $urlcmd", 2);
		Log("Annotation: $annotation", 2);
		return $annotation;
	}

	method fetchTo($dest, $pars) {
		my $fmt = $pars->{fmt};
		my $title = $self->title;
		$title =~ tr[/][|];
		my $d = {
			'%T' => $title,
			'%D' => dateReformat($self->date, '%Y-%m-%d %H:%M:%S', '%Y-%m-%d'),
			'%E' => splitPathDict($self->url)->{extension},
			'%U' => $self->annotation($pars)
		};
		#print(Dumper($d));
		my $destPath = $dest. '/'. mergeDictToString($d, $fmt, { iterative => 'no' });
		Log("Fetching ". $self->title. " to ". $destPath, 1);
		Mkpath($dest, 5);
		$self->fetchToPath($destPath, $pars);
	}

	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvItem::Youtube extends My::Schema::Result::TvItem::Base {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use utf8;
	use POSIX qw{strftime};
	__PACKAGE__->add_column(qw{id name parameters});

	method fetchToPath($destPath, $pars) {
		my %parMap = ( extractAudio => '--extract-audio' );
		Log('fetch: youtube: '. $self->url. ' --> '. $destPath. '[title: '. $self->title. ']', 5);
		my $youtubeParsBin = join(' ', map { $parMap{$_} } grep { $pars->{$_} } keys %$pars);
		my $cmd = "youtube-dl $youtubeParsBin ". $self->url. ' -o '.qs($destPath);
		System($cmd, 3);
	}
	__PACKAGE__->meta->make_immutable( inline_constructor => 0 );
}

class My::Schema::Result::TvItem::Mediathek extends My::Schema::Result::TvItem::Base {
	use TempFileNames;
	use Set;
	use Data::Dumper;
	use utf8;
	use POSIX qw{strftime};
	__PACKAGE__->add_column(qw{id name parameters});

	# default format: day_title
	method fetchToPath($destPath, $pars) {
		Log("URL: ". $self->url(), 2);
		my $command = mergeDictToString({
			URL => $self->url,
			OUTPUT => qs($destPath)
		}, './fetch-video --o OUTPUT URL');
		return System($command, 2);
	}

	__PACKAGE__->meta->make_immutable(inline_constructor => 0);
}

