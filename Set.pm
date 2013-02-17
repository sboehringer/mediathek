#	Set.pm
#Wed Aug 13 18:03:31 MET DST 1997

package	Set;
require	5.000;
require	Exporter;

@ISA		= qw(Exporter);

@EXPORT		= qw(&intersection &minus &product &union &pair &substitute &productJoin &join2 &joinNE &makeHash &dictWithKeys &mergedHashFromHash &mergeDict2dict &arrayFromKeys &mergeDict2dictDeeply &deepCopy &valuesForKeys &readHeadedTable &readHeadedTableString &readHeadedTableHandle &readCsv &writeCsv &tableColumn &tableAddColumn &writeHeadedTable &productT &productTL &arrayIsEqualTo &stripWhiteSpaceForColumns &sum &max &min &Min &Max &scaleSetTo &dictFromDictArray &toList &definedArray &firstDef &compareArrays &inverseMap &dictIsContainedInDict &keysOfDictLevel &sortTextNumber &readUnheadedTable &indexOf &mapDict &subDictFromKeys &compareSets &arrayFromDictArrayWithKey &unique &cmpSets &unlist &any &all &dict2defined &instantiateHash &order &which &whichMax &which_indeces);

use TempFileNames;

# return all keys from a dict and from dicts contained therein up to the level of $level

# for strings of the form .*[^\d]\d* sorts according to string
# then according to numerical value of \d*
sub sortTextNumber { my ($a, $b) = @_;
	my ($at, $an) = ($a =~ m{^(.*?)(\d*)$});
	my ($bt, $bn) = ($b =~ m{^(.*?)(\d*)$});
	return $at cmp $bt if ($at cmp $bt);
	return $an <=> $bn;
}

sub keysOfDictLevel { my ($d, $level) = @_;
	my ($keys, $i) = ([]);

	return $keys if ($level < 0);
	foreach $key (keys %{$d}) {
		$keys = union($keys, keysOfDictLevel($d->{$key}, $level - 1));
	}
	return union($keys, [keys %{$d}]);
}

sub valuesForKeys { my ($dict, $keys) = @_;
	#return [${$dict}{@{$keys}}]; # does not work
	my @r;
	foreach $k (@{$keys}) {
		push(@r, $dict->{$k});
	}
	return [@r];
}

sub dict2defined { my ($dict) = @_;
	return { map { ($_ => $dict->{$_}) } grep { defined($dict->{$_}) } keys %{$dict} };
}

# map the keys of $d with $map
sub mapDict { my ($d, $map) = @_;
	return makeHash(arrayFromKeys($map, [keys %{$d}]), [values %{$d}]);
}

# <i>
sub instantiateHash { my ($h) = @_;
	my $package = *{_}{PACKAGE};
	print "$package\n";
	#$$_ = $h->{$_} foreach keys %$h;
	#foreach $k (keys %$h) {
	#	$$k = $h->{$k};
	#	print "$$k\n";
	#}
	print "$a\n";
}

sub subDictFromKeys { my ($h, $keys) = @_;
	return makeHash($keys, arrayFromKeys($h, $keys));
}

# compare arrays numerically by means of the '==' operator

sub compareArrays { my (@arrays) = @_;
	my ($i, $j, $f);
	for ($i = 1, $f = int(@{$arrays[0]}); $i < @arrays; $i++) {
		return 1 if ($f != @{$arrays[$i]});
	}
	for ($i = 0; $i < @{$arrays[0]}; $i++) {
		for ($j = 1, $f = $arrays[0]->[$i]; $j < @arrays; $j++) {
			return 1 if ($f != $arrays[$j]->[$i]);
		}
	}
	return 0;
}
sub dictIsContainedInDict { my ($d1, $d2) = @_;
	foreach $k (keys %{$d1}) {
		return 0 if ($d1->{$k} ne $d2->{$k});
	}
	return 1;
}

