# Project

## Installation on current perl versions (2022/05)

Unfortunately, as of May 2022, it is impossible to install the project on a current perl install. I have fixed perl to 5.26.1 using perlbrew. Fixing some module versions allows to run this project. Probably a more recent perl version works, but this is untested.

```
cpanm Moo@2.003004 List::MoreUtils clone aliased Devel::Declare@0.006019 Devel::Declare::Context::Simple@0.006019 Sub::Name Class::Load::XS@0.10 Moose HTTP::Headers@6.14 LWP::Simple@6.31 DBIx::Class::Schema::Loader@0.07049 DBIx::Class::DynamicSubclass@0.03 Data::Dumper::Consise DateTime::Format::Strptime MooseX::KavorkaInfo@0.039 MooseX::NonMoose@0.26 MooseX::Declare@0.43 MooseX::MarkAsMethods
```

I have tried to port the project to Moops but did not manage to get an install with either perl 5.26.1 or 5.34.0. This implies that this project enters legacy status unless progress with Moops happens.

## Description

This project is a command line equivalent to the Mediathekview project on sourceforge (http://zdfmediathk.sourceforge.net). It allows you to set up automatic downloads for programming from German public TV stations. This project is freeloading on the data infrastructure provided by the sourceforge project (refreshing of programming content). Please support the Mediathekview project in maintaining their service in this regard and otherwise.

## Author

Stefan Böhringer <github-projects@s-boehringer.org>

# Release

## Version

This is the current development version from the master branch. Youtube scraping has recently been introduced but not yet documented. The latest stable version is 1.2 available from the releases. It adds proxy support and a number of bug fixes.

## License

This version is licensed under the LGPL 2.0.

## Installation

This project is meant to be small enough to run on a Raspberry Pi. A typical workload requires 100Mb of RAM and should therefore comfortably run on a Raspberry Pi that has no other big loads running.
Dependencies have to be installed manually. Detailed installation instruction are available on the wiki for Raspbian and Opensuse.

# Usage

Get help with

	mediathek-worker.pl --help

A typical scenario consists of conducting a search with

	mediathek-worker.pl --search QUERY

QUERY follows the pattern 'key1:value1;key2:value2' where values are SQL-like patterns and keys are channel, topic, title. For example, 'title:%tagesschau%' searches for titles containing 'tagesschau'. Once a search returns proper results, '--fetch' can be used to download programs. '--addsearch' adds a search permanently causing programs to be downloaded for every ensuing '--autofetch' call. Once a download completes files can be moved or deleted. They are not re-fetched by subsequent auto-fetches. Incomplete downloads are resumed in the next auto-fetch run.

The latest version allows to also download youtube channels and playlists using the same query model. See the wiki for details.

## Further Documentation

More configuration options, troubleshooting and usage scenarios are discussed on the wiki.

## Power of Perl

This project is implemented in just 350 lines of Perl code (initially) including data model, database setup, a clean OO implementation of program logic and self-documentation. It makes use of the DBIx object-relational mapping framework and the Moose OO framework. If you think you can best this implementation in terms of brevity and/or clarity (in Perl or another scripting language), please let me know. One disadvantage of this implementation is that it is slow owing to the Moose part.
