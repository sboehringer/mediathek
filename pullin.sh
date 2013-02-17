#
#	pullin.sh
#

( cd  ~/src/privatePerl/ ; tar cf - TempFileNames.pm Set.pm PropertyList.pm ) | tar xf -

