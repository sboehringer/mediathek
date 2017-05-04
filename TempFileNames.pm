package TempFileNames;
require 5.000;
require Exporter;

@ISA       = qw(Exporter);
@EXPORT    = qw(&tempFileName &removeTempFiles &readCommand &readFile &writeFile &scanDir &copyTree &searchOrphanedFiles &removeEmptySubdirs &dirList &dirListPattern &dirListDeep &fileList &FileList &searchOutputPattern &normalizedPath &relativePath &quoteRegex &uniqFileName &readStdin &restoreRedirect &redirectInOut &germ2ascii &appendStringToPath &pipeStringToCommand &pipeStringToCommandSystem &mergeDictToString &mapTr &mapS $DONT_REMOVE_TEMP_FILES &readFileHandle &trimmStr &deepTrimmStr &removeWS &fileLength &processList &pidsForWordsPresentAbsent &initLog &Log &cmdNm &splitPath &resourcePath &resourcePathesOfType &splitPathDict &progressPrint &percentagePrint &firstFile &firstFileLocation &readFileFirstLocation &allowUniqueProgramInstanceOnly &allowUniqueProgramInstanceOnly &write2Command &ipAddress &packDir &unpackDir &System $YES $NO &interpolatedPlistFromPath &GetOptionsStandard &StartStandardScript &callTriggersFromOptions &doLogOnly &interpolatedPropertyFromString &existsOnHost &existsFile &existsWithBase &mergePdfs &SystemWithInputOutput &depthSearchDir &diskUsage &searchMissingFiles &whichFilesInTree &setLogOnly &readConfigFile &writeConfigFile &statDict &Stat &findDir &tempEdit &Mkpath &Mkdir &Rename &Rmdir &Unlink &Move &Symlink &removeBrokenLinks &testService &testIfMount &qs &qsQ &qs2 &uqs &prefix &dateReformat &formatTableComponents &formatTable &lcPrefix &prefix &postfix &circumfix &slurpToTemp &slurpPipeToTemp);

#@EXPORT_OK = qw($sally @listabob %harry func3);

#use lib '/LocalDeveloper/Libraries/perl5';
use Encode;
use utf8;
use File::Copy;
use File::Path;
use IO::Handle;
use IO::File;
use PropertyList;
use Set;
use POSIX;
use POSIX::strptime qw(strptime);
use Fcntl ':flock';	# testService
use Fcntl qw(&F_WRLCK &F_SETLKW &F_UNLCK &F_SETLK);	#lockFile
#require 'sys/fcntl.ph';	#lockFile

#use Locale;	# dependence is: germ2ascii <i><A> tb removed
#	germ2ascii has been moved to Locale.pm this will break some code <!>

#
#	<p> data
#

$GeneralHelp=<<GENERAL_HELP;
	General Options:
	--logLevel n	Specify logLevel (>= 4 for debugging)
	--doLogOnly	do not execute calls controlled by \$__doLogOnly
	--config path	read config file from file system location ''path''
	--credentials	export credentials from keyring
GENERAL_HELP

$locale = undef;

#
#	<p> functions
#

sub locale {
	return $locale if ($locale);
	eval("use Locale::Locale");
	$locale = Locale::Locale->new();
	return $locale;
}

BEGIN { srand(); $DONT_REMOVE_TEMP_FILES=0; $YES = 1; $NO = 0; }
sub uniqFileName {	my($prefix)=@_;
	my($i);
	if (!-e $prefix) { return $prefix; }
	for ($i=0; -e ($ret=$prefix."_$i"); $i++) { }
	return $ret;
}


sub existsLocal { return -e $_[0]; }
sub existsOnHost { my ($file, $host) = @_;
	return !system("ssh $host '[ -e $file ];' 2>/dev/null");
}
sub existsOnHostLambda { my ($host) = @_;
	return sub { return existsOnHost($_[0], $host); }
}
sub existsWithBase { my ($path) = @_;
	my $sp = splitPathDict($path);
	my @bases = grep { splitPathDict($_)->{base} eq $sp->{base} } dirList($sp->{dir});
	#Log("bases [dir:$sp->{dir}], [base:$sp->{base}]: ". join(', ', @bases), 2);
	return map { "$sp->{dir}/$_" } @bases;
}

sub fileOperation { my ($local, $remote, $uri, @args) = @_;
	my ($host, $path) = ($uri =~ m{^(?:([^/:]+?):)?(.*)$}o);
	Log("File operation; host: $host, path: $path", 6);
	return ($host ne '')? $remote->($path, $host, @args): $local->($uri, @args);
}
sub existsFile { return fileOperation(\&existsLocal, \&existsOnHost, @_);}

sub tempFileName { my ($prefix, $postfix, $onHost, $dontDelete, $digits) = @_;
	my ($ret, $c);
	# <p> configuration polymorphism
	if (ref($onHost) eq 'HASH') {
		$c = $onHost;
		($onHost, $dontDelete, $digits, $doTouch) = @$c{
		('onHost', 'dontDelete', 'digits', 'doTouch')};
	}
	return undef() if (defined($onHost) && !($onHost =~ m{\@}os));
	my $exists = (defined($onHost) && $onHost ne 'localhost')
	? existsOnHostLambda($onHost): \&existsLocal;
	while ($exists->(($ret = $prefix. int(rand(10 ** Set::firstDef($digits, 6))). $postfix))) {
		Log("tempFileNames:trying:$ret", 7);
	}
	if ($c->{doTouch}) {	#<!><i> remote host capabilities
		my $sp = splitPathDict($ret);
		Mkpath($sp->{dir}, 6);
		writeFile($ret, '');
	}
	if ($c->{mkDir}) {	#<!><i> remote host capabilities
		Mkpath($ret, 6);
	}

	if (!$dontDelete) {
		if (defined($onHost)) {
			push(@remoteTempFileList, { host => $onHost, file => $ret });
		} else {
			push(@tempFileList, $ret);
		}
	}
	writeFile($ret, '', { host => $onHost }) if ($doTouch);
	return $ret;
}

sub tempEdit { my ($s, $o) = @_;
	my $path = tempFileName(firstDef($o->{tempfilePrefix}, "/tmp/tempEdit"));
	writeFile($path, $s);
	System("vi $path", 5);
	$s = readFile($path);
	if ($o->{secureDelete}) {
		writeFile($path, $_ x length($s)) foreach (chr(0xaa), chr(0x00), chr(0x7f));
	}
	return $s;
}

#sub removeTempFiles { system('rm -f '.join(' ',@tempFileList)) if ($#tempFileList>=0); }
sub removeTempFiles {
	# remove local files
	unlink(grep { ! -d $_ } @tempFileList);
#	print STDERR "rmtree(removeTempFiles) ", join(':', grep { -d $_ } @tempFileList), "\n";
	my @tempDirList = grep { -d $_ } @tempFileList;
	rmtree([@tempDirList]) if (@tempDirList > 0);

	# remove remote files
	foreach $tree (@remoteTempFileList) {
		System("ssh $tree->{host} rm -rf \"$tree->{file}\"", 7);
	}
}

END { removeTempFiles() if (!$DONT_REMOVE_TEMP_FILES && !$ENV{DONT_REMOVE_TEMP_FILES}); }	# perl shutdown

