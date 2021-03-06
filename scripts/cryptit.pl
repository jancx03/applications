#!/usr/bin/perl -w
#
# Copyright Red Hat, Inc. 2000
# By Owen Taylor <otaylor@redhat.com>
#
# You may use, distribute and modify this program without restriction
#
# Version 1.1 Nov 29, 2000
# - add support for entering seed by hand if you can't open /dev/random
#

BEGIN {
    use POSIX qw(:termios_h);
    
    my ($term, $oterm, $echo, $noecho, $fd_stdin);
    
    $fd_stdin = fileno(STDIN);
    
    $term     = POSIX::Termios->new();
    $term->getattr($fd_stdin);
    $oterm     = $term->getlflag();
    
    $echo     = ECHO | ECHOK | ICANON;
    $noecho   = $oterm & ~$echo;
    
    sub noecho {
	$term->setlflag($noecho);
	$term->setattr($fd_stdin, TCSANOW);    
}
    
    sub echo {
	$term->setlflag($oterm);
	$term->setattr($fd_stdin, TCSANOW);    
    }
}

END { echo() }

# Get random seed 

if (open(RANDOM, "/dev/random")) {
    read(RANDOM, $a, 8) || die "Can't read: $!";
    close RANDOM;
    
    $seed = join ("", map { chr(ord('0') + ord($_)%64) } split //,$a);
    $seed =~ s/[^A-Za-z0-9]//g;
    $seed = substr($seed,0,2);
} else {
 again:
    print "Enter some random characters for the seed: ";
    noecho;
    $seed = <>;
    chomp($seed);
    $seed =~ s/[^A-Za-z0-9]//g;
    echo;
    print "\n";
    if (length $seed < 2) {
	print "Seed must contain at least two letters and/or numbers\n";
	goto again;
    }
    $seed = substr($seed,0,2);
}


my ($result1, $result2);

$| = 0;

while (1) {
    print "Enter passwd: ";
    noecho;
    $password = <>;
    chomp($password);
    $result1 = crypt($password, $seed);
    echo;
    print "\nReenter passwd to verify: ";
    noecho;
    $password = <>;
    chomp($password);
    $result2 = crypt($password, $seed);
    echo;

    if ($result1 ne $result2) {
	print "\nPasswords did not match, try again\n";
    } else {
	last;
    }
}

print "\nCrypted value is: $result1\n";
