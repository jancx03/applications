#!/usr/bin/perl -w
# $Revision: 1.0 $
# $Date: 2007-05-03 20:37:08 $
# my_name < email@example.com >
#
# DESCRIPTION:
# USAGE:
# LICENSE: ___

=pod

=head1 NAME

skeleton.pl - skeleton script for Perl

=head1 DESCRIPTION 

    This script ...

=cut

use strict;

my $revision = '$Revision: 1.0 $';    # version
$revision =~ s/(\\|Revision:|\s|\$)//g;

# standard Perl modules
use IO::Handle;
STDOUT->autoflush(1);                 # same as: $| = 1;
STDERR->autoflush(1);

use Getopt::Long;
Getopt::Long::Configure('bundling');
use POSIX;                    # cwd() ... man POSIX
use File::Spec::Functions;    # abs2rel() and other dir/filename specific
use File::Copy;
use File::Find;               # find();
use File::Basename;           # basename() && dirname()
use FileHandle;               # for progressbar

#eval "use My::Module";
#if ($@)
#{
#    print STDERR "\nERROR: Could not load the Image::Magick module.\n" .
#    "       To install this module use:\n".
#    "       perl -e shell -MCPAN\n".
#    "       On Debian just: apt-get install perlmagic \n\n".
#    "       FALLING BACK to 'convert'\n\n";
#    print STDERR "$@\n";
#    exit 1;
#}

# Args:
my $PVERSION = 0;
my $HELP     = 0;
my $USAGE    = 0;
my $DEBUG    = 0;

=pod

=head1 SYNOPSIS

B<skeleton.pl>  [-v,--version]
                [-D,--debug] 
                [-h,--help]
                [-U,--usage]

=head1 OPTIONS

=over 8

=item -v,--version

Prints version and exits

=item -D,--debug

Enables debug mode

=item -h,--help

Prints this help and exits

=item -U,--usage

Prints usage information and exits

=back

=cut

# get options
GetOptions(

    # flags
    'v|version' => \$PVERSION,
    'h|help'    => \$HELP,
    'D|debug'   => \$DEBUG,
    'U|usage'   => \$USAGE,

    # strings
    #'o|option=s'       =>  \$NEW_OPTION,
    # numbers
    #'a|another-option=i'      =>  \$NEW_ANOTHER_OPTION,
);

if ($HELP)
{
    use Pod::Text;
    my $parser = Pod::Text->new(sentence => 0, width => 78);
    $parser->parse_from_file($0, \*STDOUT);
    exit 0;
}

sub _usage
{
    use Pod::Usage;
    pod2usage(1);
}

if ($USAGE)
{
    _usage();
    exit 0;    # never reaches here
}

if ($PVERSION) { print STDOUT ($revision, "\n"); exit 0; }

use XML::Parser;

my @servers  = ();
my $ref      = undef;
my $id_found = undef;
my $ip_found = undef;

sub start
{
    my ($p, $elt, %attrs) = @_;
    return unless $elt =~ /ip|serverid|appliancenode/i;
    $ip_found = 1 if ($elt =~ /ip/i);
    $id_found = 1 if ($elt =~ /serverid/i);
    $ref = {} if $elt =~ /appliancenode/i;
}

sub end
{
    my ($p, $elt) = @_;

    return unless $elt =~ /ip|serverid|appliancenode/i;
    push @servers,$ref if $elt =~ /appliancenode/i;
    $ip_found = 0 if $elt =~ /ip/i;
    $id_found = 0 if $elt =~ /serverid/i;
}

sub char
{
    my ($p, $elt) = @_;
    $ref->{"IP"} = $elt if $ip_found;
    $ref->{"ID"} = $elt if $id_found;
}

my $parser = new XML::Parser(
                             Handlers => {
                                          Start => \&start,
                                          End   => \&end,
                                          Char  => \&char,
                                         }
                            );
$parser->parsefile("/tmp/nodeconfig.xml");

=pod

=head1 AUTHORS

my_name < email@example.com >

=cut