sub resourcePath { my ($resource) = @_;
	foreach $path (@INC)
	{
		return "$path/$resource" if (-e "$path/$resource");
	}
	return undef;
}
sub resourcePathesOfType { my ($resource, $type, $subPath) = @_;
	my ($list, $thisPath) = ([]);
	foreach $path (@INC)
	{	$thisPath = defined($subPath)? "$path/$subPath": $path;
		push(@{$list}, map { "$thisPath/$_"; } grep(/\.$type$/, dirList($thisPath)));
	}
	return $list;
}
sub firstFile { my ($filePath, $dirs, $extensions, $c) = @_;
	my $p = splitPathDict($filePath);
	# <!> changed [23.8.2003]: $p->{base} -> $p->{basePath}
	my $base = $c->{useBase}? $p->{base}: $p->{basePath};
	foreach $dir ($p->{directory}, @$dirs) {
		foreach $ext ($p->{extension}, @$extensions) {
			my $file = firstDef($dir, '.'). "/$base". ($ext ne ''? ".$ext": '');
			$file =~ s{^~}{$ENV{HOME}}o if (!$c->{dontInterpolateHome});
			Log("firstFile: $file", 7);
			return $file if -e $file;
		}
	}
	return undef;
}
sub firstFileLocation { my ($filePath, $c, @dirs) = @_;
	if (ref($c) ne 'HASH') {
		@dirs = ($c, @dirs);
		$c = {};
	}
	return firstFile($filePath, [@dirs], undef, $c);
}
sub readFileFirstLocation { my ($filePath, $c, @dirs) = @_;
	if (ref($c) ne 'HASH') {
		push(@dirs, $c) if (defined($c));
		$c = {};
	}
	my $location = firstFileLocation($filePath, @dirs);
#	return (readFile($location), $location); # <!> not equivalent dt list vs scalar ctxt
	return undef if (!defined($location));
	my $f = readFile($location, undef, $c->{encoding});
	return $c->{returnPath}? { path => $location, file => $f }: $f;
}

# search for filename $fileName in @paths
# if not found use $c->{default} if defined
# if $c->{configPaths} is defined prepend to @paths
sub readConfigFile { my ($fileName, $c, @paths) = @_;
	@paths = ('.', "$ENV{HOME}/MyLibrary/Configs", "$ENV{HOME}/Library/Configs",
		"/Library/Configs", "/MyLibrary/Configs", '/'
	) if (!@paths);

	if (ref($c) ne 'HASH') {
		push(@paths, $c) if (defined($c));
		$c = {};
	}
	unshift(@paths, @{$c->{paths}}) if (defined($c->{paths}));
	Log('readConfigFile: pathes: '. join(':', @paths), 7);
	my $plistFile = readFileFirstLocation($fileName, $c, @paths);
	my $plist;
	if (!defined($plistFile)) {
		die "Config file $fileName not found" if (!defined($c->{default}));
		$plist = $c->{default};
	} else {
		$plist = $c->{returnPath}? propertyFromString($plistFile->{file}): propertyFromString($plistFile);
	}
	return $c->{returnPath}
	? { path => $plistFile->{path}, propertyList => $plist } : $plist;
}
sub writeConfigFile { my ($path, $config) = @_;
	writeFile($path, stringFromProperty($config));
}

sub interpolatedPropertyFromString { my ($s, $hashNames) = @_;
	return undef() if ($s eq '');
	$hashNames = ['ENV'] if (!defined($hashNames));
	my $hashNameRe = join('|', @{$hashNames});
	$s =~ s{\$($hashNameRe)\{(.*?)\}}{${$1}{$2}}ge;
	return propertyFromString($s);
}

sub interpolatedPlistFromPath { my ($configPath, $hashNames) = @_;
	if (! -e $configPath) {
		Log("No plist file exists at: $configPath.", 4);
		return undef();
	}
	my $plist = readFile($configPath);
	return interpolatedPropertyFromString($plist, $hashNames);
}

sub handleLength { my ($handle)=@_;
	my ($orig, $len)=(tell($handle));
	seek($handle,0,2), $len=tell($handle), seek($handle,$orig,0);
	return $len;
}
sub fileLength { my ($path)=@_;
	open(__PATHLENGTH, $path);
	my $length=handleLength(\*__PATHLENGTH);
	close(__PATHLENGTH);
	return $length;
}
sub readCommand { my ($command, $logLevel, $doLogOnly, $c) = @_;
	$logLevel = 6 if (!defined($logLevel));
	if ($command =~ m{\|}o || $c->{viaSystem}) {	# handle piping within $command which is not dealt with by open
		my $o = SystemWithInputOutput($command, undef, $logLevel, $doLogOnly, $c);
		return $o->{output};
	}
	return undef if (!open(COMMANDOUTPUT, "$command|"));
	my $buffer = '';
	while (<COMMANDOUTPUT>) { $buffer .= $_; }
	close(COMMANDOUTPUT);
	return $buffer;
}
sub write2Command { my ($command, $input) = @_;
	return undef if (!open(PP_COMMAND, "|$command"));
	print PP_COMMAND $input;
	close(PP_COMMAND);
}

# host can be a hash with keys:
# host, from, to
# <!> decryption does not work yet for stdin
# <!> stdinLength set to 1e7
sub readFile { my ($path, $host, $encodingFrom) = @_;
	return undef if ($path eq '');
	my ($handle, $encodingTo, $buffer, $filter, $c) = ($path, 'utf8', '', '', undef);

	if (ref($host) eq 'HASH') {
		$c = $host;
		$encodingFrom = $c->{from};
		$encodingTo = firstDef($c->{to}, 'utf8');
		$host = $c->{host};
	}

	my $fifo = undef;
	if (ref($c->{decrypt}) eq 'HASH') {
		$fifo = tempFileName("/tmp/.encryptionPipe");
		System("mkfifo -m 0700 $fifo", 6);
		if (!fork()) { writeFile($fifo, $c->{decrypt}{passwd}."\n"); exit(0); }

		$filter = " openssl aes-256-cbc -d -pass file:$fifo -salt |";
	}

	if (defined($host) && $host ne 'localhost') {
		return undef if (!open($handle, "ssh $host cat '$path' |$filter"));
		$buffer = readFileHandle($handle);
		close($handle);
	} else {
		my $l;
		if (!defined($path)) {
			$handle = \*STDIN;
			$l = firstDef($c->{stdinLength}, 1e7); #handleLength($handle);
		} else {
			if ($filter ne '') { $filter = "cat '$path' | $filter"; } else { $filter = $path; }
			return undef if ((! -e $path && !($path =~ m{[|<>]}o))
			|| !open($handle, $filter));
			$l = fileLength($path);
		}
		#read($handle, $buffer, handleLength($handle), 0);
		read($handle, $buffer, $l, 0);
		close($handle) if (defined($path));
	}
	if (defined($encodingFrom)) {
		eval("use Encode;");
		Encode::from_to($buffer, $encodingFrom, $encodingTo);
	}
	unlink($fifo) if (defined($fifo));
	return $buffer;
}

