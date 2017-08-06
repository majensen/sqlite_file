# $Id: SQLite_File.pm 16252 2009-10-09 22:26:34Z maj $
#
# converted from Bio::DB::SQLite_File for PAUSE upload
#

=head1 NAME

SQLite_File - Tie to SQLite, with DB_File emulation

=head1 SYNOPSIS

 # tie a simple hash to a SQLite DB file
 my %db;
 tie(%db, 'SQLite_File', 'my.db');

 # tie an array
 my @db;
 tie(@db, 'SQLite_File', 'my.db');

 # tie to a tempfile
 tie(%db, 'SQLite_File', undef);

 # get attributes of the tied object

 $SQLite_handle = (tied %db)->dbh;
 $db_file = (tied %db)->file;

 # use as an option in AnyDBM_File
 @AnyDBM_File::ISA = qw( DB_File SQLite_File SDBM );
 my %db;
 tie(%db, 'AnyDBM_File', 'my.db', @dbmargs)

 # Filter with DBM_Filter

 use DBM_Filter;
 tie(%db, 'SQLite_File', 'my.db');
 (tied %db)->Filter_Push('utf8');
 
=head1 DESCRIPTION

This module allows a hash or an array to be tied to a SQLite DB via
L<DBI> plus L<DBD::SQLite>, in a way that emulates many features of
Berkeley-DB-based L<DB_File>. In particular, this module offers another
choice for ActiveState users, who may find it difficult to get a
working L<DB_File> installed, but can't failover to SDBM due to its
record length restrictions. SQLite_File requires
L<DBD::SQLite>, which has SQLite built-in -- no external application
install required.

=head2 Key/Value filters

The filter hooks C<fetch_key_filter>, C<fetch_value_filter>, C<store_key_filter>, and C<store_value_filter> are honored. L<DBM_Filter> can be used as an API.

=head2 DB_File Emulation

The intention was to create a DBM that could almost completely substitute for 
C<DB_File>, so that C<DB_File> could be replaced everywhere in code by
C<AnyDBM_File>, and things would just work. Currently, it is slightly more 
complicated than that, but not too much more. 

Versions of C<$DB_HASH>, C<$DB_BTREE>, and C<$DB_RECNO>, as well as
the necessary flags (C<R_DUP>, C<R_FIRST>, C<R_NEXT>, etc.) are
imported by using the L<AnyDBM_File::Importer> module. The desired
constants need to be declared global in the calling program, as well
as imported, to avoid compilation errors (at this point). See
L<Converting from DB_File> below.

Arguments to the C<tie> function mirror those of C<DB_File>, and all should 
work the same way. See L<Converting from DB_File>.

All of C<DB_File>'s random and sequential access functions work:

 get()
 put()
 del()
 seq()

as well as the duplicate key handlers

 get_dup()
 del_dup()
 find_dup()