sub firstDef { my @args = @_;
	foreach $a (@args) { return $a if (defined($a)); }
	return undef;
}
sub indexOf { my ($arr, $obj, $doNumCmp) = @_;
	my $i = 0;
	foreach $e (@{$arr}) {
		return $i if ($doNumCmp? $e == $obj: ($e eq $obj));
		$i++;
	}
	return undef;
}

sub toList { my ($array) = @_;
	return @{$array};
}
sub definedArray { my ($array) = @_;
	my $ret = [];
	map { push(@{$ret}, $_) if (defined($_)) } @{$array};
	return $ret;
}

sub	max { my (@arr) = @_;
	my $max = $arr[0];
	foreach $el (@arr)
	{	$max = $el if ($el > $max);
	}
	return $max;
}
sub	min { my (@arr) = @_;
	my $min = $arr[0];
	foreach $el (@arr)
	{	$min = $el if ($el < $min);
	}
	return $min;
}
sub	Min { my (@arr) = @_;
	my ($min, $i, $j) = ($arr[0], 0);
	for ($j = 0; $j < @arr; $j++) { if ($arr[$j] < $min) { $min = $arr[$i = $j]; } }
	return { v => $min, i => $i};
}
sub	Max { my (@arr) = @_;
	my ($max, $i, $j) = ($arr[0], 0);
	for ($j = 0; $j < @arr; $j++) { if ($arr[$j] > $max) { $max = $arr[$i = $j]; } }
	return { v => $max, i => $i};
}
sub	sum { my ($arr) = @_;
	my $sum = 0;
	foreach $el (ref($arr) ne 'ARRAY'? @_: @{$arr})
	{	$sum += $el;
	}
	return $sum;
}
#	round by biggest decimal places
sub scaleSetTo { my ($arr, $count) = @_;
	do {
		my $sum = sum($arr);
		my ($i, $new, $rest) = (0, [], []);
		foreach $e (@{$arr})
		{
			push(@{$new}, int($e / $sum * $count));
			push(@{$rest}, [$i++, $e / $sum * $count - int($e / $sum * $count)]);
		}
		@{$rest} = sort { $b->[1] <=> $a->[1] } @{$rest};
		my $share = $count - sum($new);
		foreach $e (@{$new})
		{
			last if (!$share--);
			$new->[$e->[0]]++;
		}
		$arr = $new;
	} until (sum($arr) >= $count);
	return $arr;
}

sub intersection { my($arr1,$arr2)=@_;
	my ($ret,%keys)=[];
	foreach $i (@{$arr1}) { $keys{$i}=0; }
	foreach $i (@{$arr2}) { push(@{$ret},$i) if (defined($keys{$i})); }
	return $ret;
}
sub minus { my($minuend,$subtrahend)=@_;
	my (@ret, %keys);
	foreach $i (@{$subtrahend}) { $keys{$i} = 0; }
	foreach $i (@{$minuend}) { push(@ret, $i) if (!defined($keys{$i})); }
	return [@ret];
}	
sub compareSets { my ($seta, $setb) = @_;
	my $diffa = minus($seta, $setb);
	my $diffb = minus($setb, $seta);

	return { diffa => $diffa, diffb => $diffb, identical => !(@{$diffa} + @{$diffb}) };
}