# $c/$doMakePath: group
# <!> append not supported for remote host
sub writeFile { my ($path, $buffer, $doMakePath, $fileMode, $dirMode, $host) = @_;
	my ($c, $group);
	if (ref($doMakePath) eq 'HASH') {
		$c = $doMakePath;
		($doMakePath, $fileMode, $dirMode, $host, $group) = @$c{
		('doMakePath','fileMode','dirMode','host','group')};
	}
	if ($c->{encodeFrom} ne 'raw') {
		my $enc = firstDef($c->{encodeFrom}, 'utf8');
		eval("use Encode;");
		$buffer = encode($enc, $buffer);
	}
	if (defined($host)) {
		my $tmpWrite = tempFileName('/tmp/writeFile');
		writeFile($tmpWrite, $buffer);
		System("scp $tmpWrite $host:$path 2>/dev/null", 6);
	} else {
		my $i;
		if (defined($c->{backupCount})) {
			Unlink(sprintf("%s.%d", $path, $c->{backupCount}), 6);
			for ($i = $c->{backupCount}; $i > 1; $i--) {
				Rename(sprintf("%s.%d", $path, $i - 1),	undef, sprintf("%s.%d", $path, $i), 6);
			}
			Rename($path,	undef, "$path.1", 6);
		}
		if ($doMakePath)
		{	my ($dir) = ($path =~ m{(.*)/[^/]+}o);
			if ($dirMode) { mkpath([$dir], 0, $dirMode); }
			else { mkpath([$dir], 0); }
		}
		my $openPostf = defined($c->{encoding})? ":encoding($c->{encoding})": '';
		if (uc($c->{append}) eq 'YES') { return undef if (!open(WRITEFILE, ">>$openPostf", $path));
		} else {						 return undef if (!open(WRITEFILE, ">$openPostf", $path)); }
		syswrite(WRITEFILE, $buffer, length($buffer), 0);
		close(WRITEFILE);
		chmod($fileMode, $path) if ($fileMode); # chmod needs umask
		if (defined($group)) {
			my $gid = getgrnam($group);
			chown($>, $gid, $path);
		}
	}
	return 0;
}
sub readStdin { my($ret);
	while (defined($_ = <STDIN>)) { $ret.=$_; }
	return $ret;
}
sub readFileHandle { my ($typeGlobRef)=@_;
	my($ret);
	while (defined($_ = <$typeGlobRef>)) { $ret.=$_; }
	return $ret;
}
sub readFileByLines { my($path)=@_;
	return undef if (!open(READFILE,$path));
	my $buffer = '';

	while (defined($_ = <READFILE>)) { $buffer .= $_; }
	close(READFILE);
	return $buffer;
}

sub searchOutputPattern { my ($pattern,$cmd)=@_;
	my ($tmpfile,$outp)=tempFileName('/tmp/searchoutp');
	system("$cmd > $tmpfile");
	$outp=readFile($tmpfile);
	unlink($tmpfile);
	return $outp=~s/$pattern//g;
}

# Sandboxed file operations
sub Mkpath { my ($pathes, $logLevel) = @_;
	foreach $path (ref($pathes) eq 'ARRAY'? @$pathes: ($pathes)) {
		Log("Mkpath: $path", $logLevel);
		mkpath($path) if (!$main::__doLogOnly);
	}
}

sub MkdirOnHost { my ($pathes, $host, $logLevel) = @_;
	foreach $path (ref($pathes) eq 'ARRAY'? @$pathes: ($pathes)) {
		System("ssh $host mkdir '$path'", $logLevel);
	}
}
sub Mkdir { return fileOperation(\&Mkpath, \&MkdirOnHost, @_); }

sub standardMapper { my ($f, $fr, $to) = @_; return splitPathDict($_)->{file}; }
# three modes of operation
# 1: move files from dir $from, named $files (relatively) to dir $to
# 2: if $files is undef rename $from to $to
# 3: $from is array, $files is array then scalar product of $from x $files with $files being [$from, $to]
#	is executed
sub Rename { my ($from, $files, $to, $logLevel, $c) = @_;
	my @stack;
	# <p> case 3
	if (!defined($to) && ref($files) eq 'ARRAY' && ref($from) eq 'ARRAY') {
		@stack = ( map { my $f = $_;
			( map { { from => "$_/$f->[0]", to => "$_/$f->[1]" } } @$from )
		} @$files );
	# <p> case 2
	} elsif (!defined($files)) {
		@stack = ref($from) eq 'ARRAY'
			? map { { from => $from->[$_], to => $to->[$_] } } 0..$#$from
			: ( { from => $from, to => $to } );
	# <p> case 1
	} else {
		my $m = firstDef($c->{mapper}, \&standardMapper);
		@stack = ( map { { from => "$from/$_", to => "$to/". $m->($_, $from, $to) } } @$files );
	}
	foreach $m (@stack) {
		Log("Rename: $m->{from} --> $m->{to}", $logLevel);
		Mkpath(splitPathDict($m->{to})->{dir}, $logLevel + 1) if ($c->{mkpath});
		rename($m->{from}, $m->{to}) if (!$main::__doLogOnly);
	}
}
sub Move { my ($from, $to, $logLevel, $c) = @_;
	Rename($from, undef, $to, $logLevel, $c);
}
sub Symlink { my ($from, $to, $logLevel, $c) = @_;
	Log("Symlink: $from --> $to", $logLevel);
	symlink($from, $to)  if (!$main::__doLogOnly);
}

# <!> reinterfaced to recurseDir, tb tested <t>
sub	scanDir { my($dstPath, $basePath, $path, $fct, $obj)=@_;
	my $c = { dstPath => $dstPath, basePath => $basePath, path => $path, f => $fct,
		lengthBase => length($basePath)
	};
	depthSearchDir($path, sub { my ($path, $c) = @_;
		my $sp = splitPathDict($path);
		return $c->{f}->("$c->{dstPath}/$sp->{file}", $sp->{dir}, $sp->{file}, $c->{basePath}, $c);
	}, $c);
}

# $f callback function
# $c (the context):
#	noDirs: should the function be triggered for dirs
#	context: function argument
#	fBranch: function controlling entering of subdirs

sub depthSearchDirLeaf { my ($path, $c) = @_;
	$c->{f}->($path, $c) if (
		!(-d $path && uc($c->{noDirs}) eq 'YES')
	&&	!(-l $path && uc($c->{noSymbolicLinks}) eq 'YES') );
}
sub	depthSearchDirBranch { my($path, $c) = @_;
	return 	if ($c->{maxDepth} && $c->{depth} >= $c->{maxDepth});
	$c->{depth}++;
	my @list = dirList($path, $c->{host});
	foreach $p (@list) {
		my $npath = "$path/$p";
		$c->{fullPath} = $npath;
		next if (-d $npath && defined($c->{fBranch}) && !$c->{fBranch}->($p, $c));
		depthSearchDirBranch($npath, $c)
			if (-d $npath && !-l $npath && !defined(which($npath, $c->{exclusions})));
		depthSearchDirLeaf($npath, $c);
	}
	$c->{depth}--;
	return;
}

sub	depthSearchDir { my($path, $f, $c) = @_;
	$c = { %$c, depth => 0, f => $f };
	depthSearchDirBranch($path, $c);
	depthSearchDirLeaf($path, $c);
}

# find analogon
# $returnDirs determines whether dirs are included in return list
sub findDir { my ($path, $returnDirs) = @_;
	my $l = [];
	depthSearchDir($path, sub { my ($p, $c) = @_;
		push(@{$c->{files}}, normalizedPath($p));
	}, { files => $l, noDirs => $returnDirs? 'NO': 'YES'});
	return $l;
}

my @StatComps = ('dev', 'ino', 'mode' , 'nlink', 'uid', 'gid', 'rdev',
	'size', 'atime', 'mtime', 'ctime', 'blksize', 'blocks');
sub Stat { my ($path) = @_;
	return makeHash(\@StatComps, [stat($path)]);
}

sub statDict { my ($path) = @_;
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
		$atime,$mtime,$ctime,$blksize,$blocks) = stat($path);
	my ($name,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell,$expire) = getpwuid($uid);
	my ($gname,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell,$expire) = getgrgid($gid);
	return {
		exists => -e $path,
		dev => $dev, inode => $ino, mode => $mode, nlink => $nlink,
		uid => $uid, gid => $gid,
		rdev => $rdev, size => $size, atime => $atime, mtime => $mtime, ctime => $ctime,
		blksize => $blksize, blocks => $blocks, uname => $name, gname => $gname
	};
}

