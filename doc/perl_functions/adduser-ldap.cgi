#!/usr/bin/perl -w
# $Revision: 1.2 $
# Luis Mondesi <lemsx1@gmail.com> 
#
# DESCRIPTION: Adds user to ldap server running on (tls) 
# ldap://$LDAPSERVER:389
# This is NOT a POSIX user, just a regular user to allow chatting
#
# This is a modified version of my original script, adduser-ldap.pl
# http://lems.kiskeyix.org/toolbox/?f=adduser-ldap.pl
# USAGE: from browser
# LICENSE: GPL
###

use strict;
$|++;    # disable buffer (autoflush)

use Carp;                     # croak() cluck() carp()
eval "use Net::LDAP";
if ($@)
{
    print STDERR "\nERROR: Could not load the Net::LDAP module.\n"
      . "       To install this module use:\n"
      . "       Use: perl -e shell -MCPAN to install it.\n"
      . "       On Debian just: apt-get install perl-modules \n\n"
      . print STDERR "$@\n";
    exit 1;
}
eval "use CGI qw/:cgi/";
if ($@)
{
    print STDERR "\nERROR: Could not load the CGI module.\n"
      . "       To install this module use:\n"
      . "       Use: perl -e shell -MCPAN to install it.\n"
      . "       On Debian just: apt-get install perl-modules \n\n"
      . print STDERR "$@\n";
    exit 1;
}
eval "use Net::SMTP";
if ($@)
{
    print STDERR (
                  "\nERROR: Could not load the Net::SMTP module.\n",
                  "       To install this module use:\n",
                  "       perl -e shell -MCPAN.\n",
                  "       On Debian just: apt-get install perl-modules \n\n",
                  "\n"
                 );
    exit 1;
}

my $DEBUG = 0;

my $MAILHOST      = "localhost";                          # use this mail server
my $FROM          = "AccountControl\@example.com";
my $CC            = "Security\@example.com";
my $SUBJECT       = "New chat.example.com Account";
my $TIMEOUT       = 90;                                   # smtp timeout
my $TEMPLATE_MESSAGE = <<EOF;
Hello \@firstname\@,

Your new chat.example.com account is:

User Name:  \@username\@
Password:   \@password\@
Server:     chat.example.com
Port:       5222

Encryption is required (TLS)

