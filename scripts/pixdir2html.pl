#!/usr/bin/perl 
# $Revision: 1.14 $
# Luis Mondesi  <lemsx1@hotmail.com> 2002-01-17
# 
# USAGE:
#   pixdir2html.pl [-n|--nomenu] [-f|--force] [-h|--help]
# 
#   force   - creates a .pixdir2htmlrc in every subdir overriding
#             any file with that name
#   nomenu  - do not create menus after finishing creating thumbnails
#   help    - prints this help and exit
#   
# DESCRIPTION:
# 
# Use this non-interactive script in Nautilus to create HTML files
# with their proper thumbnails for pictures (.jpeg or .gif)
# 
# Make this file executable and put it in:
# ~/.gnome/nautilus-scripts
# or 
# ~/.gnome2/nautilus-scripts
# 
# Then run it from from the File::Scripts::script_name menu
# 
# You could customize each directory differently by having a
# file named .pixdir2htmlrc in the directory containing the
# pictues. This file has the form:
# 
# percent=30% #size of the thumbnails for this folder
# title=Title
# html_msg=<h1>Free form using HTML tags</h1> 
# body=<body bgcolor='#000000'>
# p=<p>
# table=<table border='0'>
# td=<td valign='left'>
# tr=<tr>
# footer=<a href='#'>A footer here</a>
# 
# These are the only tags that you can customize for now :-)
# Required: linux/UNIX "convert" command (to convert images from
#	    one format to another or sizes, etc...)
# 
# BUGS:
#   * links are not counted right yet... look for a way to "know"
#     when a directory is actually a link (other than checking for
#     -f .nopixdir2htmlrc || !-f $_/index.(php|html|whatever) ...
#   * when passing directory from command line, if current dir
#     needs files generated, it creates bad links...
#
#   * config file cannot contain lines that spawn to multiple
#     lines. Will fix later.
#   * config file should not contain double quotes (") without
#     escaping them first (\")
#   * if a directory has a .nopixdir2htmlrc file, it will be skipped
#     even if there are subdirectories inside which might need thumbnails
#     created. Either do not put a .nopixdir2htmlrc file in these directories
#     or mv the subdirectories parallel to this directory. Will deal with
#     this issue later when menu_file subroutine is completed and completely
#     recursive
# 
# TIPS:
# 
# Put a .nopixdir2htmlrc file in directories for which you do not want
# thumbnails and/or index.html to be written
#

use File::Copy;
use Getopt::Long;
Getopt::Long::Configure('bundling');

use File::Find;     # find();
use File::Basename; # basename();

use strict;
use vars qw( $VERSION @INC );
use Config;

my $VERSION="0.5";

$|++; # disable buffer

my $USAGE = "pixdir2html.pl [-n|--nomenu] 
                            [-f|--force] 
                            [M|menuonly]
                            [E|extension]
                            [D|directory]
 
   force    - creates a .pixdir2htmlrc in every subdir overriding
              any file with that name
   nomenu   - do not create menus after finishing creating thumbnails
   menuonly - only create a menu file and exit
   extension- use this extension instead of default (php)
   directory- use this directory instead of default (current)
   help     - prints this help and exit\n
  
   e.g.
    cd /path/to/picture_directory
    pixdir2html --extension='html'
   ";

# update these if needed
my $ROOT_DIRECTORY=".";

my $LOG="$ROOT_DIRECTORY/pixdir2html.log";

my $CONFIG_FILE=".pixdir2htmlrc";

my $THUMBNAIL="t";  # individual thumnails
my $HTMLDIR="h";    # individual HTML files

my $EXT="php";     # default extension for generated HTML files

# list directories that should be skipped here
# separated by |
my $EXCEPTION_LIST = "CVS|RCS";
# regex of files we want to include
my $EXT_INCL_EXPR = "\.(jpg|png|jpeg|gif)";