sub product { my($arr1,$arr2,$eliminate)=@_;
	my ($ret,$i,$j)=[];
	foreach $i (@{$arr1})
	{ foreach $j (@{$arr2}) { push(@{$ret},$i,$j) if (!$eliminate || ($i ne $j)); } }
#	print "Product:",join(':',@{$ret}),"|",join(':',@{$arr1}),"|",join(':',@{$arr2}),"\n";
	return $ret;
}
sub productT { my($arr1,$arr2,$eliminate)=@_;
	my ($ret,$i,$j)=[];
	foreach $i (@{$arr1})
	{ foreach $j (@{$arr2}) { push(@{$ret}, [$i, $j]) if (!$eliminate || ($i ne $j)); } }
	return $ret;
}
sub productTL { my($arr1,$arr2,$eliminate)=@_;
	my ($ret,$i,$j)=[];
	foreach $i (@{$arr1})
	{ foreach $j (@{$arr2}) { push(@{$ret}, [@{$i}, $j]) if (!$eliminate || ($i ne $j)); } }
	return $ret;
}
sub productJoin { my($arr1,$str,$arr2,$eliminate)=@_;
	my ($ret,$i,$j)=[];
	foreach $i (@{$arr1})
	{ foreach $j (@{$arr2}) { push(@{$ret},$i.$str.$j) if (!$eliminate || ($i ne $j)); } }
#	print "Product:",join(':',@{$ret}),"|",join(':',@{$arr1}),"|",join(':',@{$arr2}),"\n";
	return $ret;
}
sub pair { my($arr1,$arr2)=@_;
	my ($ret,$i,$j)=[];
	for ($i=0; $i<=$#$arr1; $i++) { push(@{$ret},$arr1->[$i],$arr2->[$j]); }
	return $ret;
}
sub substitute { my($arr1,$map)=@_;
	foreach $i (@{$arr1}) { $i=$map->{$i} if (defined($map->{$i})); }
	return $arr1;
}

# join together chunks of $cnt from @arr with $str1
# join together the chunks with $str2
sub join2 { my($str1, $cnt, $str2, @arr)=@_;
	my @temp;
	while ($#arr>=0)
	{	push(@temp,join($str1,splice(@arr,0,$cnt)));
	}
	return join($str2,@temp);
}
# joinNE: join after eliminating empty strings from @list
sub joinNE { my ($str, @list) = @_; return join($str, grep { $_ ne '' } @list); }

# return an array wich is a union of all arrays referenced by $arrOfArr
# the sematics is mathematical by excluding dupblicates

sub union { my (@arrOfArr) = @_;
	my ($dict, $ret);
	foreach $arr (@arrOfArr)
	{
		foreach $el (@{$arr})
		{
			next if (defined($dict->{$el}));
			$dict->{$el} = 0;
			push(@{$ret}, $el);
		}
	}
	return $ret;
}

sub unique { my (@set) = @_;
	return @{union([@set])};
}

sub cmpSets { my ($s1, $s2) = @_;
	return 1 if ($#$s1 != $#$s2);
	my @ss1 = sort @{$s1};
	my @ss2 = sort @{$s2};
	my $i;
	for ($i = 0; $i < @ss1; $i++) { return 1 if ($ss1[$i] != $ss2[$i]); }
	return 0;
}

%cmpFcts = (
	int => sub { $_[0] <=> $_[1] },
	alpha => sub { $_[0] cmp $_[1] }
);
sub order { my ($arr, $cmp) = @_;
	$cmp = $cmpFcts{$cmp} if (defined($cmp) && ref($cmp) eq '');
	$cmp = $cmpFcts{'int'} if (!defined($cmp));
	my $va = [];
	return sort { &$cmp($arr->[$a], $arr->[$b]) } 0 .. (int(@$arr) - 1);
}


#	other functions

sub makeHash { my ($keys, $values, $omitKey)=@_;
	my ($hash, $i) = ({});
	for ($i = 0; $i <= $#$keys; $i++)
	{	$hash->{$keys->[$i]} = $values->[$i]
			if (defined($keys->[$i]) && (!defined($omitKey) || ($keys->[$i] ne $omitKey)));
	}
	return $hash;
}
sub dictWithKeys { my($keys, $value) = @_;
	my $hash = {};
	$value = firstDef($value, 0);
	foreach $el (@$keys) { $hash->{$el } = $value; }
	return $hash;
}

sub mergedHashFromHash { my($hash, $merge, $defValues)=@_;
	my $ret={};

	foreach $key (keys(%{$hash}))
	{	$ret->{$key}=$hash->{$key};
	}
	foreach $key (keys(%{$merge}))
	{	$ret->{$key}=$merge->{$key} if (!$defValues || defined($merge->{$key}));
	}
	return $ret;
}
sub mergeDict2dict { my($hashS, $hashD)=@_;
	foreach $key (keys(%{$hashS}))
	{	$hashD->{$key}=$hashS->{$key};
	}
	return $hashD;
}

#	<!> not cycle proof
#	array merge is supported by appending arrays to each other
#	if arrays are to be merged the arrays var contains respective keys
#	indicating the order of merging 0: hashS after hashD; 1: hashD after hashS
#
sub mergeDict2dictDeeply { my($hashS, $hashD, $arrays)=@_;
	foreach $key (keys(%{$hashS}))
	{	if (ref($hashS->{$key}) eq 'HASH' && ref($hashD->{$key}) eq 'HASH')
		{	mergeDict2dictDeeply($hashS->{$key}, $hashD->{$key});
		} elsif (defined($arrays) && defined($arrays->{$key}) &&
			ref($hashS->{$key}) eq 'ARRAY' && ref($hashD->{$key}) eq 'ARRAY')
		{
			if (!$arrays->{$key})	# natural order
			{	push( @{$hashD->{$key}}, @{$hashS->{$key}} );
			} else {
				unshift( @{$hashD->{$key}}, @{$hashS->{$key}} );
			}
		} else { $hashD->{$key}=$hashS->{$key}; }
	}
	return $hashD;
}
#	<!> not cycle proof
sub deepCopyHash { my ($hash)=@_;
	my ($copy)={%{$hash}};
	foreach $key (keys(%{$copy})) { $copy->{$key}=deepCopy($copy->{$key}); }
	return $copy;
}
sub deepCopyArray { my ($array)=@_;
	my ($copy)=[@{$array}];
	foreach $el (@{$copy}) { $el=deepCopy($el); }
	return $copy;
}
sub deepCopy { my ($el)=@_;
	if (ref($el) eq 'HASH')
	{	return deepCopyHash($el);
	} elsif (ref($el) eq 'ARRAY')
	{	return deepCopyArray($el);
	} else { return $el; }	# not copied <N>
}

sub arrayFromKeys { my($hash, $keys, $default) = @_;
	my $arr = [];

	foreach $el (@{$keys}) {
		push(@{$arr}, defined($hash->{$el})? $hash->{$el}: $default);
	}
	return $arr;
}
sub arrayFromDictArrayWithKey { my ($a, $k) = @_;
	return map { $_->{$k} } @{$a};
}

sub substituteComma { my ($f) = @_;
	$f =~ tr{,}{.} if ($f =~ m{^\s*\d*,\d+\s*$}os);
	return $f;
}
sub autoNameColumns { my ($factors, $count, $prefix) = @_;
	my $i = 1;
	return [ map { $factors->[$_] eq ''? $prefix.$i++: $factors->[$_] } 0 .. ($count - 1)];
}
sub splitREforSQ { my ($s, $q) = @_;
#	return qq{(?:$s|^)((?:$q(?:[^$q\\]+|\\$q|\\[^$q])*$q)|[^$s$q]*)};
	return qq{(?:^|$s)((?:[$q](?:[^\\$q]+|\\.)*[$q])|(?:[^$s$q]*))};
}
# <i><A> tb made more robust
sub autoDetectSeparator { my ($header) = @_;
	if ($header =~ m{\t}os && !($header =~ m{,}os) && !($header =~ m{;}os)) {
		return ("\t", undef);
	} elsif ($header =~ m{,}os && !($header =~ m{;}os)) {
		return (',', undef);
	} else {
		return (';', \&substituteComma);
	}
}
# options via $cfg
#	quoteChar: quote fields and allow newlines, separator char
#	unquoteQuoteCharOnly: boolean indicating what \c should mean for c other than quoteChar
#	separationChar|sep: field separator
#	autoDetect: boolean to detect separator char from input
#	autoColumns: prefix used to replace empty column names
#	ignoreBlankRows:	whether to import rows that are empty
#	doReturnArrays:	return arrays rather than dicts
sub readHeadedTableString { my ($s, $defaultEntry, $providedFactorList, $excludeEmptyEntries, $cfg) = @_;
	if (ref($providedFactorList) eq 'HASH') {
		$cfg = $providedFactorList;
		$providedFactorList = $cfg->{factors};
		$excludeEmptyEntries = $cfg->{excludeEmptyEntries};
	}
	$defaultEntry = $cfg->{defaultEntry} if (!defined($defaultEntry));
	my ($list, $entry, $valueList, $rawList) = ([], {});
	my $factorList = [@$providedFactorList];
	my $sc = firstDef($cfg->{separationChar}, $cfg->{sep}, "\t");	# separation char
	my $q = firstDef($cfg->{quoteChar}, '"');	# quoting char
	my $splitRE = firstDef($cfg->{splitRE}, splitREforSQ($sc, $q));
	my @lines = split(/\n/, $s);
	my $sc = $splitRE;
	my $transformer;	# post transformer of fields

	if (uc($cfg->{autoDetect}) eq 'YES') {
		($sc, $transformer) = autoDetectSeparator($lines[0]);
		$splitRE = splitREforSQ($sc, $q);
	}
	if (!defined($providedFactorList) && !$cfg->{autoColumns}
		&& (!defined($cfg->{header}) || $cfg->{header})) {
		$_ = shift(@lines);
		chop($_) if (substr($_, -1, 1) eq "\r");	# ms-dos line separation
		# destill factors and substitue according to $map, strip surrounding space
		# <i> do not hardwire '"', use $q instead <t>
		$factorList = [map { /^[$q](.*)[$q]$/o? $1: $_ } m{$splitRE}g];
	}
	my $c = int(@$factorList);	# count fields
	if ($cfg->{autoColumns} ne '') {
		# <N> somewhat flawed but robust heuristic to estimate number of factors
		$c = max($c, int($lines[0] =~ m{$splitRE}g));
		$factorList = autoNameColumns($factorList, $c, $cfg->{autoColumns});
	}

	while (int(@lines)) {
		if ($q ne '') {	# sophisticated line break-up allowing 
			my ($line, $a, @fields, @rawFields, $digestedLength) = ('');
			do {
				$a = shift(@lines);
				chop($a) if (substr($a, -1, 1) eq "\r"); # ms-dos
				$line .= ($line eq ''? '': "\n"). $a;
				if ($cfg->{unquoteQuoteCharOnly}) {
					@rawFields = ($line =~ m{$splitRE}sog);
					@fields = map
						{ my $f = (/^[$q](.*)[$q]$/os? $1: $_); $f =~ s/\\$q/$q/sog; $f } @rawFields;
				} else {
					@rawFields = ($line =~ m{$splitRE}sog);
					@fields = map
						{ my $f = (/^[$q](.*)[$q]$/os? $1: $_); $f =~ s/\\(.)/$1/sog; $f } @rawFields;
				}
			} while (sum(map { length($_) } @rawFields) + int(@rawFields) < length($line) && int(@lines));
			$rawList = [ @fields ];
		} else {	# old safe fallback
			$_ = shift(@lines); chop($_) if (substr($_, -1, 1) eq "\r");	# ms-dos line separation
			$rawList = [map { /^\"(.*)\"$/o? $1: $_; } split(/$splitRE/)];
		}
		$rawList = [map { $transformer->($_) } @$rawList] if (defined($transformer));
		next if (uc($cfg->{ignoreBlankRows}) eq 'YES' && !any(@$rawList));

		if ($excludeEmptyEntries) {
			$rawList = [map { $_ eq ''? undef(): $_ } @{$rawList}];
		}
		mergeDict2dict($defaultEntry, $entry = {});
		my $e = uc($cfg->{doReturnArrays}) eq 'YES'
			? $rawList
			: mergeDict2dict(makeHash($factorList, $rawList, $excludeEmptyEntries), $entry);
		push(@$list, $e);
		if (uc($cfg->{returnLevels}) eq 'YES') {
			$valueList = { @{product($factorList, [{}])} }; # initialize $valueList
			foreach $factor (@{$factorList}) {
				$valueList->{$factor}{$entry->{$factor}} = 0;
			}
		}
	}
	push(@{$factorList}, sort keys %{$defaultEntry});
	my $r = { factors => $factorList, values => $valueList, data => $list};
	$r->{list} = $r->{data};	# retain compatibility
	return $r;
}
sub readHeadedTableHandle { my ($fileHandle, $defaultEntry, $providedFactorList,
		$excludeEmptyEntries, $cfg) = @_;
	my $s = TempFileNames::readFileHandle($fileHandle, undef, $cfg->{encoding});
	return readHeadedTableString($s, $defaultEntry, $providedFactorList, $excludeEmptyEntries, $cfg);
}

sub readHeadedTable { my ($path, $defaultEntry, $providedFactorList, $excludeEmptyEntries, $cfg) = @_;
	my $s = TempFileNames::readFile($path, undef, $cfg->{encoding});
	return readHeadedTableString($s, $defaultEntry, $providedFactorList, $excludeEmptyEntries, $cfg);
}
sub stripWhiteSpaceForColumns { my ($set, $columns) = @_;
	foreach $row (@{$set->{list}})
	{
		foreach $column (@{$columns})
		{
			$row->{$column} =~ s{^\s*(.*?)\s*$}{$1}o;
		}
	}
}

sub readCsv { my ($path, $c) = @_;
	my $s = TempFileNames::readFile($path, undef, $c->{encoding});
	return readHeadedTableString($s, undef, { sep => ',', doReturnArrays => 'YES', %$c });
}
sub writeCsv { my ($t, $path, $c) = @_;
	writeHeadedTable($path, $t->{data}, $t->{factors}, { sep => ',', %$c });
}

sub tableColumn { my ($t, $col) = @_;
	my $name = $t->{factors}[$col];
	my @d;
	return { data => [], $name => $name } if ($#{$t->{data}} < 0);
	if (ref($t->{data}[0]) eq 'ARRAY') {
		push(@d, $_->[$col]) foreach (@{$t->{data}});
	} else {
		push(@d, $_->{$name}) foreach (@{$t->{data}});
	}
	return { data => [@d], name => $name };
}
sub tableAddColumn { my ($t, $col) = @_;
	my $name = $col->{name};
	push(@{$t->{factors}}, $name);

	# the following does not work because of identical reference [] <!>
	#$t->{data} = [ ([]) x int(@{$col->{data}}) ] if ($#{$t->{data}} < 0);	# default to array version
	$t->{data} = [ map { [] } 0 .. $#{$col->{data}} ] if ($#{$t->{data}} < 0);	# default to array version

	if (ref($t->{data}[0]) eq 'ARRAY') {
		push(@{$t->{data}[$_]}, $col->{data}[$_]) foreach (0 .. $#{$col->{data}});
	} else {
		$t->[$_]{$name} = $col->{data}[$_] foreach (0 .. $#{$col->{data}});
	}
}

sub readUnheadedTable { my ($path) = @_;
	my $ret = [];

	open(TABLE_INPUT, $path);
	while (<TABLE_INPUT>)
	{
		chop($_);
		push(@{$ret}, [split(/\t/)]);
	}
	close(TABLE_INPUT);

	return $ret;
}

sub writeHeadedTableHandle { my ($fileHandle, $sets, $factorList, $options) = @_;
	my $factors = defined($factorList)? $factorList: (ref($sets) eq 'ARRAY'
		? (ref($sets->[0]) eq 'ARRAY'? undef: [keys(%{$sets->[0]})])
		: $sets->{factors});
	my $sep = firstDef($options->{separationChar}, $options->{sep}, "\t");

	print $fileHandle join($sep, ref($sets) eq 'HASH' && defined($sets->{printFactors})?
		@{$sets->{printFactors}}: @{$factors}),"\n" if (!$options->{noHeader} && defined($factors));

	foreach $data (ref($sets) eq 'ARRAY'? @{$sets}: @{$sets->{list}})
	{	my $dmy = (ref($data) eq 'ARRAY')? $data: arrayFromKeys($data, $factors);
		if ($options->{quoteSpace})
		{
			foreach $el (@{$dmy})
			{	$el = '"'.$el.'"' if ($el =~ m{\s}o);
			}
		}
		print $fileHandle join($sep, @{$dmy}), "\n";
	}
}

sub writeHeadedTable { my ($path, $sets, $factorList, $options) = @_;
	my $outputFile;
	if ($path eq 'STDOUT') { $outputFile = \*STDOUT; }
	else { open (DATA_OUTPUT,">$path"), $outputFile = \*DATA_OUTPUT; }

		writeHeadedTableHandle($outputFile, $sets, $factorList, $options);

	close(DATA_OUTPUT) if ($path ne 'STDOUT');
}

sub arrayIsEqualTo { my ($arr1, $arr2) = @_;
	return 0 if ($#$arr1 != $#$arr2);
	my $i;
	for ($i = 0; $i <= $#$arr1; $i++) { return 0 if ($arr1->[$i] ne $arr2->[$i]); }
	return 1;
}

# compute a somewhat inverse map:
# foreach dict take the value of some key and associate that value with the dict

sub dictFromDictArray { my ($array, $key) = @_;
	my $dict = {};
	$key = 'name' if (!defined($key));

	foreach $entry (@{$array})
	{
		$dict->{$entry->{$key}} = $entry;
	}
	return $dict;
}

# compute a Map with value => key
# which of course is not unique

sub inverseMap { my ($dict) = @_;
	my $idict = {};

	foreach $k (keys %{$dict}) {
		$idict->{$dict->{$k}} = $k;
	}
	return $idict;
}

sub unlist { my (@list) = @_;
	my @ret;
	foreach $e (@list) {
		push(@ret, ref($e) eq 'ARRAY'? unlist(@{$e}): $e);
	}
	return @ret;
}

# <p> logic on arrays

# is any value in the list true?
sub any { foreach $e (@_) { return 1 if ($e); } return 0; }
# are all values true?
sub all { foreach $e (@_) { return 0 if (!$e); } return 1; }

sub which { my ($see, $sed, $numeric) = @_;
	my $i;
	if ($numeric) {
		for ($i = 0; $i < @$sed; $i++) { return $i if ($sed->[$i] == $see); }
	} else {
		for ($i = 0; $i < @$sed; $i++) { return $i if ($sed->[$i] eq $see); }
	}
	return undef;
}

sub orderFromIndeces { my (@a) = @_;
	my @o = (undef() x int(@a));
	for (my $i = 0; $i < @a; $i++) { $o[$a[$i]] = $i; }
	return @o;
}

sub which_indeces { my ($see, $sed, $numeric) = @_;
	my (@ret, $i, $j);
	if ($numeric) {
		my @isee = sort { $see->[$a] <=> $see->[$b] } 0..(@$see - 1);
		my @osee = orderFromIndeces(@isee); # order
		my @ised = sort { $sed->[$a] <=> $sed->[$b] } 0..(@$sed - 1);
		for ($i = $j = 0; $i < @$see; $i++) {
			while ($j < @$sed && $sed->[$ised[$j]] < $see->[$isee[$i]]) { $j++; }
			push(@ret, $sed->[$ised[$j]] == $see->[$isee[$i]]? $ised[$j]: undef);
		}
		@ret = @ret[@osee];
	} else {
		my @isee = sort { $see->[$a] cmp $see->[$b] } 0..(@$see - 1);
		my @osee = orderFromIndeces(@isee); # order
		my @ised = sort { $sed->[$a] cmp $sed->[$b] } 0..(@$sed - 1);
		for ($i = $j = 0; $i < @$see; $i++) {
			while ($j < @$sed && ($sed->[$ised[$j]] cmp $see->[$isee[$i]]) < 0) { $j++; }
			push(@ret, $sed->[$ised[$j]] eq $see->[$isee[$i]]? $ised[$j]: undef);
		}
		@ret = @ret[@osee];
	}
	return @ret;
}

sub whichMax { my ($see, $numeric) = @_;
	my $mxI = 0;
	for (my $i = 1; $i < @$see; $i++) {
		$mxI = $i if ($see->[$i] > $see->[$mxI]);
	}
	return $mxI;
}

1;