sub copyFiles { my($dstPath,$srcPath,$object,$basePath,$filter)=@_;
	my($readPath,$writePath,$d,$ino,$mode,$nlink);
	$readPath=$srcPath.'/'.$object;
	$writePath=$dstPath.'/'.$object;

	($d,$ino,$mode,$nlink,$d,$d,$d,$d,$d,$d,$d,$d,$d)=lstat($readPath);
	if (&{$filter}($readPath))
	{	if (-d $readPath)
		{	print STDERR "Couldn't create $writePath\n" if (!mkpath($writePath,0,0775));
		} else {
			copy($readPath,$writePath,1024*1024);
			#chmod($mode,$writePath);
		}
	}
	return 0;
}

sub RmdirOnHost { my ($path, $host, $logLevel) = @_;
	System("ssh $host rmdir '$path'", $logLevel);
}
sub RmdirLocal { my ($p, $logLevel) = @_;
	Log("Removing dir: $p", $logLevel);
	rmdir($p) if (!$main::__doLogOnly);
}
sub Rmdir { return fileOperation(\&RmdirLocal, \&RmdirOnHost, @_); }

sub Unlink { my ($p, $logLevel, $c) = @_;
	my @files = (ref($p) eq 'ARRAY'? @$p: $p);
	Log("Removing file(s): ". join(' ', @files), $logLevel);
	if (!$main::__doLogOnly && $c->{secureDelete}) {
		foreach $f (@files) { writeFile($f, ' ' x fileLength($f)) }
	}
	unlink(@files) if (!$main::__doLogOnly);
}

sub	removeEmptySubdirs { my($path, $logLevel) = @_;
	my @dirs = (ref($path) eq 'ARRAY'? @$path: $path);
	foreach $dir (@dirs) {
		# rmdir removes only, if empty
		Log("Removing empty dirs from: $dir", $logLevel);
		depthSearchDir($dir, sub { my ($p) = @_; Rmdir($p) if (-d $p);	});
	}
}

sub	removeBrokenLinks { my($path, $logLevel) = @_;
	my @dirs = (ref($path) eq 'ARRAY'? @$path: $path);
	foreach $dir (@dirs) {
		depthSearchDir($dir, sub { my ($p) = @_;
			my $l = readlink($p);
			my $lSp = splitPathDict($l);
			my $lDst = $lSp->{isRelative}? splitPathDict($p)->{dir}. '/'. $l: $l;
			Unlink($p) if (-l $p && ! -e $lDst);
		});
	}
}

# $fileDict contains known files relative to $path.
sub whichFilesInTree { my ($path, $fileDict, $o) = @_;
	my $o = { %$o, noDirs => 'YES', orphans => [], present => []};
	depthSearchDir($path, sub { my ($p, $c) = @_;
		my $file = substr($p, length($path) + 1);
		push(@{$c->{orphans}}, $file) if (!defined($fileDict->{$file}));
		push(@{$c->{present}}, $file) if (defined($fileDict->{$file}));
	}, $o);
	return { orphans => $o->{orphans}, present => $o->{present},
		broken => [ grep { ! -e "$path/$_" } (keys %{$fileDict}) ]};
}

# $o: options: maxDepth, exactDepth: only store files at that depth
#	other options passed to depthSearchDir
sub dirListDeep { my ($path, $o) = @_;
	my ($host, $pathLocal) = ($path =~ m{^(?:([^/]+?):)?(.*)$}o);
	# <i> implement fileManager
	die 'remote dirListDeep not supported' if ($host ne '' && $host ne 'localhost');
	$host = '' if ($host eq 'localhost');
	my $c = { %$o, maxDepth => firstDef($o->{maxDepth}, $o->{exactDepth}),
		exactDepth => $o->{exactDepth}, files => [], host => $host };
	depthSearchDir($pathLocal, sub { my ($p, $c) = @_;
		my $file = substr($p, length($pathLocal) + 1);
		push(@{$c->{files}}, $file)
			if (!defined($c->{exactDepth}) || $c->{depth} == $c->{exactDepth});
	}, $c);
	return @{$c->{files}};
}

# $fileDict contains known files relative to $path (as keys). All other files will be returned
#	<!> skipSymbolicLinks currently not heeded by depthSearchDir but hard coded
sub searchOrphanedFiles { my ($path, $fileDict, $o) = @_;
	$o = { noSymbolicLinks => 'YES', %$o };
	return whichFilesInTree($path, $fileDict, $o)->{orphans};
}
# $fileDict contains known files relative to $path (as keys). Returns files in dict but not in filesystem
sub searchMissingFiles { my ($path, $fileDict, $o) = @_;
	$o = { noSymbolicLinks => 'YES', %$o };
	return whichFilesInTree($path, $fileDict, $o)->{broken};
}

sub copyAll { return 1; }

sub copyTree { my($dstPath,$srcPath,$filterFct)=@_;
	$filterFct=\&copyAll if (!defined($filterFct));
	scanDir($dstPath,$srcPath,$srcPath,\&copyFiles,$filterFct);
}

sub processList {
	open (__PS, "ps -ax|");
		my $list=readFileHandle(\*__PS);
	close(__PS);
	return $list;
}
sub pidsForWordsPresentAbsent { my ($presentWord, $absentWord)=@_;
	my (@prcs, $prcs,$process, @selected);
	@prcs=($prcs=processList())=~m{^\s*[0-9]+.*$presentWord.*$}ogm;
	foreach $process (@prcs)
	{	next if (defined($absentWord) && $process=~m{$absentWord});
		($pid)=$process=~m{\s*([0-9]+)}o;
		push(@selected, $pid);
	}
	return @selected;
}

sub dirList { my($path, $host) = @_;
	my @list;
	if ($host ne '' && $host ne 'localhost') {
		my $remoteHandle = "remote-$path";
		return undef if (!open($remoteHandle, "ssh $host ls $path |"));
		@list = split(/\n/o, readFileHandle($remoteHandle));
		close($remoteHandle);
	} else {
		opendir(DIRLISTFH, $path);	# || die "can't opendir $some_dir: $!";
			@list = grep { !/^\.+$/ } readdir(DIRLISTFH);	# chop off '.', '..'
		closedir(DIRLISTFH);
	}
	return sort @list;
}
sub dirListPattern { my ($prefix, $postfix, $o) = @_;
	my $sp = splitPathDict($prefix);
	my @files;
	if ($o->{recursive}) {
		my $r = System('find '. qs($sp->{dir}), 5, undef, { returnStdout => 'YES' });
		@files = map { substr($_, length($sp->{dir})) } split(/\n/, $r->{output});
	} else {
		@files = dirList(firstDef($o->{asDir}? $prefix: $sp->{dir}, '.'),
			defined($o)? $o->{host}: undef);
	}
	@files = grep { /^$sp->{file}.*($postfix)$/ } @files;
	@files = map { "$sp->{dir}/$_" } @files if (uc($o->{returnDir}) eq 'YES');
	@files = sort { $a cmp $b } @files if ($o->{sort});
	return @files;
}
sub fileList { my ($prefix, $o) = @_;
	return dirListPattern($prefix, undef, $o);
}
sub FileList { my ($prefix, $postf, $o) = @_;
	my $sp = splitPathDict($prefix);
	return dirListPattern($sp->{path}, undef, { host => $sp->{host} });
}

