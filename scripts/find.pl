#!/usr/bin/perl -w
# $Revision: 1.20 $
# Luis Mondesi < lemsx1@gmail.com >
# Last modified: 2005-Feb-19
#
# DESC: finds a string in a set of files
#
# USAGE: 
#   find_infile.pl "string" ".*\.html"
#
# BUGS: if replacement string contains invalid characters
#       nothing gets done. Have to find a way to escape
#       all characters which might be used by Perl's
#       s/// operator
#


use File::Find;     # find();
use File::Basename; # basename();
use Getopt::Long;
Getopt::Long::Configure('bundling');

use strict;
$|++;

my $DEBUG = 0;

my $EXCEPTION_LIST = "\.soc\$|\.sock\$|\.so\$|\.o\$|\.swp\$";

# -------------------------------------------------------------------
#           NO NEED TO MODIFY ANYTHING PASS THIS LINE               #
# -------------------------------------------------------------------

my $usage = "Usage: find.pl [--replace=\"string\"] \"string\" [\"FILE_REGEX\"]\n NOTE use quotes to avoid the shell expanding your REGEX";
my $modified = 0;

my $thisFile = "";      # general current file
my @new_file = ();      # lines to be printed in new file
my @ls = ();            # array of files

my ($this_string,$that_string,$f_pattern) = "";

GetOptions(
    # flags
    #'v|version'         =>  \$PVERSION,
    #'h|help'            =>  \$HELP,
    'D|debug'           =>  \$DEBUG,
    # strings
    'r|replace=s'      =>   \$that_string
) and $this_string = shift and $f_pattern = shift;

if ( defined $f_pattern && $f_pattern =~ m(^\.) )
{
    print "WARNING: using a dot in file pattern can match too many files. Escape dots with '\.'.\n Waiting 5 seconds before continuing\n Press CTRL+C to abort script execution\n" ;
    sleep(5);
}

if (!$f_pattern) {
    print STDERR "All files chosen\n";
    $f_pattern = ".*";
}

if ( $DEBUG > 0 )
{
    print "s: '$this_string' r: '$that_string' f: '$f_pattern'\n";
    print STDERR "DEBUG in place... pausing for 10 seconds\n";
    sleep(10);
}

if ($this_string =~ /\w/) {
    my $i =0;
    @ls = do_file_ary("."); # start at current directory
    
    for (@ls) {
        # yes, this is a wrapper for a standard tip!
        #
        # open e/a file if it's a regular file
        # and replace $this_string with $that_string
        # if $that_string is set
        # and keep a backup .bak for e/a file modified
    
        if ($DEBUG) {print STDERR "opening $_\n"; }
        
        #system("perl -e 'm/$this_string/g;' $_");
        # or 
        #system("perl -e 's/$this_string/$that_string/g;' -pi.bak $_");

        $thisFile = $_;

        $i = 0;
        $modified = 0; # clear flag

        open (FILE,"<$thisFile") or die "could not open $thisFile. $!\n";
        if ( $that_string gt "" )
        {
            while(<FILE>) {
                $i++;
                if ($_ =~ s($this_string)($that_string)g) {
                    print STDOUT "$thisFile [$i]: $_"; 
                    $modified = 1;
                }
                push @new_file,$_;
            }
            close(FILE);

            if ($modified) {
                open (NEWFILE,">$thisFile") 
                    or die "could not write to $thisFile. $!\n";
                print NEWFILE @new_file;
                close(NEWFILE);
            }

            # cleanup array
            @new_file = ();

        } else {
            while(<FILE>) { 
                $i++; 
                if ($_ =~ m($this_string)gi) {
                    print STDOUT "$thisFile [$i]: $_"; 
                }
            }
            close(FILE);

        }

    } #end for
} else {
    print $usage;
}

sub do_file_ary {
    # uses find() to recur thru directories
    # returns an array of files
    # i.e. in directory "a" with the files:
    # /a/file.txt
    # /a/b/file-b.txt
    # /a/b/c/file-c.txt
    # /a/b2/c2/file-c2.txt
    # 
    # my @ary = &do_file_ary(".");
    # 
    # will yield:
    # a/file.txt
    # a/b/file-b.txt
    # a/b/c/file-c.txt
    # a/b2/c2/file-c2.txt
    # 
    my $ROOT = shift;
    
    my %opt = (wanted => \&process_file, no_chdir=>1);
    
    find(\%opt,$ROOT);
    
    return @ls;
}

sub is_binary
{
    # returns 1 if true
    my $file = shift;
    my $file_t = qx/file "$file"/;
    if ( $file_t =~ m/text\s+executable/i )
    {
        return 0;
    }
    if ( $file_t =~ m/elf|executable|data$/i )
    {
        return 1;
    }
    return 0;
}

sub process_file {
    my $base_name = basename($_);
    if ( 
        $_ =~ m($f_pattern) &&
        -f $_ && 
        $base_name !~ m($EXCEPTION_LIST) &&
        ! is_binary ($_)
    ) {
        s/^\.\/*//g;
        push @ls,$_;
    }
}

# without using Find
#sub file_ary {
#    
#    my $dir = $_[0];
#    my @subdir = ();
#
#    if ($DEBUG) { print STDOUT "dir $dir\n"; }
#    
#    opendir (DIR,"$dir") || die "Couldn't open current directory. $!\n";
#
#    #construct array of all files and put in @ls
#    while (defined($thisFile = readdir(DIR))) {
#        next if ($thisFile !~ /\w/);
#        if (-d "$dir/$thisFile") {
#            # we don't care about directories . and ..
#            next if ($thisFile =~ /^\.{1,2}$/);
#            push @subdir,"$dir/$thisFile"; 
#            next;
#        }
#        # is file a plain text (ASCII) file?
#        next unless (-f "$dir/$thisFile" && -T "$dir/$thisFile");
#       
#        # do we want specific file extensions?
#        no warnings;
#        if ( $f_pattern gt "" ) {
#            next if ($thisFile !~ m/$f_pattern/i);
#        }
#        
#        if ($DEBUG) { print STDERR "this file $thisFile\n"; }
#        
#        push @ls, "$dir/$thisFile";
#    }
#    closedir(DIR);
#
#    # recur thru rest of directories
#    # there is no limit in recursion. be careful!
#    foreach(@subdir) {
#        file_ary("$_");
#    }
#}