# How big are the thumbnails?
# This is the default, in case the config file
# doesn't exist or do not have this item in it
my $PERCENT="20%";
# How many TDs per table?
my $td=4;
# How many TDs per menu table?
my $menu_td=10;

# dont worry if you don't have a log rotation facility...
# just leave it as is
my $SAVELOG = "/usr/bin/savelog";

###Nothing below this line should need to be configured.###
#**************************************************************#

my @pixdir = (); # for menu
my @pixfile = (); # for thumbfiles/pictures

my %myconfig = (); # init config hash

my $total_directories=0;
my $total_links=0;

#my $ROOT_DIRECTORY=".";

my $FORCE=0; 
my $NOMENU=0; 
my $MENUONLY=0;
my $HELP=0;

# get options
GetOptions(
    # flags
    'n|nomenu' => \$NOMENU,
    'f|force' => \$FORCE,
    'h|help' => \$HELP,
    'M|menuonly' =>\$MENUONLY,
    # strings
    'E|extension=s' =>\$EXT,
    'D|directory=s' =>\$ROOT_DIRECTORY
);

die $USAGE if $HELP;

my $FILE_NAME="index.$EXT";
my $MENU_NAME="menu.$EXT";
my $menu_str="";

my $THUMBNAILSDIR="$ROOT_DIRECTORY/$THUMBNAIL";
my $HTMLSDIR="$ROOT_DIRECTORY/$HTMLDIR";

warn << "__EOF__";
Perl PixDir2HTML v$VERSION 
(Luis Mondesi <lemsx1\@hotmail.com> / LatinoMixed.com) 
(running with Perl $] on $Config{'archname'}) \n \n
__EOF__

main();

#-------------------------------------------------#
#                     FUNCTIONS                   #
#-------------------------------------------------#
sub main {
    # are we creating a menu file only?
    if ( $MENUONLY > 0 ) {
        print LOGFILE ("Creating menu file\n");
        menu_file();
        return 0;
    }
    
    if (!-x "/usr/bin/convert") {
        die ("could not find 'convert'. Install ImageMagick.");
    }
    open (LOGFILE,"> $LOG");
    init_config(".");
    # get menu string
    unless ( $NOMENU == 1 ) {
        print LOGFILE ("Creating menu file\n");
        $menu_str = menu_file();
    }
    # make all thumbnails and indices
    mkthumb($ROOT_DIRECTORY,$menu_str);
    # make all supporting HTML files
    thumb_html_files($ROOT_DIRECTORY);
    
    close(LOGFILE);
    if ( -x $SAVELOG ) {
        system("$SAVELOG $LOG > /dev/null 2>&1");
    }

    print STDOUT "$total_directories directories.\n Read log $LOG for details. \n";
    return 0;
} # endmain

sub init_config {
    # Takes one argument:
    # ROOT = directory from which we will take the config file   

    my %config_tmp = "";
    
    my $ROOT = shift;
    if (open(CONFIG, "<$ROOT/$CONFIG_FILE")){
        while (<CONFIG>) {
            next if /^\s*#/;
            chomp;
            $config_tmp{$1} = $2 if m/^\s*([^=]+)=(.+)/;
        }
        close(CONFIG);

    } else {
        warn << "__EOF__";
   Could not find $ROOT/$CONFIG_FILE 
__EOF__

        $config_tmp{percent}="20%";
        $config_tmp{title}="Images";
        $config_tmp{meta}="<meta http-equiv='content-type' content='text/html;charset=iso-8859-1'>";
        $config_tmp{stylesheet}="<link rel='stylesheet' href='../styles.css' type='text/css'>";
        $config_tmp{html_msg}="<h1>Free form HTML</h1>";
        $config_tmp{body}="<body bgcolor='#000000' text='#ffffff'>";
        $config_tmp{p}="<p>";
        $config_tmp{table}="<table border='0'>";
        $config_tmp{td}="<td valign='top' align='left'>";
        $config_tmp{tr}="<tr>";
        $config_tmp{footer}="";

    }
    
    #construct a header if it doesn't yet exist:
    if ( $config_tmp{header} eq "" ) {

        print LOGFILE ("Blank header. Generating my own ... \n");

        $config_tmp{header}="<html>
        <head>
        ".$config_tmp{meta}."
        <title>".$config_tmp{title}."</title>
        ".$config_tmp{stylesheet}."
        </head>".
        $config_tmp{body}."
        <center>".
        $config_tmp{html_msg}."
        \n
        ";
    }

    return %config_tmp;
}

