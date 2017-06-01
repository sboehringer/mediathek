#
#	pullin.sh
#

( cd  ~/src/privatePerl/ ; tar cf - TempFileNames.pm Set.pm PropertyList.pm ) | tar xf -
( cd  ~/src/scripts/Net ; tar cf - tidy.pl xml.pl ) | tar xf -
( cd  ~/src/scripts/Conversion ; tar cf - mplayer.pl ) | tar xf -