sub normalizedPath { my($path, $sep, $doSlashes, $beURLaware, $beAbsolute) = @_;
	my $c = firstDef($sep, {});
	if (ref($c) eq 'HASH') {
		$sep = firstDef($c->{sep}, $c->{separator}, '/');
		$doSlashes = firstDef($c->{doSlashes}, 1);
		$beURLaware = firstDef($c->{beURLaware}, 0);
		$beAbsolute = firstDef($c->{beAbsolute}, 0);
	}

	if ($beAbsolute && substr($path, 0, 1) ne '/') {
		$path = substr(`pwd`, 0, -1). "/$path";
	}
	# URLawareness means that m{[a-z]+//:} will be skipped
	if ($doSlashes)	# if ($beURLaware) then exclude the double slashed url-qualifier
	{
		if ($beURLaware) { my ($type, $protocol, $urlPath) = ($path =~ m{(([a-z]+:)?//)?(.*)}o);
			$urlPath =~ s{/+}{/}go;
			$path = $type.$urlPath;
#			$path = ($protocol ne ''? $protocol: 'http:')."//$urlPath";
#		if ($beURLaware) { my ($type, $urlPath) = ($path =~ m{([a-z]+://)?(.*)}o);
#			$urlPath =~ s{/+}{/}go, $path = $type.$urlPath;
		} else { $path=~s{/+}{/}go; }		#mult slashes are like single slashes
	}
	# . elimination before .. dt .. must ignore any .
	#	eliminate . components: here seems to be some bug <b>
	$path =~ s{(^|/)\./+}{$1}og;			#g option is safe here (dt limited scope)
	#<A><b> succeding '..' prevent g option
	while ($path=~s{(^|/)[^/]*/\.\.(/|$)}{$1$2}o) {}
	$path =~ s{/$}{}sog if ($c->{removeTrailingSlash});
	return $path;
}
sub relativePath { my($absCurr, $absDest, $sep, $ignoreCase)=@_;
	$sep = firstDef($sep, '/');
	#	trailing null fields are stripped
	my ($curS,$curD)=(normalizedPath($absCurr), normalizedPath($absDest));
	my @curr=($curS eq $sep)? (''): split(/$sep/, $curS);
	my @dest=($curD eq $sep)? (''): split(/$sep/, $curD);
	my ($i, $app);
#print "Path:",join('|',@curr),"\n";
	for ($i=0; $i<=$#curr; $i++)
	{
		if ($ignoreCase) {
			last if (lc($curr[$i]) ne lc($dest[$i]));
		} else {
			last if ($curr[$i] ne $dest[$i]);
		}
	}
	$app=(((chop($curD) eq $sep) && ($#dest-$i>=0))? $sep: '');
	return "..$sep" x ($#curr-$i).join($sep,splice(@dest,$i)).$app;
}
sub quoteRegex { return join('\\',split(/(?=\.|\?|\=|\*|\\)/,$_[0])); }

sub redirectInOut { my($saveName, $inPath, $outPath)=@_;
	open($saveName.'OUT', ">&STDOUT");
	open($saveName.'IN', "<&STDIN");
	open(STDIN, $inPath);
	open(STDOUT, ">$outPath");
}
sub restoreRedirect { my($saveName)=@_;
	close(STDIN);
	close(STDOUT);
	open(STDIN, "<&$saveName".'IN');
	open(STDOUT, ">&$saveName".'OUT');
}

sub germ2ascii { my($str)=@_;
	die "germ2ascii has been moved to Locale.pm\nAdd 'use Locale' after 'use TempfileNames.";
}

sub fileLock { my($handle) = @_;
	my $lock = pack('s s l l s', &F_WRLCK, 0, 0, 0, 0);
	my $r = fcntl($handle, &F_SETLKW, $lock);
	return $r != 0;
}
sub fileUnlock { my ($handle) = @_;
	my $lock = pack('s s l l s', &F_UNLCK, 0, 0, 0, 0);
	return fcntl($handle, &F_SETLK, $lock);
}

sub appendStringToPath { my ($strRef, $path, $c) = @_;
#	print "Will append to path:$path\n";
	open(APPEND_HANDLE, ">>$path");
		if ($c->{lockFcntl} && fileLock(\*APPEND_HANDLE)) {
			Log("Couldn't lock file for appending: '$path'", 4);
			return -1;
		}
		print APPEND_HANDLE (ref($strRef) eq ''? $strRef: $$strRef);
		fileUnlock(\*APPEND_HANDLE) if ($c->{lockFcntl});
	close(APPEND_HANDLE);
	return 0;
}
sub pipeStringToCommand { my ($strRef, $cmd, $logLevel)=@_;
#	print "Will pipe through:$cmd\n";
	Log("print | $cmd", defined($logLevel)? $logLevel: 6);
	open(PIPE_HANDLE, "|$cmd");
		print PIPE_HANDLE (ref($strRef) eq ''? $strRef: $$strRef);
	close(PIPE_HANDLE);
}
sub pipeStringToCommandSystem { my ($strRef, $cmd, $logLevel)=@_;
	my $tmpFile=tempFileName('/tmp/mail');
	writeFile($tmpFile, (ref($strRef) eq ''? $strRef: $$strRef));
#	system("cat $tmpFile| $cmd ; echo >/dev/console '$tmpFile written'");
	System("$cmd < $tmpFile >/dev/console 2>&1", $logLevel);
}

# flags:
#	maxIterations: for iterate eq 'YES' iterate that often. 0: 2^(bitWidth - 1) iterations
sub mergeDictToString { my ($hash, $str, $flags)=@_;
	my $maxIterations = firstDef($flags->{maxIterations}, 100);
	my @keys = grep { defined($hash->{$_}) } keys(%{$hash});
	my $doIterate = uc($flags->{iterate}) eq 'YES';
	my $keysRe = uc($flags->{keysAreREs}) eq 'YES';
	if (uc($flags->{sortKeys}) eq 'YES' || $doIterate)
	{	@keys = sort { length($b) <=> length($a) } @keys;
	}
	if (uc($flags->{sortKeysInOrder}) eq 'YES')
	{	@keys = sort { $a <=> $b } @keys;
	}
	my $str0;
	do {
		$str0 = $str;
		foreach $key (@keys)
		{	if ($keysRe) {	$str =~ s/$key/$hash->{$key}/sg; }
			else {			$str =~ s/\Q$key\E/$hash->{$key}/sg; }
			# need to start from beginning to retain length order
			last if ($doIterate && $str ne $str0);
		}
	} while ($doIterate && ($str ne $str0) && --$maxIterations);
	return $str;
}

sub trimmStr { my($str)=@_;	#remove whitespace at both ends of string
	#$str =~ s/^\s+|\s+$//g;
	($str) = ($str =~ m{^\s*(.*?)\s*$}so);
	return $str;
}

#	remove whitespace at both ends of string, collapse to single space inside
sub deepTrimmStr { my($str)=@_;
	$str=~s/^\s+|\s+$//og;
	$str=~s/\s+/ /og;
	return $str;
}
sub removeWS { my($str)=@_;	#remove all whitespace inside string
	$str=~s/\s+//og;
	return $str;
}

sub prefix { my ($s, $sep) = @_;
	($s eq '')? '': $sep.$s;
}
sub postfix { my ($s, $sep) = @_;
	($s eq '')? '': $s.$sep;
}
sub circumfix { my ($s, $sepPre, $sepPost) = @_;
	postfix(prefix($s, $sepPre), $sepPost)
}

sub lcPrefix { my (@s) = @_;
	my $minL = min(map { length($_) } @s);
	for (my $i = 0; $i < $minL; $i++) {
		for (my ($c, $j) = (substr($s[0], $i, 1), 1); $j < @s; $j++) {
			return substr($s[0], 0, $i) if (substr($s[$j], $i, 1) ne $c);
		}
	}
	return substr($s[0], 0, $minL);
}


sub mapTr { my ($s, $pat, $subst) = @_;
	eval "\$s =~ tr{$pat}{$subst}";
	return $s;
}
sub mapS { my ($s, $pat, $subst) = @_;
	$s =~ s{$pat}{$subst}seg;
	return $s;
}

#	<p> log level conventions
#	Lev	Comment
#-----------------------------------------------------------------------
#	0	nothing is logged
#	1	may be logged on regular use [<10 lines per app call]
#	2	end user information which may be logged with a verbose flag
#	3	more verbosity: still user information
#	4	debugging information which may be turned on on regular usage
#	5	development only logging
#	6	debugging only logging: app becomes unusable on regular usage
#	>6	think what you want

sub setLogVerbosity { my ($verbosityLevel) = @_;
	$__verbosity = $verbosityLevel;
}
sub verbosityLevel { return $__verbosity; }

#	<g> global here: $__verbosity, $__logPrefix
sub initLog { my ($verbosityLevel)=@_;
	setLogVerbosity($verbosityLevel);
	$0 =~ /[^\/]+$/o;
	$__logPrefix = $&."[$$]: ";
}
sub setLogOnly { my ($doItOrNot) = @_;
	$main::__doLogOnly = $doItOrNot;
}

# <!> 4.7.2001: this is hard change: log -> Log not to overwrite the internal function
sub Log { my ($message, $level)=@_;
	my $prefix = $level < 0? '': $__logPrefix;
	$level = -$level if ($level < 0);
	initLog(4) if (!defined(verbosityLevel()));
	$level = 1 if (!defined($level));
	return if ($level > verbosityLevel());
	
	print STDERR $prefix.$message."\n" if ($level ne 'NO');
}

# <N> maybe through the getStandardOptions() function
#	$__doLogOnly might be moved to this package
# if $redirect is set to numeric 1 it is supposed to silence output
# if $redirect is a string it supposedly contains redirection (sh) syntax
sub System { my ($cmd, $loglevel, $doLogOnly, $c) = @_;
	$c = (ref($c) eq 'HASH')? { %$c } : { host => $c };	# copy $c
	my ($prefix, $postfix) = ('', '');
	my ($exit, $fifo, $cdcmd) = (-1, undef);
	$doLogOnly = $main::__doLogOnly if (!defined($doLogOnly));
	# <p> save descriptor redirections
	my $descriptorRedirections = join(' ', ($cmd =~ m{\d>\&\d}sog));
	# <p> remove descriptor redirections from $cmd
	$cmd =~ s{\d>\&\d}{}sog;

	if (uc($c->{returnStdout}) eq 'YES') {
		my $tmpOutput = tempFileName("/tmp/perl_$ENV{USER}/tempIO-$ENV{USER}-o",
			undef, {doTouch => 1});
		writeFile($tmpOutput, '');
		$c->{redirect}{output} = $tmpOutput;
	}
	if (uc($c->{returnStderr}) eq 'YES') {
		my $tmpErr = tempFileName("/tmp/perl_$ENV{USER}/tempIO-$ENV{USER}-e",
			undef, {doTouch => 1});
		writeFile($tmpErr, '');
		$c->{redirect}{error} = $tmpErr;
	}
	if (defined($c->{stdinFrom})) {
		$c->{redirect}{input} = $c->{stdinFrom};
	}

	if (ref($c) eq 'HASH') {
		$c = { %$c };	# make a copy of $c
		if ($c->{silent} == 1) {
			$postfix = ' 1>/dev/null 2>/dev/null';
		}
		if (ref($c->{redirect}) eq 'HASH') {
			#<!> assuming sh/bash
			$prefix .= "cat '$c->{redirect}{input}' | " if (defined($c->{redirect}{input}));
			$postfix .= " > '$c->{redirect}{output}'" if (defined($c->{redirect}{output}));
			$postfix .= " 2> '$c->{redirect}{error}'" if (defined($c->{redirect}{error}));;
		} 
		if (ref($c->{encrypt}) eq 'HASH') {	# <!> clashes with redirect
			$fifo = tempFileName("/tmp/.encryptionPipe");
			System("mkfifo -m 0700 $fifo", 6);
			if (!fork()) { writeFile($fifo, $c->{encrypt}{passwd}."\n"); exit(0); }
			# <!> proper file handling
			$cmd .= " | openssl aes-256-cbc -e -pass file:$fifo -salt -out '$c->{encrypt}{output}'";
		} 
		if (ref($c->{decrypt}) eq 'HASH') {	# <!> clashes with redirect
			$fifo = tempFileName("/tmp/.encryptionPipe");
			System("mkfifo -m 0700 $fifo", 6);
			if (!fork()) { writeFile($fifo, $c->{decrypt}{passwd}."\n"); exit(0); }
			# <!> proper file handling
			$cmd = "openssl aes-256-cbc -d -pass file:$fifo -salt -in '$c->{decrypt}{input}' | ". $cmd;
		}
		my $dir = Set::firstDef($c->{dir}, '.');
		$cdcmd = "cd '$dir'" if (defined($c->{dir}));
	}
	# <p> re-introduce descriptor redirections
	$postfix .= ' '. $descriptorRedirections;
	# <!> logging control via global variable
	if (defined($c->{host})) {
		my $fcmd = "${prefix}ssh $postfix $c->{host} ".
			($cdcmd ne ''? "'$cdcmd ; ": "'"). "$cmd'";
		Log($fcmd, $loglevel);
		$exit = $c->{returnStdout}? `$fcmd`: system($fcmd) if (!$main::__doLogOnly && !$doLogOnly);
	} else {
		my $fcmd = ($cdcmd ne ''? "$cdcmd ; ": ""). $prefix. $cmd. $postfix;
		Log($fcmd, $loglevel);
		$exit = $c->{returnStdout}? `$fcmd`: system($fcmd) if (!$main::__doLogOnly && !$doLogOnly);
	}
	unlink($fifo) if (defined($fifo));

	return {
		returnCode => $exit,
		output => readFile($c->{redirect}{output}),
		error => readFile($c->{redirect}{error})
	} if (defined($c->{redirect}{output}) || defined($c->{redirect}{error}));
	return $exit;
}
sub doLogOnly { return $main::__doLogOnly; }

sub SystemWithInputOutput { my ($cmd, $input, $loglevel, $doLogOnly, $c) = @_;
	my $tmpInput = tempFileName('/tmp/tempIO-i');
	my $tmpOutput = tempFileName('/tmp/tempIO-o');
	my $tmpError = tempFileName('/tmp/tempIO-e');
	writeFile($tmpOutput, '');
	writeFile($tmpError, '');
	writeFile($tmpInput, $input) if (defined($input));
	my $redirect = { output => $tmpOutput, error => $tmpError };
	$redirect->{input} = $tmpInput if(defined($input)); 
	my $ret = System($cmd, $loglevel, $doLogOnly, { %$c, redirect => $redirect });
	return {
		returnCode => $ret,
		output => readFile($tmpOutput),
		error => readFile($tmpError)
	};
}


sub GetOptionsStandard { my @options = @_;
	eval("use Getopt::Long");
	my ($logLevel, $result);
	if (ref($options[0]) eq 'HASH') {
		my $h = $options[0];
		$result = GetOptions(@options, 'help|h', 'logLevel=i', 'doLogOnly', 'config=s');
		$main::__doLogOnly = $h->{doLogOnly};
		$logLevel = $h->{logLevel};
	} else {
		$result = GetOptions(
			'logLevel=i' => \$logLevel,
			'doLogOnly' => \$main::__doLogOnly,
			@options
		);
		setLogVerbosity($verbosity);
	}
	setLogVerbosity($logLevel) if (defined($logLevel));
	return $result;
}

sub cmdNm { $0=~m{/?([^/]*)$}o; return $1; }

# triggers are given as code references in the default dict
# ways to specify triggers
#	define a default with a code ref as value
#	add a '+myOption' option and implement 'doMyOption'
sub callTriggersFromOptions { my ($c, @args) = @_;
	my $didCall = 0;
	my $ret = 0;
	# extract options and detect deep vs non-deep structure
	my $o = defined($c->{o})? $c->{o}: $c;
	foreach $key (keys %{$c->{_triggers}}) {
		#if (defined($o->{$key})) {
		# <!> changed 23.11.2016 due to introduction of default trigger without entry in $c/$o
		# <!> changed back 17.1.2017 due to breaking behaviour
		if (defined($o->{$key})) {
			my $sub = (ref($c->{_triggers}{$key}) eq 'CODE'
				? $c->{_triggers}{$key}
				: 'main::'. $o->{triggerPrefix}. ($o->{triggerPrefix} eq ''? $key: ucfirst($key)));
			$sub =~ tr{-}{_} if (ref($sub) ne 'CODE');
			$didCall = 1;
			$ret += $sub->($c, @args);
		}
	}
	exit($ret) if ($didCall && !$o->{doReturn});
}


%StartStandardScriptOptions = (
	returnDeepStruct => 0, triggerPrefix => 'do', callTriggers => 1, helpOnEmptyCall => 0
);
# example for option === function name
# $main::d = { triggerPrefix => '' };
# $main::d = { triggerDefault => 'myFunction' };
# $main::o = [ '+encryptToHex=s'];

# triggers:
#	triggers are specified as a code reference in defaults, as a +option in options or as 
#	a auto-vivifying default trigger that is called even if no option is given to the program
# $returnDeepStruct returns a dict with elements c, o, cred
#	return a merged dict otherwise
# if an option has a subroutine as a default that subroutine gets called
#	if the options was specified, exits afterwards
# %sso: standard script options
sub StartStandardScript { my ($defaults, $options, %sso) = @_;
	# initialization
	my $o = { %StartStandardScriptOptions, %$defaults, %sso };
	# copy trigger definitions
	my @triggers = grep { ref($o->{$_}) eq 'CODE' } keys %$o;
	my $subs = makeHash([@triggers], [@{$defaults}{@triggers}]);
	# are any arguments present before calling GetOptionsStandard
	my $noArgs = !@ARGV;
	# get subroutine triggers (+options)
	my @options = @$options;
	my $triggerDefault = $defaults->{triggerDefault};
	push(@options, "+$triggerDefault") if (defined($triggerDefault));
	@options = map {
		my ($t, $o, $oa) = ($_ =~ m{^(\+?)([a-z0-9_-]*)(.*)$}i);
		$subs->{$o} = 0 if ($t eq '+');
		$o.$oa
	} (@options, @triggers);
	# <!> reset $o in order to prevent Getopt::Long from calling triggers interpreted as callbacks
	my $od = { %$o, ( map { $_ => undef }  keys %$subs ) };	# option defaults, reset triggers
	my $os = {};	# specified options
	my $result = GetOptionsStandard($os, @options);
	# no triggers triggered?
	my $doTrigger = (int(grep { defined($_) }  @$os{keys %$subs}) == 0 && defined($triggerDefault));
	my %odt = ($doTrigger? ($triggerDefault => 0): ());
	$o = { %$od, %$os, %odt };
	my $programName = cmdNm();

	if ($o->{help} || !$result || ($noArgs && $o->{helpOnEmptyCall})) {
		printf("USAGE: %s $main::usage\n$main::helpText", $programName);
		exit(!$result);
	}
	my $c = {};
	$c = readConfigFile($o->{config}, { default => {}, paths => $o->{configPaths} })
		if (defined($o->{config}));
	my $cred = undef;
	if (defined($o->{credentials})) {
		load('KeyRing');
		$cred = KeyRing->new()->handleCredentials($o->{credentials},
			'.this_cookie.'. $programName) || exit(0)
	}
	my $deepR = { o => $o, c => $c, cred => $cred, _triggers => $subs };
	my $flatR = { %$od, %$c, %$os, %odt, %$cred, _triggers => $subs };
	my $r = $o->{returnDeepStruct}? $deepR: $flatR;
	# handle call triggers, triggering might be delayed
	callTriggersFromOptions($r, @ARGV) if ($o->{callTriggers});
	return $r;
}

#	SplitPath options
# 		$doTestDir makes splitPath to probe the path on Dir Qualitiy
#		if so the whole path is the dir and $fileNameToSubstitue is the filename

sub splitPath { my ($path, $doTestDir, $fileNameToSubstitue)=@_;
	my ($directory, $filename, $ext);
	if ($doTestDir && -d $path)
	{	($directory, $filename, $ext) =
			($path, $fileNameToSubstitue =~ m{^(.*?(?:\.([^/.]*))?)$}o );
	} else {
		($directory, $filename, $ext) = ($path =~ m{^(?:(.*/))?([^/]*?(?:\.([^/.]*))?)$}o);
		# <!> change as of 22.4.2008 <t>: chop off /, if not the root directory
		chop($directory) if (length($directory) > 1);
	}
	return ($directory, $filename, $ext);
}

# returns the following:
#	dir: directory or whole path in case of ambiguitiy (e.g. 'abc')
#	base: filename w/o path, w/o extension
#	extension: filename extension
#	file:	filename w/ extension
#	path:	the input argument
#	basePath:	input argument w/o file extension if present
#	dirComponents:	an array of the dirs leading to the file
#	isRelative:	does not start with '/'

sub splitPathDict { my ($path, $doTestDir, $fileNameToSubstitue, %c)=@_;
	my ($user, $host, $pathN);
	$path = $pathN
		if ((($user, $host, $pathN)
		= ($path =~ m{^(?:(\w+)\@)?(?:(\w+):)(.*)}goi)) && $c{testRemote});
	my ($directory, $filename, $ext) = splitPath($path, $doTestDir, $fileNameToSubstitue);
	my $base = defined($ext)? substr($filename, 0, - length($ext) - 1): $filename;
	my $dirPrefix = defined($directory)? ($directory eq '/'? '/': "$directory/"): '';

	my $lastComponent = $filename;

	if ($filename eq '' && length($path) > 0) {
		my $subSplit = splitPathDict(substr($path, 0, -1));
		$lastComponent = $subSplit->{file};
	}

	return {
		user => $user, host => $host,
		isLocal => !defined($host) || $host eq 'localhost',
		dir => $directory eq ''? undef: $directory, base => $base, extension => $ext, file => $filename,
		path => $path, basePath => $dirPrefix.$base,
		lastComponent => $lastComponent,
		isRelative => substr($path, 0, 1) ne '/',
		dirComponents => [$directory eq '/'? (''): split(/\//, $directory)]	# heed special case <A>
	};
}

#
#	some (loosly) file related output methods
#

# Args:
# 	perc|percentage: percentage to print
# 	width: width of resulting string
sub progressPrint { my ($p, %a) = @_;
	my $w = firstDef($a{width}, 20) - 2;	# remaining width without delimeters
	return '<'. ( '=' x $w ). '>' if ($p == 1);
	# progress position
	my $pp = max(int($p * $w + 0.5), 1);
	my $r = '['. ('=' x ($pp - 1)). '>'. ('-' x ($w - $pp)). ']';
	return $r;
}

sub percentagePrint { my ($count, $max, $hashCount, $file) = @_;
	my $p = $count / $max;
	$hashCount = 20 if (!defined($hashCount));
	$file = \*STDERR if (!defined($file));
	printf $file progressPrint($count/$max, width => $hashCount)
	. sprintf(" %d%% (%d)\r", int($count * 100 / $max + 0.5), $count);
	$file->flush();
}


sub allowUniqueProgramInstanceOnly {
	my ($name) = ($0 =~ m{/?([^/]*)$}o);
	my $processes = readCommand("ps auxw");
	my @instances = ($processes =~ m{\Q$name\E}og);

	if (@instances > 1) {
		Log("An instance of $name is already running. Exiting.");
		exit(0);
	}
}

#
# system methods
#

# that is locale prone <A>
sub ipAddress { my ($dev) = @_;
	$dev = 'eth0' if (!defined($dev));
	my ($ip) = (`/sbin/ifconfig $dev` =~ /inet addr:([^\s]+)/so);
	return $ip;
}

# cave $file handling is not clean <!>
# dirSpec is a directory containing entries:
#	directory: the directory to cd to
#	content: the elements within directory to pack
sub packDir { my ($dirSpec, $destFile) = @_;
	my $error = `cd \"$dirSpec->{directory}\"; tar czf $destFile $dirSpec->{content}`;
	return $error;
}

sub unpackDir { my ($dirSpec, $sourceFile) = @_;
	my $error = `cd \"$dirSpec->{directory}\"; tar xzf $sourceFile`;
	return $error;
}

sub mergePdfs { my ($list, $output) = @_;
	my $cmd = "gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite "
	. "-sOutputFile=$output ". join(' ', @{$list});
	System($cmd, 5);
}

sub diskUsage { my ($path, $o) = @_;
	return undef if (!-e $path);
	my $du = locale()->diskUsage($path) if ($o->{useLocale});
	return $du if (defined($du));
	$du = (`du --summarize $path` =~ m{(\d+)}so);
	return $du;
}

sub testService { my ($MUTEX, $serviceName) = @_;
	my $r = 0;
	$serviceName = $0 if (!defined($serviceName));
	writeFile($MUTEX, '') if (! -e $MUTEX);
	open($MUTEX, $MUTEX);
		return 0 if (!flock($MUTEX, LOCK_EX));
			my $pid = firstDef(readFile("${MUTEX}_pid"), 12345 );
			my ($name) = (`ps -p $pid -w -w -o command=` =~ m{(\S+)\n*$}so);
			if ($name eq $serviceName) {
				$r = 0;
			} else {
				writeFile("${MUTEX}_pid", sprintf("%d", $$));
				$r = 1;
			}
		flock($MUTEX, LOCK_UN);
	close($MUTEX);
	return $r;
}

sub testIfMount { my ($path, $doFollowLink) = @_;
	$doFollowLink = 1 if (!defined($doFollowLink));
	$path = readlink($path) if ($doFollowLink && -l $path);
	$path = normalizedPath($path, { removeTrailingSlash => 1 });
	# <!> linux specific
	my ($isMount) = (`mount` =~ m{ on \Q$path\E}m);
	return !!$isMount;
}

# quote string for bash command line use
sub qw { $_[0] =~ s{"}{\\"}sog; $_[0] }
sub qsB { $_[0] =~ s{\\}{\\\\}sog; return $_[0]; }
sub qsQ { return qw(qsB($_[0])) }
sub qs { my $p = $_[0];
	$p = qsB($p);
	$p =~ s{'}{'"'"'}sog;
	return "'$p'";
}
sub qs2 { my $p = $_[0];
	$p = qsB($p);
	$p =~ s{"}{\\"}sog;
	return "\"$p\"";
}
sub prefix { my ($s, $prefix) = @_;
	return $s eq ''? '': "$prefix$s";
}
sub uqs { my ($t) = @_;
	my $u;
	return $u if (($u) = ($t =~ m{\A"(.*)"\Z}so));
	return $u if (($u) = ($t =~ m{\A'(.*)'\Z}so));
	return $t;
}

#
#	<p> table formatting
#

#%main::tableDesc = ( parameters => { width => 79 },
#	columns => {
#		id => { width => 2, format => '%0*d' },
#		component => { width => -30, format => '%*s' },
#		stratum => { width => -15, format => '%*s' },
#		perc => { width => 4, format => 'percent' }
#	}
#);
%Set::tableFormats = (
	percent => {
		format => '%*.0f%%',
		width => sub { $_[0] - 1 },
		transform => sub { $_[0] * 100 }
	},
	date => {
		format => '%*s',
		width => sub { $_[0] },
		transform => sub { localtime($_[0]) }
	}
);

sub traverseRaw { my ($v, $keys) = @_;
	my @keys = @$keys;
	return $v if (!int(@keys));
	my $key = shift(@keys);

	if (ref($v) eq 'HASH') {
		$v = $v->{$key};
	} else {
		my $code = ref($v)->can($key);
		$v = $v->$code();
		#Log("Col: $c; value:$v; Class: ". ref($v).": ". ref($r). " Method: $m, ", 2);
	}
	return traverseRaw($v, [@keys]);
}

sub traverse { my ($v, $kp) = @_;
	my @keys = split(/[.]/, $kp);
	return traverseRaw($v, [@keys]);
}

sub formatTableHeader { my ($d, $cols) = @_;
	#my $fmt = join(' ', map { $_->{format} } @{$d->{columns}}{@$cols});
	#$fmt =~ s{%0?\*\.?\d?[df]}{%*s}sog;
	my $fmt = join(' ', ('%*s') x int(@$cols));
	my $header = sprintf($fmt, map {
		( -abs($d->{columns}{$_}{width}), ucfirst(firstDef($d->{columns}{$_}{rename}, $_)) )
	} @$cols);
	return $header;
}
sub formatTableRows { my ($d, $t, $cols) = @_;
	my $fmt = join(' ', map {
		firstDef($Set::tableFormats{$_->{format}}{format}, $_->{format})
	} @{$d->{columns}}{@$cols});
	my @rows = map { my $r = $_;
		sprintf($fmt, map { my $c = $_;
			my $col = $d->{columns}{$c};
			my $f = $col->{format};
			my $m = $col->{method};
			my $v = traverse($r, firstDef($col->{keyPath}, $c));
			my $tr = $Set::tableFormats{$f}{transform};
			$v = $tr->($v) if (defined($tr));
			# <p> width
			my $w = $col->{width};
			my $tw = $Set::tableFormats{$f}{width};
			$w = $tw->($w) if (defined($tw));
			($w, $v)
		} @$cols);
	} @$t;
	return @rows;
}
sub formatTableComponents { my ($d, $rows, $cols) = @_;
	return {
		header => formatTableHeader($d, $cols),
		separator => '-' x $d->{parameters}{width},
		rows => [formatTableRows($d, $rows, $cols)]
	};
}
sub formatTable { my ($d, $rows, $cols) = @_;
	$cols = $d->{print} if (!defined($cols));
	my $t = formatTableComponents($d, $rows, $cols);

	return join("\n", ($t->{header}, $t->{separator}, @{$t->{rows}}));
}

sub dateReformat { my ($date, $fmtIn, $fmtOut) = @_;
	return strftime($fmtOut, strptime($date, $fmtIn));
}

sub slurpToTemp {
	my @lines = <>;
	my $tf = tempFileName("/tmp/perl_$ENV{USER}/slurp_pl", undef, { doTouch => 'YES' });
	writeFile($tf, join("\n", @lines));
	return $tf;
}

sub slurpPipeToTemp { my ($cmd) = @_;
	$fh = new IO::File;
    return undef if (!$fh->open("$cmd |"));
	my @lines = <$fh>;
	my $tf = tempFileName("/tmp/perl_$ENV{USER}/slurp_pl", undef, { doTouch => 'YES' });
	writeFile($tf, join("\n", @lines));
	$fh->close;
	return $tf;
}

1;