sub mkthumb {
    # Takes one argument directory to create images for
    # If a directory is found inside this directory containing
    # images, then it recursively calls itself over and over

    my $ROOT = $_[0];
    my $MENU_STR = $_[1];

    $THUMBNAILSDIR="$ROOT/$THUMBNAIL";

    my @subdir = ();
    my @ls = ();
    my @ts = ();
    my %myconfig = ();

    my $line = "";
    my $thisFile= "";
    my $i=0;
    my $total_picts=0;
    
    opendir (DIR,"$ROOT") || die "Couldn't open dir $ROOT";
    
    print LOGFILE ("Working in $ROOT \n");
    
    # construct array of all image files
    while (defined($thisFile = readdir(DIR))) {
        next if ($thisFile =~ m/$EXCEPTION_LIST/);
        next if ($thisFile !~ /\w/);
        next if ($thisFile =~ /^\..*/); 
        if (
            -d "$ROOT/$thisFile" 
            && $thisFile !~ m/^$THUMBNAIL$/ 
            && $thisFile !~ m/^$HTMLDIR$/
        ) {
            if (-f "$ROOT/$thisFile/.nopixdir2htmlrc") {
                print LOGFILE ".nopixdir2htmlrc file exists in ($thisFile). Skipping ...\n";
                next;
            }
            $total_directories++;
            push @subdir,"$ROOT/$thisFile";
   
            if (-f "$ROOT/$thisFile/$CONFIG_FILE") {
                if ($FORCE == 1) {
                    if ( 
                        copy("$ROOT_DIRECTORY/$CONFIG_FILE", 
                            "$ROOT/$thisFile/$CONFIG_FILE") 
                    ) {
                        print LOGFILE ("force copied $ROOT_DIRECTORY/$CONFIG_FILE \
                            to $ROOT/$thisFile/$CONFIG_FILE \n");
                    }
                } 
            } else {
                #file doesn't exist, copy it
                if (
                copy("$ROOT_DIRECTORY/$CONFIG_FILE", 
                    "$ROOT/$thisFile/$CONFIG_FILE")
                ) {
                    print LOGFILE ("copied $CONFIG_FILE to \
                        $ROOT/$thisFile/$CONFIG_FILE \n");
                }
            }
        }
        next if ($thisFile !~ m/$EXT_INCL_EXPR/i);
        push @ls,$thisFile;
        $total_picts++;
    } #end images array creation
    closedir(DIR);

    #do we already have a dir with this name? no, then create one
    if (!-d "$THUMBNAILSDIR" && !-f "$ROOT/.nopixdir2htmlrc") { 
        print LOGFILE ("making thumbnails directory in $THUMBNAILSDIR\n");
        # only create directory if at least one image file exists here
        if ( -f $ROOT."/".$ls[0] ) {
            mkdir("$THUMBNAILSDIR",0755);
        }
    }

    if (!-f "$ROOT/.nopixdir2htmlrc" && -f $ROOT."/".$ls[0] ) {
       
        # read specific config file for this directory
        %myconfig = init_config($ROOT);
        
        open(FILE, "> $ROOT/$FILE_NAME") || die "Couldn't write file $FILE_NAME to $ROOT";

        # Percentage for this directory?
        $PERCENT = ("$myconfig{percent}") ? $myconfig{percent}:$PERCENT;

        # start HTML
        print FILE ("$myconfig{header}\n");
        
        # print menu (if any)
        print FILE ("$MENU_STR");

        # start table
        print FILE ("$myconfig{table}\n");

        my ($my_bgcolor,$file_name) = "";

        #print all picts now
        foreach(@ls){
            if ( !-f "$THUMBNAILSDIR/"."t$_" ){
                # create thumbnail 
                if ( -f "$ROOT/$_" ){

                    print LOGFILE ("\nConverting file $ROOT/$_ into $THUMBNAILSDIR/t$_ \n");
                    system("convert -geometry $PERCENT $ROOT/$_ $THUMBNAILSDIR/"."t$_");
                    if ( $? != 0 ) {
                        die "ERROR: conversion failed\n";
                    }

                    print LOGFILE ("\n"); 
                } # end if -f ROOT/ls[i]
            } # end if THUMBNAILSDIR/myfile

            if ($i == 0) {
                # open a new row
                if ( $myconfig{tr} =~ m/\%+bgcolor\%+/i ) {
                    ($myconfig{tr} = $myconfig{tr}) =~ s/\%+bgcolor\%+//i;
                }

                print FILE ($myconfig{tr}."\n");
            } 
            print FILE ("\t".$myconfig{td}."\n");
            if (-f "$THUMBNAILSDIR/"."t$_"){
                # if file exists, create a link, otherwise leave it blank
                ($file_name = $_) =~ s/$EXT_INCL_EXPR//g;
                print FILE ("<a href='$HTMLDIR/$file_name.$EXT'><img src='$THUMBNAIL/"."t$_'></a>\n");
            } else {
                print FILE ("&nbsp;");
            }
            print FILE ("\t</td>\n");
            if ($i<($td-1)) {
                $i++;
            } else {
                # wrap and reset counter
                print FILE ("</tr>\n");
                $i = 0;
            }
        } #end foreach
        # complete missing TD
        if ($i != 0) {
            for (;$i<$td;$i++) {
                print FILE ("\t".$myconfig{td}."\n");
                print FILE ("&nbsp;");
                print FILE ("\t</td>\n");
            }
        }
        print FILE ("</tr>\n");
        print FILE ("</table>\n");

# close the footer if one doesn't exist:
        if ( $myconfig{footer} eq "" ) {
            print FILE ($myconfig{footer}."\n");
            print FILE ("</center></body>\n");
            print FILE ("</HTML>");
        } else {

            print FILE ($myconfig{footer});
        }
        close(FILE);
        print LOGFILE "Counted $total_picts pictures here $ROOT\n";
    }

# loop thru rest of directories
    foreach(@subdir){
        mkthumb($_,$MENU_STR); 
    }
} #end mkthumb