C<seq()> works by finding partial matches, like C<DB_File::seq()>.
The extra array functions ( C<shift()>, C<pop()>, etc. ) are not yet
implemented as method calls, though all these functions (including
C<splice> are available on the tied arrays.

Some C<HASHINFO> fields are functional:

 $DB_BTREE->{'compare'} = sub { - shift cmp shift };

will provide sequential access in reverse lexographic order, for example. 

 $DB_HASH->{'cachesize'} = 20000;

will enforce C<PRAGMA cache_size = 20000>.

=head2 Converting from DB_File

To failover to C<SQLite_File> from C<DB_File>, go from this:

 use DB_File;
 # ...
 $DB_BTREE->{cachesize} = 100000;
 $DB_BTREE->{flags} = R_DUP;
 my %db;
 my $obj = tie( %db, 'DB_File', 'my.db', $flags, 0666, $DB_BTREE);

to this:
  
  use vars qw( $DB_HASH &R_DUP );
  BEGIN {
    @AnyDBM_File::ISA = qw( DB_File SQLite_File )
      unless @AnyDBM_File::ISA == 1; # 
  }
  use AnyDBM_File;
  use AnyDBMImporter qw(:bdb);
  # ...

  $DB_BTREE->{cachesize} = 100000;
  $DB_BTREE->{flags} = R_DUP;
  my %db;
  my $obj = tie( %db, 'AnyDBM_File', 'my.db', $flags, 0666, $DB_BTREE);

=head1 SEE ALSO

L<AnyDBMImporter>, L<DBD::SQLite>, L<DB_File>, L<AnyDBM_File>

=head1 AUTHOR

 Mark A. Jensen < MAJENSEN -at- cpan -dot- org >
 http://fortinbras.us

=head1 CONTRIBUTORS

This code owes an intellectual debt to Lincoln Stein. Inelegancies and
bugs are mine.

Thanks to Barry C. and "Justin Case".

=head1 COPYRIGHT AND LICENSE

(c) 2009-2017 Mark A. Jensen

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut

package SQLite_File;
use base qw/Tie::Hash Tie::Array/;
use strict;
use warnings;
our $VERSION = '0.1000';

use vars qw( $AUTOLOAD ) ;

BEGIN {
    unless (eval "require DBD::SQLite; 1") {
 	croak( "SQLite_File requires DBD::SQLite" );
     }
    use Fcntl qw(O_CREAT O_RDWR O_RDONLY O_TRUNC);
}
use DBI qw(:sql_types);
use File::Temp qw( tempfile );
use Carp;

our @EXPORT = qw( 
                 $DB_HASH $DB_BTREE $DB_RECNO
                 R_DUP R_CURSOR R_FIRST R_LAST
                 R_NEXT R_PREV R_IAFTER R_IBEFORE
                 R_NOOVERWRITE R_SETCURSOR
                 O_CREAT O_RDWR O_RDONLY O_SVWST
		 O_TRUNC
                 );

our $DB_HASH = new SQLite_File::HASHINFO;
our $DB_BTREE = new SQLite_File::BTREEINFO;
our $DB_RECNO = new SQLite_File::RECNOINFO;

# constants hacked out of DB_File:
sub R_DUP  { 32678 }
sub R_CURSOR  { 27 }
sub R_FIRST { 7 }
sub R_LAST  { 15 }
sub R_NEXT  { 16 }
sub R_PREV  { 23 }
sub R_IAFTER  { 1 }
sub R_IBEFORE  { 3 }
sub R_NOOVERWRITE  { 20 }
sub R_SETCURSOR  { -100 }
sub O_SVWST { O_CREAT() | O_RDWR() };

$SQLite_File::MAXPEND = 250;

our $AUTOKEY = 0;
# for providing DB_File seq functionality
our $AUTOPK = 0;

# statement tables
our %STMT = (
    HASH => {
	put     => "INSERT INTO hash (id, obj, pk) VALUES ( ?, ?, ? )",
	put_seq => "INSERT INTO hash (id, obj, pk) VALUES ( ?, ?, ? )",
	get     => "SELECT obj, pk FROM hash WHERE id = ?",
	get_seq => "SELECT id, obj FROM hash WHERE pk = ?",
	upd     => "UPDATE hash SET obj = ? WHERE id = ? AND pk = ?",
	upd_seq => "UPDATE hash SET id = ?, obj = ? WHERE pk = ?",
	del     => "DELETE FROM hash WHERE id = ?",
	del_seq => "DELETE FROM hash WHERE pk = ?",
	del_dup => "DELETE FROM hash WHERE id = ? AND obj = ?",
	sel_dup => "SELECT pk FROM hash WHERE id = ? AND obj = ?",
	part_seq=> "SELECT id, obj, pk FROM hash WHERE id >= ? LIMIT 1"
    },
    ARRAY => {
	put     => "INSERT INTO hash (id, obj) VALUES ( ?, ?)",
	put_seq => "INSERT INTO hash (obj, id) VALUES ( ?, ?)",
	get     => "SELECT obj, id FROM hash WHERE id = ?",
	get_seq => "SELECT id, obj FROM hash WHERE id = ?",
	upd     => "UPDATE hash SET obj = ? WHERE id = ?",
	upd_seq => "UPDATE hash SET obj = ? WHERE id = ?",
	del     => "DELETE FROM hash WHERE id = ?",
	del_seq => "DELETE FROM hash WHERE id = ?"
    }
    );

# our own private index

sub SEQIDX {
    my $self = shift;
    return $self->{SEQIDX} = [] if (!defined $self->{SEQIDX});
    return $self->{SEQIDX};
}

sub CURSOR {
    my $self = shift;
    return \$self->{CURSOR};
}

sub TIEHASH {
    my $class = shift;
    my ($file, $flags, $mode, $index, $keep) = @_;
    $flags //= O_CREAT|O_RDWR;
    my $self = {};
    bless($self, $class);
    # allow $mode to be skipped
    if (ref($mode) =~ /INFO$/) { # it's the index type
	$index = $mode;
	$mode = 0644;
    }
    #defaults
    $mode ||= 0644;
    $index ||= $DB_HASH;
    unless (defined $index and ref($index) =~ /INFO$/) {
	croak(__PACKAGE__.": Index type selector must be a HASHINFO, BTREEINFO, or RECNOINFO object");
    }

    $self->{ref} = 'HASH';
    $self->{index} = $index;
    $self->{pending} = 0;
    my ($infix,$fh);
    # db file handling
    if ($file) {
	# you'll love this...
	my $setmode;
	for ($flags) {
	    $_ eq 'O_SVWST' && do { #bullsith kludge
		$_ = 514;
	    };
	    ($_ & O_CREAT) && do {
		$setmode = 1 if ! -e $file;
		$infix = (-e $file ? '<' : '>');
	    };
	    ($_ & O_RDWR) && do {
		$infix = '+'.($infix ? $infix : '<');
	      };
	    ($_ & O_TRUNC) && do {
	      $infix = '>';
	    };
	    do { # O_RDONLY
		$infix = '<' unless $infix;
	    };
	}
	open($fh, $infix, $file) or croak(__PACKAGE__.": Can't open db file: $!");
	chmod $mode, $file if $setmode;
	# if file explicitly specified, but keep is not, 
	# retain file at destroy...
	$keep = 1 if !defined $keep;
    }
    else {
	# if no file specified, use a temp file...
	($fh, $file) = tempfile(EXLOCK => 0);
	# if keep not explicitly specified, 
	# remove the tempfile at destroy...
	$keep = 0 if !defined $keep;
    }
    $self->file($file);
    $self->_fh($fh);
    $self->keep($keep);

    # create SQL statements
     my $hash_tbl = sub {
	 my $col = shift;
	 $col ||= 'nocase';
	 return <<END;
    (	 
      id      blob collate $col,
      obj     blob not null,
      pk      integer primary key autoincrement
    );
END
     };
    my $create_idx = <<END;
    CREATE INDEX IF NOT EXISTS id_idx ON hash ( id, pk );
END
    my $dbh = DBI->connect("DBI:SQLite:dbname=".$self->file,"","",
			   {RaiseError => 1, AutoCommit => 0});
    $self->dbh( $dbh );
    # pragmata inspired by Bio::DB::SeqFeature::Store::DBI::SQLite
#    $dbh->do("PRAGMA synchronous = OFF");
    $dbh->do("PRAGMA temp_store = MEMORY");
    $dbh->do("PRAGMA cache_size = ".($index->{cachesize} || 20000));

    for ($index->{'type'}) {
	my $flags = $index->{flags} || 0;
	!defined && do {
	    $self->dbh->do("CREATE TABLE IF NOT EXISTS hash $hash_tbl");
	    last;
	};
	$_ eq 'BINARY' && do {
	    my $col = 'nocase';
	    if (ref($index->{'compare'}) eq 'CODE') {
		$self->dbh->func( 'usr', $index->{'compare'}, "create_collation");
		$col = 'usr';
	    }
	    if ($flags & R_DUP ) {
		$self->dup(1);
		$self->dbh->do("CREATE TABLE IF NOT EXISTS hash ".$hash_tbl->($col));
		$self->dbh->do($create_idx);
	    }
	    else {
		$self->dup(0);
		$self->dbh->do("CREATE TABLE IF NOT EXISTS hash ".$hash_tbl->($col));
		$self->dbh->do($create_idx);
	    }
	    last;
	};
	$_ eq 'HASH' && do {
	    $self->dbh->do("CREATE TABLE IF NOT EXISTS hash ".$hash_tbl->());
	    last;
	};
	$_ eq 'RECNO' && do {
	    croak(__PACKAGE__.": \$DB_RECNO is not meaningful for tied hashes");
	    last;
	};
	do {
	    croak(__PACKAGE__.": Index type not defined or not recognized");
	};
    }
    $self->_index if ($infix and $infix =~ /</ and $index->{type} eq 'BINARY');
    $self->commit(1);
    # barryc fix : fast forward the autokey
    my ($sth)=$self->dbh->prepare("select max(pk) from hash");
    $sth->execute();
    ($AUTOPK)=$sth->fetchrow_array();
    return $self;
}

sub TIEARRAY {
    my $class = shift;
    my ($file, $flags, $mode, $index, $keep) = @_;
    $flags //= O_CREAT|O_RDWR;
    my $self = {};
    bless($self, $class);

    $self->{ref} = 'ARRAY';
    # allow $mode to be skipped
    if (ref($mode) =~ /INFO$/) { # it's the index type
	$index = $mode;
	$mode = 0644;
    }
    $mode ||= 0644;
    $index ||= $DB_RECNO;
    unless (defined $index and ref($index) =~ /INFO$/) {
	croak(__PACKAGE__.": Index type selector must be a HASHINFO, BTREEINFO, or RECNOINFO object");
    }
    croak(__PACKAGE__.": Arrays must be tied to type RECNO") unless 
	$index->{type} eq 'RECNO';
    $self->{index} = $index;
    $self->{pending} = 0;
    my ($infix,$fh);
    # db file handling
    if ($file) {
	my $setmode;
	for ($flags) {
	    $_ eq 'O_SVWST' && do { #bullsith kludge
		$_ = 514;
	    };
	    ($_ & O_CREAT) && do {
		$setmode = 1 if ! -e $file;
		$infix = (-e $file ? '<' : '>');
	    };
	    ($_ & O_RDWR) && do {
		$infix = '+'.($infix ? $infix : '<');
	    };
	    ($_ & O_TRUNC) && do {
	      $infix = '>';
	    };
	    do { # O_RDONLY
		$infix = '<' unless $infix;
	    };
	}
	open($fh, $infix, $file) or croak(__PACKAGE__.": Can't open db file: $!");
	chmod $mode, $file if $setmode;
	# if file explicitly specified, but keep is not, 
	# retain file at destroy...
	$keep = 1 if !defined $keep;
    }
    else {
	# if no file specified, use a temp file...
	($fh, $file) = tempfile(EXLOCK => 0);
	# if keep not explicitly specified, 
	# remove the tempfile at destroy...
	$keep = 0 if !defined $keep;
    }
    $self->file($file);
    $self->_fh($fh);
    $self->keep($keep);
    
    my $arr_tbl = <<END;
    (
      id      integer primary key,
      obj     blob not null
    );
END
    
    my $create_idx = <<END;
    CREATE INDEX IF NOT EXISTS id_idx ON hash ( id );
END
    
    my $dbh = DBI->connect("dbi:SQLite:dbname=".$self->file,"","",
			   {RaiseError => 1, AutoCommit => 0});
    $self->dbh( $dbh );

    for ($index->{'type'}) {
	my $flags = $index->{flags} || 0;
	$_ eq 'BINARY' && do {
	    $self->dbh->disconnect;
	    croak(__PACKAGE__.": \$DB_BTREE is not meaningful for a tied array");
	    last;
	};
	$_ eq 'HASH' && do {
	    $self->dbh->disconnect;
	    croak(__PACKAGE__.": \$DB_HASH is not meaningful for a tied array");
	    last;
	};
	$_ eq 'RECNO' && do {
	    $self->dbh->do("CREATE TABLE IF NOT EXISTS hash $arr_tbl");
	    $self->dbh->do($create_idx);
	    my $r = $self->dbh->selectall_arrayref("select * from hash");
	    for (@$r) {
	      push @{$self->SEQIDX},$$_[0];
	    }
	    last;
	};
	do {
	    croak(__PACKAGE__.": Index type not defined or not recognized");
	};
    }
    $self->commit(1);
    return $self;
}

# common methods for hashes and arrays

sub FETCH {
    my $self = shift;
    my $key = shift;
    my $fkey;
    return unless $self->dbh;
    $self->commit;
    if (!$self->{ref} or $self->ref eq 'HASH') {
      local $_ = $key;
      $self->_store_key_filter;
      $self->get_sth->execute($_); # fetches on column 'id'
    }
    elsif ($self->ref eq 'ARRAY') {
	if (defined ${$self->SEQIDX}[$key]) {
	    $self->get_sth->execute($self->get_idx($key));
	}
	else {
	    $self->_last_pk(undef);
	    return undef;
	}
    }
    else { # type not recognized
        croak(__PACKAGE__.": tied type not recognized");
    }
    my $ret = $self->get_sth->fetch;
    if ($ret) {
	$self->_last_pk( $ret->[1] ); # store the returned pk
	$ret->[0] =~ s{<SQUOT>}{'}g;
	$ret->[0] =~ s{<DQUOT>}{"}g;
	local $_ = $ret->[0];
	$self->_fetch_value_filter;
	return $_; # always returns the object
    }
    else {
	$self->_last_pk( undef ); # fail in pk
	return $ret;
    }
}

sub STORE {
    my $self = shift;
    my ($key, $value) = @_;
    my ($fkey, $fvalue);
    return unless $self->dbh;
    {
      # filter value
      local $_ = $value;
      $self->_store_value_filter;
      $fvalue = $_;
    }
    {
      # filter key 
      $_ = $key;
      $self->_store_key_filter;
      $fkey = $_;
    }
    $fvalue =~ s{'}{<SQUOT>}g;
    $fvalue =~ s{"}{<DQUOT>}g;
    my ($pk, $sth);
    if ( !defined $self->{ref} or $self->ref eq 'HASH' ) {
      if ( $self->dup ) { # allowing duplicates
	$pk = $self->_get_pk;
	$sth = $self->put_sth;
	$sth->bind_param(1,$fkey);
	$sth->bind_param(2,$fvalue, SQL_BLOB);
	$sth->bind_param(3,$pk);
	$self->put_sth->execute();
	push @{$self->SEQIDX}, $pk;
      }
      else { # no duplicates...
	#need to check if key is already present
	if ( $self->EXISTS($key) )
	  {
	    $sth = $self->upd_sth;
	    $sth->bind_param(1,$fvalue, SQL_BLOB);
	    $sth->bind_param(2,$key);
	    $sth->bind_param(3,$self->_last_pk);
	    $sth->execute();
	  }
	else {
	  $pk = $self->_get_pk;
	  $sth = $self->put_sth;
	  $sth->bind_param(1,$fkey);
	  $sth->bind_param(2,$fvalue, SQL_BLOB);
	  $sth->bind_param(3,$pk);
	  $sth->execute();
	  push @{$self->SEQIDX}, $pk;
	}
      }
      $self->{_stale} = 1;
    }
    elsif ( $self->ref eq 'ARRAY' ) {
      # need to check if the key is already present
      if (!defined ${$self->SEQIDX}[$key] ) {
	$self->put_sth->execute($self->get_idx($key), $fvalue);
      }
      else {
	$self->upd_sth->execute($fvalue,$self->get_idx($key));
      }
    }
    ++$self->{pending};
    $value;
}

sub DELETE {
    my $self = shift;
    my $key = shift;
    return unless $self->dbh;
    my $fkey;
    { # filter key
	local $_ = $key;
	$self->_store_key_filter;
	$fkey = $_;
    }
    $self->_reindex if ($self->index->{type} eq 'BINARY' and $self->_index_is_stale);
    my $oldval;
    if (!$self->ref or $self->ref eq 'HASH') {
	return unless $self->get_sth->execute($fkey);
	my $ret = $self->get_sth->fetch;
	$oldval = $ret->[0];
	$self->del_sth->execute($fkey); # del on id
	# update the sequential side
	if ($ret->[1]) {
	    delete ${$self->SEQIDX}[_find_idx($ret->[1],$self->SEQIDX)];
	}
    }
    elsif ($self->ref eq 'ARRAY') {
	my $SEQIDX = $self->SEQIDX;
	if ($$SEQIDX[$key]) {
	    $oldval = $self->FETCH($$SEQIDX[$key]);
#	    $self->dbh->do("DELETE FROM hash WHERE id = '$$SEQIDX[$key]'");
	    $self->del_sth->execute($$SEQIDX[$key]); # del on id
	    $self->rm_idx($key);
	}
    }
    else {
	croak( __PACKAGE__.": tied type not recognized" );
    }
    ++$self->{pending};
    $_ = $oldval;
    $self->_fetch_value_filter;
    return $_;
}

sub EXISTS {
    my $self = shift;
    my $key = shift;
    return unless $self->dbh;

    $self->commit;
    if (!$self->ref or $self->ref eq 'HASH') {
      local $_ = $key;
      $self->_store_key_filter;
      $self->get_sth->execute($_);
      my $ret = $self->get_sth->fetch;
      return $self->_last_pk(defined($ret) ? $ret->[1] : undef);
    }
    elsif ($self->ref eq 'ARRAY') {
      return $self->_last_pk(${$self->SEQIDX}[$key]);
    }
    else {
	croak(__PACKAGE__.": tied type not recognized");
    }
}

sub CLEAR {
    my $self = shift;
    return unless $self->dbh;
    $self->dbh->commit;
    my $sth = $self->dbh->prepare("DELETE FROM hash");
    $sth->execute;
    $self->dbh->commit;
    @{$self->SEQIDX} = ();
    return 1;
}

# hash methods

sub FIRSTKEY {
    my $self = shift;
    return unless $self->dbh;
    $self->commit;
    return if ($self->{ref} and $self->ref ne 'HASH');
    my $ids = $self->dbh->selectall_arrayref("SELECT id FROM hash");
    return unless $ids;
    $ids = [ map { $_->[0] } @$ids ];
    { # filter keys
	$self->_fetch_key_filter for (@$ids);
    }
    return $self->_keys($ids);
}

sub NEXTKEY {
    my $self = shift;
    my $lastkey = shift;
    return unless $self->dbh;
    return if ($self->{ref} and $self->ref ne 'HASH');
    return $self->_keys;
}

# array methods

sub FETCHSIZE {
    my $self = shift;
    return unless $self->dbh;
    return if (!$self->{ref} or $self->ref ne 'ARRAY');
    $self->len;
}

sub STORESIZE {
    my $self = shift;
    my $count = shift;
    return unless $self->dbh;
    return if (!$self->ref or $self->ref ne 'ARRAY');
    if ($count > $self->len) {
	foreach ($count - $self->len .. $count) {
	    $self->STORE($_, '');
	}
    }
    elsif ($count < $self->len) {
	foreach (0 .. $self->len - $count - 2) {
	    $self->POP();
	}
    }
}

# EXTEND is no-op
sub EXTEND {
    my $self = shift;
    my $count = shift;
    return;
}

sub POP {
    my $self = shift;
    return unless $self->dbh;
    $self->commit;
    return if (!$self->{ref} or $self->ref ne 'ARRAY');
    $self->get_sth->execute($self->get_idx($self->len-1));
    my $ret = $self->get_sth->fetch;
#    $self->dbh->do("DELETE FROM hash WHERE id = ".$self->get_idx($self->len-1));
    $self->del_sth->execute($self->get_idx($self->len-1));
    # bookkeeping
    $self->rm_idx($self->len-1);
    return defined $ret ? $ret->[0] : $ret;
}

sub PUSH {
    my $self = shift;
    my @values = @_;
    return unless $self->dbh;
    return if (!$self->{ref} or $self->ref ne 'ARRAY');
    my $ret = @values;
    my $beg = $self->len;
    my $end = $self->len + @values - 1;
    for my $i ($beg..$end) {
	$self->put_sth->execute($self->get_idx($i), shift @values);
    }
    ++$self->{pending};
    return $ret;
}

sub SHIFT {
    my $self = shift;
    return unless $self->dbh;
    $self->commit;
    return if (!$self->{ref} or $self->ref ne 'ARRAY');
    $self->get_sth->execute( $self->get_idx(0) );
    my $ret = $self->get_sth->fetch;
    $self->del_sth->execute($self->get_idx(0));
    # bookkeeping
    $self->shift_idx;
    $_ = $ret && $ret->[0];
    $self->_fetch_value_filter;
    return $_;
}

sub UNSHIFT {
    my $self = shift;
    my @values = @_;
    return if (!$self->{ref} or $self->ref ne 'ARRAY');
    my $n = @values;
    $self->_store_value_filter for @values;
    return unless $self->dbh;
    for ($self->unshift_idx($n)) {
	$self->put_sth->execute($_,shift @values);
    }
    ++$self->{pending};
    return $n;
}

sub SPLICE {
    my $self   = shift;
    my $offset = shift || 0;
    my $length = shift || $self->FETCHSIZE() - $offset;
    my @list   = @_;
    my $SEQIDX = $self->SEQIDX;
    $self->_wring_SEQIDX;
    my @pk = map { $self->get_idx($_)} ($offset..$offset+$length-1);
    my @ret;
    for (@pk) {
	$self->get_sth->execute($_);
	push @ret, ${$self->get_sth->fetch}[0];
	$self->del_sth->execute($_);
    }
    my @new_idx = map { $AUTOKEY++ } @list;
    splice( @$SEQIDX, $offset, $length, @new_idx );
    $self->put_sth->execute($_, shift @list) for @new_idx;
    $self->_fetch_value_filter for @ret;
    return @ret;
}    

# destructors

sub UNTIE {
    my $self = shift;
    my $count = shift;

    croak( __PACKAGE__.": untie attempted while $count inner references still exist" ) if ($count);}

sub DESTROY {
    my $self = shift;
    $self->dbh->commit; #'hard' commit
    my $tbl = $STMT{$self->ref};
    # finish and destroy stmt handles
    for ( keys %$tbl ) {
	$self->{$_."_sth"}->finish if $self->{$_."_sth"};
	undef $self->{$_."_sth"};
    }
    # disconnect
    croak($self->dbh->errstr) unless $self->dbh->disconnect;
    $self->{dbh}->DESTROY;
    undef $self->{dbh};
    # remove file if nec
    $self->_fh->close() if $self->_fh;
    if (-e $self->file) {
	local $!;
	unlink $self->file if (!$self->keep && $self->_fh);
	$! && carp(__PACKAGE__.": unlink issue: $!");
    }
    undef $self;
    1;
}

# dbm filter storage hooks

sub filter_store_key { 
    my $self = shift;
    my $code = shift;
    
    unless (!defined($code) or ref($code) eq 'CODE') {
	croak(__PACKAGE__."::filter_store_key requires a coderef argument");
    }
    $self->_store_key_filter($code);
    
};

sub filter_store_value { 
    my $self = shift;
    my $code = shift;
    unless (!defined($code) or ref($code) eq 'CODE') {
	croak(__PACKAGE__."::filter_store_value requires a coderef argument");
    }
    $self->_store_value_filter($code);
    
};

sub filter_fetch_key { 
    my $self = shift;
    my $code = shift;
    unless (!defined($code) or ref($code) eq 'CODE') {
	croak(__PACKAGE__."::filter_fetch_key requires a coderef argument");
    }
    $self->_fetch_key_filter($code);    
};

sub filter_fetch_value { 
    my $self = shift;
    my $code = shift;
    unless (!defined($code) or ref($code) eq 'CODE') {
	croak(__PACKAGE__."::filter_fetch_value requires a coderef argument");
    }
    $self->_fetch_value_filter($code);
};

# filters

sub _fetch_key_filter {
    my $self = shift;
    if (@_) {
	$self->{_fetch_key_filter} = shift;
	return 1;
    }
    return unless defined $self->{_fetch_key_filter};
    &{$self->{_fetch_key_filter}};
};

sub _fetch_value_filter {
    my $self = shift;
    if (@_) {
	$self->{_fetch_value_filter} = shift;
	return 1;
    }
    return unless defined $self->{_fetch_value_filter};
    &{$self->{_fetch_value_filter}};
};

sub _store_key_filter {
    my $self = shift;
    if (@_) {
	$self->{_store_key_filter} = shift;
	return 1;
    }
    return unless defined $self->{_store_key_filter};
    &{$self->{_store_key_filter}};
};

sub _store_value_filter {
    my $self = shift;
    if (@_) {
	$self->{_store_value_filter} = shift;
	return 1;
    }
    return unless defined $self->{_store_value_filter};
    &{$self->{_store_value_filter}};
};

=head1 Attribute Accessors

=head2 file()

 Title   : file
 Usage   : $db->file()
 Function: filename for the SQLite db
 Example : 
 Returns : value of file (a scalar)
 Args    : 

=cut

sub file {
    my $self = shift;
    
    return $self->{'file'} = shift if @_;
    return $self->{'file'};
}

=head2 _fh()

 Title   : _fh
 Usage   : $db->_fh()
 Function: holds the temp file handle
 Example : 
 Returns : value of _fh (a scalar)
 Args    : 

=cut

sub _fh {
    my $self = shift;
    
    return $self->{'_fh'} = shift if @_;
    return $self->{'_fh'};
}

=head2 keep()

 Title   : keep
 Usage   : $db->keep()
 Function: flag allows preservation of db file when set
 Returns : value of keep (a scalar)
 Args    : 

=cut

sub keep {
    my $self = shift;
    
    return $self->{'keep'} = shift if @_;
    return $self->{'keep'};
}

=head2 ref()

 Title   : ref
 Usage   : $db->ref
 Function: HASH or ARRAY? Find out.
 Returns : scalar string : 'HASH' or 'ARRAY'
 Args    : none

=cut


sub ref {
    my $self = shift;
    return $self->{ref};
}

=head2 index()

 Title   : index
 Usage   : $db->index()
 Function: access the index type structure ($DB_BTREE, $DB_HASH, 
           $DB_RECNO) that initialized this instance
 Returns : value of index (a hashref)
 Args    : 

=cut

sub index {
    my $self = shift;
    return $self->{'index'};
}

# =head2 _keys

#  Title   : _keys
#  Usage   : internal
#  Function: points to a hash to make iterating easy and fun
#  Example : 
#  Returns : value of _keys (a hashref)
#  Args    : on set, an arrayref of scalar keys

# =cut

sub _keys {
    my $self = shift;
    my $load = shift;
    if ($load) {
	$self->{'_keys'} = {};
	@{$self->{'_keys'}}{ @$load } = (undef) x @$load;
	my $a = keys %{$self->{'_keys'}}; #reset each
    }
    return each %{$self->{'_keys'}};
}

=head1 BDB API Emulation : random access

=head2 get()

 Title   : get
 Usage   : $db->get($key, $value)
 Function: Get value associated with key
 Returns : 0 on success, 1 on fail; 
           value in $value
 Args    : as in DB_File

=cut

sub get {
    my $self = shift;
    my ($key, $value) = @_;
    return unless $self->dbh;
    $_[1] = ($self->ref eq 'ARRAY' ? $self->FETCH(${$self->SEQIDX}[$key]) : $self->FETCH($key));
    return 0 if defined $_[1];
    return 1;
}

=head2 put()

 Title   : put
 Usage   : $db->put($key, $value, $flags)
 Function: Replace a key's value, or
           put a key-value pair
 Returns : 0 on success, 1 on fail;
           value in $value
           key in $key if $flags == R_CURSOR
 Args    : as in DB_File

=cut

sub put {
    my $self = shift;
    my ($key, $value, $flags) = @_;
    return unless $self->dbh;

    my $SEQIDX = $self->SEQIDX;
    my $CURSOR = $self->CURSOR;
    my ($status, $pk, @parms);
    my ($sth, $do_cursor);
    for ($flags) {
	(!defined || $_ == R_SETCURSOR) && do { # put or upd
	    if ($self->dup) { # just make a new one
		$pk = $self->_get_pk;
		$sth = $self->put_seq_sth;
		$do_cursor = sub {
		    push @$SEQIDX, $pk;
		    $$CURSOR = $#$SEQIDX if $flags;
		    $self->_reindex if $self->index->{type} eq 'BINARY';
		};
	    }
	    else {
		$self->FETCH($key);
		$pk = $self->_last_pk || $self->_get_pk;
		$sth = ($self->_last_pk ? 
			   $self->upd_seq_sth :
			   $self->put_seq_sth);
		$do_cursor = sub {
		    push @$SEQIDX, $pk if !$self->_last_pk;
		    $flags && do { # R_SETCURSOR
			if ( $pk = $$SEQIDX[-1] ) {
			    $$CURSOR = $#$SEQIDX;
			}
			else {
			    $$CURSOR = _find_idx($pk, $SEQIDX);
			};
			$self->_reindex if $self->index->{type} eq 'BINARY';
		    };
		};
	    }
	    last;
	};
	$_ == R_IAFTER && do {
	    $self->_wring_SEQIDX unless $$SEQIDX[$$CURSOR];
	    # duplicate protect
	    return 1 unless ($self->ref eq 'ARRAY') || $self->dup || !$self->EXISTS($key);
	    croak(__PACKAGE__.": R_IAFTER flag meaningful only for RECNO type") unless
		$self->index->{type} eq 'RECNO';
	    $pk = $self->_get_pk;
	    $sth = $self->put_seq_sth;
	    $_[0] = $$CURSOR+1;
	    $do_cursor = sub {
		if ($$CURSOR == $#$SEQIDX) {
		    push @$SEQIDX, $pk;
		}
		else {
		    splice(@$SEQIDX,$$CURSOR,0,$pk);
		}
	    };
	    last;
	};
	$_ == R_IBEFORE && do {
	    $self->_wring_SEQIDX unless $$SEQIDX[$$CURSOR];
	    # duplicate protect
	    return 1 unless ($self->ref eq 'ARRAY') || $self->dup || !$self->EXISTS($key);
	    croak(__PACKAGE__.": R_IBEFORE flag meaningful only for RECNO type") unless
		$self->index->{type} eq 'RECNO';
	    $pk = $self->_get_pk;
	    $sth = $self->put_seq_sth;
	    $_[0] = $$CURSOR;
	    $do_cursor = sub {
		if ($$CURSOR) {
		    splice(@$SEQIDX,$$CURSOR-1,0,$pk);
		}
		else {
		    unshift(@$SEQIDX, $pk);
		}
		$$CURSOR++; # preserve cursor
	    };
	    last;
	};
	$_ == R_CURSOR && do { # upd only
	    $self->_wring_SEQIDX unless $$SEQIDX[$$CURSOR];
	    # duplicate protect
	    return 1 unless ($self->ref eq 'ARRAY') || $self->dup || !$self->EXISTS($key);
	    $pk = $$SEQIDX[$$CURSOR];
	    $sth = $self->upd_seq_sth;
	    $do_cursor = sub {
		$self->_reindex if $self->index->{type} eq 'BINARY';
	    };
	    last;
	};
	$_ == R_NOOVERWRITE && do { # put only/add to the "end"
	    #will create a duplicate if $self->dup is set!
	    return 1 unless ($self->ref eq 'ARRAY') || $self->dup || !$self->EXISTS($key);
	    $pk = $self->_get_pk;
	    $sth = $self->put_seq_sth;
	    $do_cursor = sub {
		push @$SEQIDX, $pk;
		$self->_reindex if $self->index->{type} eq 'BINARY';
	    };
	    last;
	};
    }
    if ($self->ref eq 'ARRAY') {
	$sth->bind_param(1, $value, SQL_BLOB);
	$sth->bind_param(2, $pk);
    }
    else {
	$sth->bind_param(1, $key);
	$sth->bind_param(2, $value, SQL_BLOB);
	$sth->bind_param(3, $pk);
    }
    $status = !$sth->execute;
    $do_cursor->() if !$status;
    $self->{pending} = 1;
    $self->{_stale} = 0 if $self->index->{type} eq 'BINARY';
    return $status;
}

=head2 del()

 Title   : del
 Usage   : $db->del($key)
 Function: delete key-value pairs corresponding to $key
 Returns : 0 on success, 1 on fail
 Args    : as in DB_File

=cut

sub del {
    my $self = shift;
    my ($key, $flags) = @_;
    return unless $self->dbh;
    $self->_reindex if ($self->index->{type} eq 'BINARY' and $self->_index_is_stale);
    my $SEQIDX = $self->SEQIDX;
    my $CURSOR = $self->CURSOR;
    my $status;
    if ($flags eq R_CURSOR) {
	_wring_SEQIDX($self->SEQIDX) unless $$SEQIDX[$$CURSOR];
	my $pk = $$SEQIDX[$$CURSOR];
	$status = $self->del_seq_sth->execute($pk);
	if ($status) { # successful delete
	    $$SEQIDX[$$CURSOR] = undef;
	    $self->_wring_SEQIDX;
	}
	1;
    }
    else {
	# delete all matches
	$status = $self->DELETE($key);
	1;
    }
    $self->{_stale} = 1;
    $self->{pending} = 1;
    return 0 if $status;
    return 1;
}

=head1 BDB API Emulation : sequential access

=head2 seq()

 Title   : seq
 Usage   : $db->seq($key, $value, $flags)
 Function: retrieve key-value pairs sequentially,
           according to $flags, with partial matching
           on $key; see DB_File
 Returns : 0 on success, 1 on fail;
           key in $key,
           value in $value
 Args    : as in DB_File

=cut

sub seq {
    my $self = shift;
    my ($key, $value, $flags) = @_;
    return 1 unless $flags;
    $self->commit;
    my $status;
    $self->_reindex if ($self->index->{type} eq 'BINARY' and $self->_index_is_stale);
    my $SEQIDX = $self->SEQIDX;
    my $CURSOR = $self->CURSOR;
    for ($flags) {
	$_ eq R_CURSOR && do {
	    last;
	};
	$_ eq R_FIRST && do {
	    $$CURSOR  = 0;
	    last;
	};
	$_ eq R_LAST && do {
	    $$CURSOR = $#$SEQIDX;
	    last;
	};
	$_ eq R_NEXT && do {
	    return 1 if ($$CURSOR >= $#$SEQIDX);
	    ($$CURSOR)++;
	    last;
	};
	$_ eq R_PREV && do {
	    return 1 if $$CURSOR == 0;
	    ($$CURSOR)--;
	    last;
	};
    }
    $self->_wring_SEQIDX() unless defined $$SEQIDX[$$CURSOR];
    # get by pk, set key and value.
    if (($flags == R_CURSOR ) && $self->ref eq 'HASH') {
	$status = $self->partial_match($key, $value);
	$_[0] = $key; $_[1] = $value;
	return $status;
    }
    else {
	$self->get_seq_sth->execute($$SEQIDX[$$CURSOR]);
	my $ret = $self->get_seq_sth->fetch;
	($_[0], $_[1]) = (($self->ref eq 'ARRAY' ? $$CURSOR : $$ret[0]), $$ret[1]);
    }
    return 0;
}

=head2 sync()

 Title   : sync
 Usage   : $db->sync
 Function: stub for BDB sync 
 Returns : 0
 Args    : none

=cut

sub sync { !shift->commit };

=head1 BDB API Emulation : C<dup>

=head2 dup

 Title   : dup
 Usage   : $db->dup()
 Function: Get/set flag indicating whether duplicate keys
           are preserved
 Returns : boolean
 Args    : [optional] on set, new value (a scalar or undef, optional)

=cut

sub dup {
    my $self = shift;
    return $self->{'dup'} = shift if @_;
    return $self->{'dup'};
}

=head2 get_dup()

 Title   : get_dup
 Usage   : $db->get_dup($key, $want_hash)
 Function: retrieve all records associated with a key
 Returns : scalar context: scalar number of records
           array context, !$want_hash: array of values
           array context, $want_hash: hash of value-count pairs
 Args    : as in DB_File

=cut

sub get_dup {
    my $self = shift;
    my ($key, $want_hash) = @_;
    return unless $self->dbh;
    $self->commit;
    unless ($self->dup) {
	carp("DB not created in dup context; ignoring");
	return;
    }
    $self->get_sth->execute($key);
    my $ret = $self->get_sth->fetchall_arrayref;
    return scalar @$ret unless wantarray;
    my @ret = map {$_->[0]} @$ret;
    if (!$want_hash) {
	return @ret;
    }
    else {
	my %h;
	$h{$_}++ for @ret;
	return %h;
    }
}

=head2 find_dup()

 Title   : find_dup
 Usage   : $db->find_dup($key, $value)
 Function: set the cursor to an instance of 
           the $key-$value pair, if one 
           exists
 Returns : 0 on success, 1 on fail
 Args    : as in DB_File

=cut

sub find_dup {
    my $self = shift;
    my ($key, $value) = @_;
    return unless $self->dbh;
    $self->commit;
    unless ($self->dup) {
	carp("DB not created in dup context; ignoring");
	return;
    }
    $self->sel_dup_sth->bind_param(1,$key);
    $self->sel_dup_sth->bind_param(2,$value,SQL_BLOB);
    $self->sel_dup_sth->execute;
    my $ret = $self->sel_dup_sth->fetch;
    return 1 unless $ret;
    ${$self->CURSOR} = _find_idx($ret->[0], $self->SEQIDX);
    return 0
}

=head2 del_dup()

 Title   : del_dup
 Usage   : $db->del_dup($key, $value)
 Function: delete all instances of the $key-$value pair
 Returns : 0 on success, 1 on fail
 Args    : as in DB_File

=cut

sub del_dup {
    my $self = shift;
    my ($key, $value) = @_;
    my $ret;
    return unless $self->dbh;
    unless ($self->dup) {
	carp("DB not created in dup context; ignoring");
	return;
    }
    $self->sel_dup_sth->bind_param(1, $key);
    $self->sel_dup_sth->bind_param(2, $value, SQL_BLOB);
    $self->sel_dup_sth->execute;
    $ret = $self->sel_dup_sth->fetchall_arrayref;
    unless ($ret) {
	return 1;
    }
    $self->del_dup_sth->bind_param(1, $key);
    $self->del_dup_sth->bind_param(2, $value, SQL_BLOB);
    if ($self->del_dup_sth->execute) {
	# update SEQIDX
	foreach (map { $$_[0] } @$ret) {
	    delete ${$self->SEQIDX}[_find_idx($_,$self->SEQIDX)];
	}
	$self->_wring_SEQIDX;
	$self->{pending} = 1;
	return 0; # success
    }
    else {
	return 1; # fail
    }
}

# =head2 BDB API Emulation : internals

# =head2 partial_match()

#  Title   : partial_match
#  Usage   : 
#  Function: emulate the partial matching of DB_File::seq() with
#            R_CURSOR flag
#  Returns : 
#  Args    : $key

# =cut

sub partial_match {
    my $self = shift;
    my ($key, $value) = @_;

    my ($status,$ret, $pk);
    unless ($self->ref ne 'ARRAY') {
	croak(__PACKAGE__.": Partial matches not meaningful for arrays");
    }
    my $SEQIDX = $self->SEQIDX;
    my $CURSOR = $self->CURSOR;
    $status = !$self->part_seq_sth->execute( $key );
    if (!$status) { # success
	if ($ret = $self->{part_seq_sth}->fetch) {
	    $_[0] = $ret->[0]; $_[1] = $ret->[1];
	    $pk = $ret->[2];
 	    unless (defined($$CURSOR = _find_idx($pk,$SEQIDX))) {
		croak(__PACKAGE__.": Primary key value disappeared! Please submit bug report!");
	    }
	    return 0;
	}
    }
    return 1;
}

=head1 SQL Interface

=head2 dbh()

 Title   : dbh
 Usage   : $db->dbh()
 Function: Get/set DBI database handle
 Example : 
 Returns : DBI database handle
 Args    : 

=cut

sub dbh {
    my $self = shift;
    return $self->{'dbh'} = shift if @_;
    return $self->{'dbh'};
}

=head2 sth()

 Title   : sth
 Usage   : $obj->sth($stmt_descriptor)
 Function: DBI statement handle generator
 Returns : a prepared DBI statement handle
 Args    : scalar string (statement descriptor)
 Note    : Calls such as $db->put_sth are autoloaded through
           this method; please see source for valid descriptors

=cut

sub sth {
    my $self = shift;
    my $desc = shift;
    croak(__PACKAGE__.": No active database handle") unless $self->dbh;
    my $tbl = $STMT{$self->ref};
    unless ($tbl) {
	croak(__PACKAGE__.": Tied type '".$self->ref."' not recognized");
    }
    if (!$self->{"${desc}_sth"}) {
	croak(__PACKAGE__.": Statement descriptor '$desc' not recognized for type ".$self->ref) unless grep(/^$desc$/,keys %$tbl);
	$self->{"${desc}_sth"} = $self->dbh->prepare($tbl->{$desc});
    }
    return $self->{"${desc}_sth"};
}

# autoload statement handle getters
# autoload filters

sub AUTOLOAD {
    my $self = shift;
    my @pth = split(/::/, $AUTOLOAD); 
    my $desc = $pth[-1];
    unless ($desc =~ /^(.*?)_sth$/) {
	croak(__PACKAGE__.": Subroutine '$AUTOLOAD' is undefined in ".__PACKAGE__);
    }
    $desc = $1;
    if (defined $desc) {
      unless (grep /^$desc$/, keys %{$STMT{$self->ref}}) {
	croak(__PACKAGE__.": Statement accessor ${desc}_sth not defined for type ".$self->ref);
      }
      return $self->sth($desc);
    }
    else {
      croak __PACKAGE__.": Shouldn't be here; call was to '$pth[-1]'";
    }
}

=head2 commit()

 Title   : commit
 Usage   : $db->commit()
 Function: commit transactions
 Returns : 
 Args    : commit(1) forces, commit() commits when
           number of pending transactions > $SQLite::MAXPEND

=cut

sub commit {

    my $self = shift;

    if (@_ or ($self->{pending} > $SQLite_File::MAXPEND)) {
	carp(__PACKAGE__.": commit failed") unless $self->dbh->commit();
	$self->{pending} = 0;
    }
    return 1;
}

=head2 pending()

 Title   : pending
 Usage   : $db->pending
 Function: Get count of pending (uncommitted) transactions
 Returns : scalar int
 Args    : none

=cut

sub pending {
    shift->{pending};
}

=head2 trace()

 Title   : trace
 Usage   : $db->trace($TraceLevel)
 Function: invoke the DBI trace logging service
 Returns : the trace level
 Args    : scalar int trace level

=cut

sub trace {
    my $self = shift;
    my $level = shift;
    return unless $self->dbh;
    $level ||= 3;
    $self->dbh->{TraceLevel} = $level;
    $self->dbh->trace;
    return $level;
}

# =head1 Private index methods : Internal

# =head2 _index_is_stale()

#  Title   : _index_is_stale
#  Usage   : 
#  Function: predicate indicating whether a _reindex has been
#            performed since adding or updating the db
#  Returns : 
#  Args    : none

# =cut

sub _index_is_stale {
    my $self = shift;
    return $self->{_stale};
}

# =head2 _index()

#  Title   : _index
#  Usage   : 
#  Function: initial the internal index array (maps sequential 
#            coordinates to db primary key integers)
#  Returns : 1 on success
#  Args    : none

# =cut

sub _index {
    my $self = shift;

    croak(__PACKAGE__.": _index not meaningful for index type '".$self->index->{type}."'") unless $self->index->{type} eq 'BINARY';
    my ($q, @order);
    $q = $self->dbh->selectall_arrayref("SELECT pk, id FROM hash ORDER BY id");
    unless ($q) {
	return 0;
    }
    @order = map { $$_[0] } @$q;
    $self->{SEQIDX} = \@order;
    ${$self->CURSOR} = 0;
    $self->{_stale} = 0;
    return 1;
}

# =head2 _reindex()

#  Title   : _reindex
#  Usage   : 
#  Function: reorder SEQIDX to reflect BTREE ordering,
#            preserving cursor
#  Returns : true on success
#  Args    : none

# =cut

sub _reindex {
    my $self = shift;

    croak(__PACKAGE__.": _reindex not meaningful for index type '".$self->index->{type}."'") unless $self->index->{type} eq 'BINARY';
    my ($q, @order);
    my $SEQIDX = $self->SEQIDX;
    my $CURSOR = $self->CURSOR;
    $self->_wring_SEQIDX;
    $q = $self->dbh->selectall_arrayref("SELECT pk, id FROM hash ORDER BY id");
    unless ($q) {
	return 0;
    }
    @order = map { $$_[0] } @$q;
    if (defined $$CURSOR) {
	$$CURSOR = _find_idx($$SEQIDX[$$CURSOR],\@order);
    }
    else {
	$$CURSOR = 0;
    }
    $self->{SEQIDX} = \@order;
    $self->{_stale} = 0;
    return 1;
}

# =head2 _find_idx()

#  Title   : _find_idx
#  Usage   : 
#  Function: search of array for index corresponding
#            to a given value
#  Returns : scalar int (target array index)
#  Args    : scalar int (target value), array ref (index array)

# =cut

sub _find_idx {
    my ($pk, $seqidx) = @_;
    my $i;
    for (0..$#$seqidx) {
	$i = $_;
	next unless defined $$seqidx[$_];
	last if $pk == $$seqidx[$_];
    }
    return (defined $$seqidx[$i] and $pk == $$seqidx[$i] ? $i : undef);
}

# =head2 _wring_SEQIDX()

#  Title   : _wring_SEQIDX
#  Usage   : 
#  Function: remove undef'ed values from SEQIDX,
#            preserving cursor
#  Returns : 
#  Args    : none

# =cut

sub _wring_SEQIDX {
    my $self = shift;
    my $SEQIDX = $self->SEQIDX;
    my $CURSOR = $self->CURSOR;
    $$CURSOR = 0 unless defined $$CURSOR;
    my ($i, $j, @a);
    $j = 0;
    for $i (0..$#$SEQIDX) {
	if (defined $$SEQIDX[$i]) {
	    $$CURSOR = $j if $$CURSOR == $i;
	    $a[$j++] = $$SEQIDX[$i];
	}
	else {
	    $$CURSOR = $i+1 if $$CURSOR == $i;
	}
    }
    @$SEQIDX = @a;
    return;
}

# =head2 _get_pk()

#  Title   : _get_pk
#  Usage   : 
#  Function: provide an unused primary key integer for seq access
#  Returns : scalar int
#  Args    : none

# =cut

sub _get_pk {
    my $self = shift;
    # do the primary key auditing for the cursor functions...
    return ++$AUTOPK;
}

# =head2 _last_pk

#  Title   : _last_pk
#  Usage   : $obj->_last_pk($newval)
#  Function: the primary key integer returned on the last FETCH
#  Example : 
#  Returns : value of _last_pk (a scalar)
#  Args    : on set, new value (a scalar or undef, optional)

# =cut

sub _last_pk {
    my $self = shift;
    
    return $self->{'_last_pk'} = shift if @_;
    return $self->{'_last_pk'};
}

# =head2 Array object helper functions : internal

# =cut

sub len {
    scalar @{shift->SEQIDX};
}

sub get_idx {
    my $self = shift;
    my $index = shift;
    my $SEQIDX = $self->SEQIDX;
    return $$SEQIDX[$index] if defined $$SEQIDX[$index];
    push @$SEQIDX, $AUTOKEY;
    $$SEQIDX[$index] = $AUTOKEY++;
}

sub shift_idx {
    my $self = shift;
    return shift( @{$self->SEQIDX} );
}

# returns the set of new db ids to use
sub unshift_idx {
    my $self = shift;
    my $n = shift;
    my @new;
    push(@new, $AUTOKEY++) for (0..$n-1);
    unshift @{$self->SEQIDX}, @new;
    return @new;
}

sub rm_idx {
    my $self = shift;
    my $index = shift;
    unless (delete ${$self->SEQIDX}[$index]) {
	warn("Element $index did not exist");
    }
}

1;


package #hide from PAUSE
  SQLite_File::HASHINFO;
use strict;
use warnings;

# a hashinfo class stub
sub new {
    my $class = shift;
    my $self = bless({}, $class);
    $self->{type} = 'HASH';
    return $self;
}

1;

package #hide from PAUSE
  SQLite_File::BTREEINFO;
use strict;
use warnings;

# a btreeinfo class stub
sub new {
    my $class = shift;
    my $self = bless({}, $class);
    $self->{type} = 'BINARY';
    return $self;
}

1;

package #hide from PAUSE
  SQLite_File::RECNOINFO;
use strict;
use warnings;

# a recnoinfo class stub
sub new {
    my $class = shift;
    my $self = bless({}, $class);
    $self->{type} = 'RECNO';
    return $self;
}

1;
