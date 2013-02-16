#
#	mediathekLogic.pm
#Wed Feb  6 21:09:20 CET 2013

use MooseX::Declare;
use MooseX::NonMoose;
use MooseX::MarkAsMethods;

class My::Schema::Result::TvItem {
	# default format: day_title
	method fetchTo(Str $dest, Str $fmt = '%D_%T.flv') {
		my $destPath = $dest. '/'. TempFileNames::mergeDictToString({
			'%T' => $self->title,
			'%D' => main::dateReformat($self->date, '%Y-%m-%d %H:%M:%S', '%Y-%m-%d')
		}, $fmt, { iterative => 'no' });
		TempFileNames::Log("Fetching ". $self->title. " to ". $destPath, 1);
		TempFileNames::Mkpath($dest, 5);
		return TempFileNames::System($self->command. ' -o '. TempFileNames::qs($destPath), 2);
	}
  __PACKAGE__->meta->make_immutable(inline_constructor => 0);
}