sub thumb_html_files {
    # creates an HTML page for a thumbnail
    my $ROOT = $_[0];
    
    # locals
    my (@ls,%myconfig) = ();
    my $i = 0;
    my ($thisFile,
        $pix_name,
        $file_name,
        $next_pix_name,
        $next_file_name,
        $last_pix_name,
        $last_html_file,
        $current_html_file,
        $last_file_name,
        $current_link,
        $last_link,
        $BASE,
        $tmp_BASE,
        $LAST_BASE,
        $NEXT_BASE,
        $HTMLSDIR) = "";


    print LOGFILE ("Making HTML files in $ROOT \n");

    #construct array of all image files
    my @ary = do_file_ary("$ROOT");

    # parse array of images
    foreach (@ary){
        $thisFile = basename($_);
        next if ($thisFile =~ m/$EXCEPTION_LIST/);
        next if ($thisFile !~ m/$EXT_INCL_EXPR/i);
        next if ($_ =~ m/\/$THUMBNAIL\/.*$EXT_INCL_EXPR$/i);
        push @ls,$_;
    } #end images array creation
   
        #print all picts now
    foreach(@ls){
        $pix_name = basename($_);
        # strip extension from file name
        ($file_name = $pix_name) =~ s/$EXT_INCL_EXPR//g;
        # get base directory
        ( $BASE = $_ ) =~ s/(.*)\/$pix_name$/$1/g;
        #print STDOUT $BASE."\n";

        if ( $BASE !~ m/$tmp_BASE/ ) {
            print LOGFILE "reading config for $BASE\n";
            # read specific config file for this directory
            %myconfig = init_config($BASE);
            # construct PATH for html directory
            $HTMLSDIR = "$BASE/$HTMLDIR";
        } 
        # update flag
        $tmp_BASE = $BASE;
        next if ( -f "$BASE/.nopixdir2htmlrc" );

        if (!-d "$HTMLSDIR") { 
            print LOGFILE ("making html files directory in $BASE\n");
            mkdir("$HTMLSDIR",0755);
        }

        my $current_html_file = "$HTMLSDIR/$file_name.$EXT";
        my $current_link = "$file_name.$EXT";

        if ( -f $current_html_file ){
            print LOGFILE "WARNING: overriding $current_html_file\n";
        } # end if not current_html_file

        print LOGFILE ("\ncreating html file into $current_html_file\n");
        # TODO routine for creating file should be called here...
        open(FILE, "> $current_html_file") || 
        die "Couldn't write file $current_html_file";

        # start HTML
        print FILE ("$myconfig{header}\n");

        # start table
        print FILE ("$myconfig{table}\n");
        print FILE ("<tr><td>\n");

        # image here
        print FILE ("<img src='../$pix_name'>\n");
        print FILE ("</td></tr>\n<tr><td valign='bottom' align='center'><div align='center'>\n");

        # back link here
        if ( -f $last_html_file && ($BASE =~ m/$LAST_BASE/) ) {
            print FILE ("<a href='$last_link'>&lt;==</a>\n"); 
        } else {
            print FILE ("&lt;==");
        }

        # home link here
        print FILE (" | <a href='../$FILE_NAME'>HOME</a> | \n");
        # next link here
        # calculate next base
        $next_pix_name = basename($ls[$i+1]);
        # get next base directory
        ( $NEXT_BASE = $ls[$i+1] ) =~ s/(.*)\/$next_pix_name$/$1/g;
 
        if ( -f $ls[$i+1] && ( $BASE =~ m/$NEXT_BASE/ ) ) {
            ($next_file_name = $next_pix_name) =~ s/$EXT_INCL_EXPR//g;
            print FILE ("<a href='$next_file_name.$EXT'>==&gt;</a>\n");
        } else {
            print FILE ("==&gt;");
            # TODO would be nice to jump to next directory in the
            #       array... 
            #print FILE (" <a href='../$next_file_name.$EXT'> |=&gt;&gt;</a> \n");

        }
        print FILE ("</div></td></tr>\n");
        print FILE ("</table>\n");

        # close the footer if one doesn't exist:
        if ( $myconfig{footer} eq "" ) {
            print FILE ($myconfig{footer}."\n");
            print FILE ("</center></body>\n");
            print FILE ("</HTML>");
        } else {
            print FILE ($myconfig{footer});
        }            
        close(FILE);
        # end HTML

        print LOGFILE ("\n"); 

        # increase array counter
        $i++; 
        # keep track of links
        $last_html_file = $current_html_file;
        $last_link = $current_link;
        # update flags
        $LAST_BASE = $BASE;
        #$PRINT_NEXT_LINK = 0;
    } #end foreach

}

