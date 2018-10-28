use Test::More;
use Test::Warnings;
use lib '../lib';

use SQLite_File;
use Fcntl;
use File::Spec;

my $t = -d 't' ? 't' : '.';

my %cache;
tie (%cache, 'SQLite_File', File::Spec->catfile($t,"test.sqlite"), (O_RDWR|O_CREAT), 0666);
$cache{123}="data";
delete $cache{123};
# Does not print a warning

$cache{123}="data";
untie %cache;
tie (%cache, 'SQLite_File', File::Spec->catfile($t,"test.sqlite"), (O_RDWR|O_CREAT), 0666);
delete $cache{123};
# Prints: "Use of uninitialized value $i in array element at /usr/lib
# /perl5/site_perl/5.18.2/SQLite_File.pm line 1671."

done_testing;

END {
  unlink File::Spec->catfile($t,"test.sqlite");
}