Notes:
* Clients that are known to work
    - Exodus 0.9.1 (http://www.jabberstudio.org/projects/exodus/releases/)
    - Gaim 2.0b3   (http://sourceforge.net/project/showfiles.php?group_id=235)

* To search for other Chat users, use the server "search.chat.example.com"
EOF

my $LDAPADMINCN =
  "uid=admin,ou=Administrators,ou=TopologyManagement,o=netscapeRoot";
my $LDAPPASSWORDFILE = "/etc/adduser-ldap.secret";
# man Net::LDAP
my $LDAPCACERT       = '/etc/ldap/cacerts/5eb9559f.0';
my $LDAPSERVER       = "ldap.example.com";
my $OU               = "People";
my $DOMAIN           = "example.com";

my $PASS_SCHEME      = "{crypt}";

# ------------------------------------------------------------------- #
#                   DO NOT MODIFY BELOW THIS LINE                     #
# ------------------------------------------------------------------- #

my $html = new CGI;

# these fields will be normalized to lowercase lc() and no extra chars ( anything not matching
# /[[:alnum:]]/ ) will be removed.
#
# Note that "domain" was explicitly left out
my @fields =
  ("First Name", "Last Name", "User Name", "Password", "E-Mail", "Telephone");

my $style = <<EOF;
SELECT,TEXTAREA
{
    font-family : Verdana, "hoefler text", Tahoma, Helvetica, sans-serif;
    font-size : 10pt;
    color : #808080;
    text-decoration : none;
}
BODY
{
    font-family : Verdana, "hoefler text", Tahoma, Helvetica, sans-serif;
    font-size : 11pt;
    color : #808080;
    text-decoration : none;
    background: #ffffff;
}
input {
    border: #000 1px solid;
    margin: 3px;
}
hr {
    color:  #808080;
    height: 1px;
    width: 80%;
}
.template {
    font-family : Arial,Verdana, "hoefler text", Tahoma, Helvetica, sans-serif;
    font-size : 12pt;
    color : #000000;
    text-decoration : none;
    background: #ffffff;
}
.smalltext {
        font-size: 6pt;
        font-family: sans-serif;
}
.errortext {
        font-size: 10pt;
        font-family: sans-serif;
        color: red;
}
.debugtext {
        font-size: 14pt;
        font-family: sans-serif;
        color: red;
}
.successtext {
        font-size: 10pt;
        font-family: sans-serif;
        color: green;
}

EOF

my $jscript = <<EOF;
    
    function update_subject(element)
    {
        document.form1.subject.value = element.options[element.selectedIndex].text;
        document.form1.submit();
    }

    function update_form(element)
    {
        var fname = document.form1.firstname.value;
        var lname = document.form1.lastname.value;

        if (document.form1.email)
        {
            document.form1.email.value = fname + '.' + lname + '\@example\.com';
        }
        if (document.form1.firstname)
        {
            document.form1.firstname.value = fname;
        }
        if (document.form1.lastname)
        {
            document.form1.lastname.value = lname;
        }
        if (document.form1.username)
        {
            var uname = fname.substring(0,1) + lname;
            if (document.form1.username.length > 1)
            {
                for (i=0;i<document.form1.username.length;i++)
                {
                    document.form1.username[i].value = uname;
                }
            } else {
                document.form1.username.value = uname;
            }
        }
    }

    function reset_form()
    {
        for (i=0;i<document.form1.elements.length;i++)
        {
            if (document.form1.elements[i].type == "text")
            {
                document.form1.elements[i].value = "foo";
            }
        }
    }

EOF

# helper functions

sub print_form
{
    print $html->h1("Add chat.example.com User");
    print $html->hr();
    print $html->start_form('-name'   => "form1",
                            '-action' => "/cgi-bin/adduser-chat.cgi");
    print $html->start_table(), "\n";
    foreach (@fields)
    {
        my $_f = lc($_);
        $_f =~ s/[^[:alnum:]]//g;
        print STDOUT ($html->start_Tr(), "\n", $html->td($_ . ': '), "\n",);
        if ($_f eq "username")
        {

            # allows changing of username (see javascript code)
            print $html->td ($html->textfield('-name' => $_f));
        }
        else
        {
            print $html->td(
                            $html->textfield(
                                             '-name'       => $_f,
                                             '-onkeypress' => "update_form()",
                                             '-onchange'   => "update_form()"
                                            )
                           );
        }
        print $html->end_Tr();
    }
    print $html->end_table();
    print $html->p({'-class' => 'smalltext'},
                   "Sample password: " . random_password(8));
    print $html->reset() . " " . $html->submit() . "\n";
    print $html->end_form();
    print $html->hr();
}

sub random_password
{
    my $num = shift;
    if ($num !~ /^[[:digit:]]+$/ or $num < 8)
    {
        $num = 8;
    }
    my $count          = $num;
    my @password_chars = ('.', '/', 0 .. 9, 'A' .. 'Z', 'a' .. 'z');
    my $_password      = undef;
    for (1 .. $count)
    {
        $_password .= (@password_chars)[rand(@password_chars)];
    }
    return $_password;
}

sub hash_password
{
    my $str  = shift;
    my $hash = "x";
    if ( ${PASS_SCHEME} =~ /crypt/i )
    {
        # generates an MD5 sum salted password with 8 random chars
        $hash = crypt($str,"\$1\$".random_password(8)."\$");
    }
    return $hash;
}

sub _create_entry
{
    my ($ldap, $dn, $whatToCreate) = @_;
    if (0)
    {
        print "<pre>";
        print("dn: ", $dn, "\n");
        foreach (@$whatToCreate)
        {
            print($_, "\n");
        }
        print "</pre>";
    }
    my $result = $ldap->add($dn, 'attr' => [@$whatToCreate]);
    return $result;
}

sub _get_password
{
    my $file = shift;
    if (-r $file)
    {
        open(PW, "<$file") or die("Could not read file $file. " . $!);
        undef $/;    # slurp mode
        my $content = <PW>;
        $content =~ s/(\r|\n)//g;
        return $content;
    }
    else
    {
        die("Could not read password file $file\n");
    }
}

sub _send_email
{
    my $email = shift;

    # sanity check:
    my $MAILHOST =
      (exists $email->{'mailhost'} and $email->{'mailhost'} !~ /^\s*$/)
      ? $email->{'mailhost'}
      : "localhost";
    my $FROM =
      (exists $email->{'from'} and $email->{'from'} !~ /^\s*$/)
      ? $email->{'from'}
      : $ENV{'USER'};
    my $CC =
      (exists $email->{'cc'} and $email->{'cc'} !~ /^\s*$/)
      ? $email->{'cc'}
      : "";
    my $TIMEOUT =
      (exists $email->{'timeout'} and $email->{'timeout'} !~ /^\s*$/)
      ? $email->{'timeout'}
      : 90;

    # create object
    my $smtp = Net::SMTP->new($MAILHOST, 'Timeout' => $TIMEOUT);
    $smtp->mail($FROM);

    # TODO validate $to address?
    my $_to = (exists($email->{"to"})) ? $email->{"to"} : $ENV{'USER'};

    $smtp->to($_to);
    $smtp->cc($CC) if ($CC ne "");

    $smtp->data();
    $smtp->datasend("To: $_to\n");
    my $_subj = (exists($email->{"subject"})) ? $email->{"subject"} : "";
    $smtp->datasend("Subject: $_subj\n");
    my $_msg = (exists($email->{"message"})) ? $email->{"message"} : "";
    $smtp->datasend("$_msg\n");
    $smtp->datasend();

    $smtp->quit;
}

sub _debug
{
    my $str = shift;
    print "<p class='debugtext'>$str</p>\n" if ($DEBUG);
}

# end helper functions

# main ()
print $html->header();
print $html->start_html(
                        '-title'  => 'New chat.example.com account',
                        '-script' => $jscript,
                        '-style'  => {
                                     '-src'  => "/styles/style.css",
                                     '-code' => $style
                                    }
                       );

# web form to ask for what to do
print_form();

# handle POST
if ($html->param())
{
    my $first     = $html->param('firstname');
    my $last      = $html->param('lastname');
    my $uid       = $html->param('username');
    my $password  = $html->param('password');
    my $email     = $html->param('email');
    my $domain    = $DOMAIN;                    # if (!$html->params('domain'));
    my $telephone = "555.555.5555";

    print STDERR (
        "Missing first name and/or last name. Click back in your browser to fix it.\n"
      )
      and exit(1)
      if ($first eq "" || $last eq "");         # || $domain eq "");

    # set some internal vars:
    my @domain_parts = split(/\./, $domain);

    # create UID and MID using scheme:
    #   (first letter of first name) + (last name)
    $uid = ($uid) ? $uid : lc(substr($first, 0, 1) . $last);
    my $mid = lc($first) . '.' . lc($last);

    my $full_name = ucfirst($first) . " " . ucfirst($last);

    #my $initials  = substr($first, 0, 1) . substr($last, 0, 1);

    my $ou = ($OU) ? "ou=$OU, " : "ou=People, ";
    my $domain_joined = "";
    foreach (@domain_parts)
    {
        $domain_joined .= "dc=$_, ";
    }
    $domain_joined =~ s/, $//;

    my $RANDOM_PASSWORD_USED = 0;    # set when user forgets to set password

    if (!$password)
    {
        $RANDOM_PASSWORD_USED = 1;
        $password             = random_password(8);
    }

    my $hash_password = hash_password($password);

    my $ldif = "
dn: uid=${uid},${ou}${domain_joined}
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetorgperson
cn: $full_name
sn: $last
givenName: $first
uid: $uid
mail: $mid\@$domain
telephoneNumber: $telephone
userPassword: ${PASS_SCHEME}${hash_password}
\n";

    # this is used by Net::LDAP
    my $create_dn = "uid=${uid},${ou}${domain_joined}";
    my $create_ary = [
                   objectClass =>
                     [ "top", "person", "organizationalPerson", "inetorgperson" ],
                   cn              => $full_name,
                   uid             => $uid,
                   givenName       => $first,
                   sn              => $last,
                   mail            => "${mid}\@${domain}",
                   telephoneNumber => $telephone,
                   userPassword    => "${PASS_SCHEME}${hash_password}"
    ];

    # make connection to LDAP server and handle uid creation
    print STDOUT ("<!-- \n", $ldif, "\n -->\n");

    my $ldap = Net::LDAP->new($LDAPSERVER);

    # TODO make sure we have the right access level to read
    # cafile below!
    #
    # you can comment this out if you have problems with TLS
    $ldap->start_tls('cafile' => $LDAPCACERT);

    _debug($LDAPADMINCN); 
    _debug(_get_password($LDAPPASSWORDFILE));

    my $mesg =
      $ldap->bind(
                  $LDAPADMINCN,
                  'password' => _get_password($LDAPPASSWORDFILE),
                  'version'  => '3'
                 );    # if bind() it binds anonymously
    $mesg =
      $ldap->search('base'   => "${domain_joined}",
                    'filter' => "uid=$uid");

    if (!$mesg->code())
    {

        # no errors were reported when we connected with the last
        # search(), now we need to know if the result matches

        my $FOUND_UID = 0;
        my $max       = $mesg->count();
        for (my $i = 0 ; $i < $max ; $i++)
        {
            my $entry = $mesg->entry($i);
            foreach my $attr ($entry->attributes())
            {
                next if ($attr !~ /uid/);
                if ($uid eq $entry->get_value($attr))
                {
                    $FOUND_UID++;
                    last;
                }
            }
        }

        if ($FOUND_UID)
        {

            # $mesg->error_text() yields success now...
            print $html->p({'-class' => 'errortext'},
                           "An user with uid $uid already exits");
            if ($DEBUG)
            {
                print $html->start_table();

                # already got my $max = $mesg->count();
                for (my $i = 0 ; $i < $max ; $i++)
                {
                    my $entry = $mesg->entry($i);
                    foreach my $attr ($entry->attributes())
                    {
                        next if ($attr =~ /passw/);    # skip password printing
                        print STDOUT (
                                      $html->Tr(
                                              $html->td($attr),
                                              $html->td(
                                                  $html->span(
                                                      {'-class' => 'errortext'},
                                                      $entry->get_value($attr)
                                                  )
                                              )
                                      ),
                                      "\n"
                                     );
                    }
                }
                print $html->end_table();
            }
            goto EXIT;
        }

        # at this point we can create the account
        my $entry_result = _create_entry($ldap, $create_dn, $create_ary);
        if ($entry_result->code())
        {
            print($html->p(
                     {'-class' => 'errortext'},
                     " Error while creating entry for uid $uid on $LDAPSERVER: "
                       . $mesg->error_text()
                 )
            );

            _debug(". Server message => code: ".$entry_result->code().". name: ".$entry_result->error_name().". text: ".$entry_result->error_text());
            goto EXIT;
        }

        print $html->p({'-class' => "successtext"},
                       "User $uid created (email: $mid\@$domain)");
        
        my $_message = $TEMPLATE_MESSAGE;
       
        $_message =~ s/\@fullname\@/$full_name/mi;
        $_message =~ s/\@username\@/$uid/mi;
        $_message =~ s/\@firstname\@/$first/mi;
        $_message =~ s/\@lastname\@/$last/mi;
        $_message =~ s/\@email\@/"${mid}\@${domain}"/mi;
        $_message =~ s/\@password\@/$password/mi;

        # send email:
        my %message = (
                   'mailhost' => $MAILHOST,
                   'subject'  => $SUBJECT,
                   'to'       => "${mid}\@${domain}",
                   'cc'       => $CC,
                   'from'     => $FROM,
                   'message'  => $_message
                  );

        _send_email(\%message);
    }
    else
    {
        print($html->p(
                       {'-class' => 'errortext'},
                       " Error while searching for uid $uid on $LDAPSERVER: "
                         . $mesg->error_text()
                      )
             );

        goto EXIT;
    }

    # some last minute messages
    print $html->hr();
    print $html->p({'-class' => "successtext"},
                   "Random password used is $password. This was emailed to the end-user $mid\@$domain"
                  )
      if ($RANDOM_PASSWORD_USED);

  EXIT:
    $mesg = $ldap->unbind();    # take down session
    $ldap->disconnect();

    #print STDERR ("Failed to create LDIF for $uid\@$domain");
}

print($html->end_html(), "\n");

# connect to LDAP server and do your thing