sub prompt {
    # promt user and return input 
    # pass string when calling subroutine: $var = prompt("string");
    my($string) = $_[0];#shift;
    my($input) = "";
    
        #if ($Suppress_readline) { 
    print ("* ".$string."\n");
    chomp($input = <STDIN>);
        # chomp is the same as:
        # $input =~ s/\n//g; # remove lineend
        #} else {
        # No readline support for now
        #$input = $term->readline($string);
        #}
    return $input;
}

sub do_dir_ary {
    # uses find() to recur thru directories
    # returns an array of directories
    # i.e. in directory "a" with structure:
    # /a
    # /a/b
    # /a/b/c
    # /a/b2/c2
    # 
    # my @ary = &do_dir_ary(".");
    # 
    # will yield:
    # a
    # a/b
    # a/b/c
    # a/b2/c2
    # 
    my $ROOT = shift;
    
    my %opt = (wanted => \&process_dir, no_chdir=>1);
    
    find(\%opt,$ROOT);
    
    return @pixdir;
}

sub process_dir {
    my $base_name = basename($_);
    if ( 
        !-f $_ && 
        $base_name !~ m/^($EXCEPTION_LIST|$THUMBNAIL|$HTMLDIR|\..*)$/ 
    ) {
        s/^\.\/*//g;
        push @pixdir,$_;
    }
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
    
    return @pixfile;
}

sub process_file {
    my $base_name = basename($_);
    if ( 
        -f $_ && 
        $base_name !~ m/^($EXCEPTION_LIST|$THUMBNAIL|$HTMLDIR|\..*)$/ 
    ) {
        s/^\.\/*//g;
        push @pixfile,$_;
    }
}

sub menu_file {
    #---------------------------------------------#
    # It creates a menu.$EXT file at 
    # the root level of the picture
    # directory (at the first 
    # directory that was passed to the script) or
    # it puts a menu in e/a index.$EXT file
    #
    # if there is a file named .new 
    # inside the given directory,
    # then a IMG tag will be put in 
    # front of the link with an image
    # src=myscript{new} in it
    # 
    # Thus in the config file put a line as such:
    # new=http://images.server.com/new_icon.png;
    #----------------------------------------------#

    # TODO this was read at some point... maybe it
    # should be passed to this function in some way...
    my %myconfig = init_config($ROOT_DIRECTORY);

    my $MENU_STR = ""; # return this instead of making file

    my $IMG = ""; 
    my $line = "";
    #my $thisFile= "";
    my $x=0;    # counts number of links
    my $y=0;    # counts number of td's
    my $i=0;    # general purpose counter
    my $j=0;    # count number of TR's

    my @ls = ();
    my $ts = "";
    my @files=();
    my @pixdir = (); # reset array

    my @ary = do_dir_ary("$ROOT_DIRECTORY");

    foreach(@ary){
        if (
            !-f "$ROOT_DIRECTORY/$_/.nopixdir2htmlrc"
            #-f "$ROOT_DIRECTORY/$_/$FILE_NAME"
        ) {
            # note that @ls holds the HTML links...
            $ls[$x] = "$_/$FILE_NAME"; # why not push()?
            $x++; 
        }
    }   

    $total_links = $x;

    # sort menus alphabetically (dictionary order):
    # print STDERR join(' ', @ls), "\n";
    my $da;
    my $db;
    @ls = sort { 
        ($da = lc $a) =~ s/[\W_]+//g;
        ($db = lc $b) =~ s/[\W_]+//g;
        $da cmp $db;
    } @ls;

    if ( $MENUONLY > 0 ) {
        open(FILE, "> $ROOT_DIRECTORY/$MENU_NAME") ||
        die "Couldn't write file $MENU_NAME to $ROOT_DIRECTORY";
    }

    if ($myconfig{nomenuheader_footer} == 0) {
        if ( $MENUONLY > 0 ) {
            print FILE ($myconfig{header}."\n");
        }
        $MENU_STR .= $myconfig{header}."\n";
    }
    if ( $MENUONLY > 0 ) {
        print FILE ("$myconfig{table}\n");
    }
    $MENU_STR .= "$myconfig{table}\n";

    # print all links now

    my $tmp_tr = ""; # used to color the rows

    while($x>0){
        # temporarily turn off warnings
        no warnings;
        if ( $MENUONLY > 0 ) {
            if ($myconfig{tr}=~m/\%+bgcolor\%+/i){
                if (($j % 2) == 0){
                    ($tmp_tr = $myconfig{tr}) =~ s/\%+bgcolor\%+/bgcolor=#efefef/i;
                } else {
                    ($tmp_tr = $myconfig{tr}) =~ s/\%+bgcolor\%+//i;
                }

                print FILE ($tmp_tr."\n");
                #$MENU_STR .= $tmp_tr."\n";

            } else {
                print FILE ($myconfig{tr}."\n");
                #$MENU_STR .= $myconfig{tr}."\n";
            }
            for ($y=1;$y<=$menu_td;$y++){
                # close the TD tags
                if ($y > 1) { 
                    print FILE ("\t </td> \n"); 
                    #$MENU_STR .= "\t </td> \n";
                }   
                print FILE ("\t".$myconfig{td}."\n");
                #$MENU_STR .= "\t".$myconfig{td}."\n";

                if ( $ls[$i] ne "" ) {
                    # if link exists, otherwise leave it blank
                    # TODO there is a better way to do this... find it...
                    ($ts = $ls[$i]) =~ s/(.*)\/$FILE_NAME/$1/gi;
                    $IMG = (-f "$ts/.new") ? "<img valign='middle' border=0 src='$myconfig{new}' alt='new'>":""; # if .new file
                    $ts = ucfirst($ts);
                    print FILE ("<a href='$myconfig{uri}/$ls[$i]' target='_top'>$IMG $ts</a>\n");
                    #$MENU_STR .= "<a href='$myconfig{uri}/$ls[$i]' target='_top'>$IMG $ts</a>\n";
                } else {
                    print FILE ("&nbsp;");
                    #$MENU_STR .= "&nbsp;";
                }
                $i++;
                $x--;
            } # end for $y
            print FILE ("</tr>\n");
            #$MENU_STR .= "</tr>\n";
            $j++; # incr TR counter

        } else {
            # TODO cleanup
            if ($myconfig{tr}=~m/\%+bgcolor\%+/i){
                if (($j % 2) == 0){
                    ($tmp_tr = $myconfig{tr}) =~ s/\%+bgcolor\%+/bgcolor=#efefef/i;
                } else {
                    ($tmp_tr = $myconfig{tr}) =~ s/\%+bgcolor\%+//i;
                }

                $MENU_STR .= $tmp_tr."\n";

            } else {
                $MENU_STR .= $myconfig{tr}."\n";
            }
            for ($y=1;$y<=$menu_td;$y++){
                # close the TD tags
                if ($y > 1) { 
                    $MENU_STR .= "\t </td> \n";
                }   
                $MENU_STR .= "\t".$myconfig{td}."\n";

                if ( $ls[$i] ne "" ) {
                    # if link exists, otherwise leave it blank
                    # TODO there is a better way to do this... find it...
                    ($ts = $ls[$i]) =~ s/(.*)\/$FILE_NAME/$1/gi;
                    $IMG = (-f "$ts/.new") ? "<img valign='middle' border=0 src='$myconfig{new}' alt='new'>":""; # if .new file
                    $ts = ucfirst($ts);
                    $MENU_STR .= "<a href='$myconfig{uri}/../$ls[$i]' target='_top'>$IMG $ts</a>\n";
                } else {
                    $MENU_STR .= "&nbsp;";
                }
                $i++;
                $x--;
            } # end for $y
            $MENU_STR .= "</tr>\n";
            $j++; # incr TR counter
        } # end if/else menuonly
    }
    if ( $MENUONLY > 0 ) {
        print FILE ("</table>\n");
    }
    $MENU_STR .= "</table>\n";

    if ($myconfig{nomenuheader_footer} == 0) {
        if ( $MENUONLY > 0 ) {
            print FILE ($myconfig{footer}."\n");
        } 
        $MENU_STR .= $myconfig{footer}."\n";
    }

    if ( $MENUONLY > 0 ) {
        close(FILE);
    }

    print STDERR "$total_links links in menu.\n";
    return $MENU_STR;
}
