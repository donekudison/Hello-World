

#!/usr/bin/perl
#----------------------------------------------------------------------------
# Subversion information:
# $HeadURL: http://prdsvnrepo:8080/svn/projects/src/main/resources/scripts/makeDirs.pl $
# $LastChangedDate: 2016-05-09 09:01:05 -0400 (Mon, 09 May 2016) $
# $LastChangedBy: udaj $
# $LastChangedRevision: 1389762 $
#----------------------------------------------------------------------------
use strict;
use XML::XPath;
use XML::XPath::XMLParser;
use Getopt::Std;
use File::Path;
use Cwd 'abs_path';

sub usage
{
    print "$0 -x <adx file> [-p <properties file>]\n";
    print " or \n";
    print "$0 -a <app> -r <release> [-p <properties file>]\n";
    exit( 1 );
}

sub evalString
{
    my $ptr = shift;
    my %props = %{ $ptr };
    my $str = shift;

    # hack for recursive evals
    # only works recursively 10 deep
    # should be good enoguh for now
    for ( my $i = 0; $i < 10; $i++ )
    {
        for my $key ( sort keys %props )
        {
            my $val = $props{ $key };
            $str =~ s/\$\{$key\}/$val/g;
        }
    }
    return $str;
}

#-----------------------------------------------------------------------------
# Preset all kinds of variables in a global sense...
#
# -> From perl_variables.pl
use vars qw{ %G %V };

#-----------------------------------------------------------------------------
# Get some variables from current path
#
use vars qw{ $runlevel $FULLSCRIPTNAME $SUBDIV };

$FULLSCRIPTNAME = abs_path($0);
#$FULLSCRIPTNAME = getcwd;
#$FULLSCRIPTNAME = $0;

$runlevel       = ( split /\//, $FULLSCRIPTNAME )[3];        #i.e. "dev", "prd"
( $runlevel )   = $runlevel =~ /([\w]+)/s;

$SUBDIV         = ( split /\//, $FULLSCRIPTNAME )[2];        #i.e. "ret", "crp", "ins"
( $SUBDIV )     = $SUBDIV =~ /([\w]+)/s;

#
# End getting variables from current path
#-----------------------------------------------------------------------------
# 

my %opts;
getopts( 'p:a:x:r:t', \%opts );


my $test = 0;
$test = 1 if $opts{ 't' };

my $adx = "";
$adx = $opts{ 'x' } if $opts{ 'x' };
$adx = "/cm/$SUBDIV/$runlevel/eet/RulesEngine/cf_xml/adx/" . uc( $opts{ 'a' } ) . '_' . $opts{ 'r' } . ".adx.xml" if $opts{ 'a' } && $opts{ 'r' };

usage() if $adx eq "";
my $propfile = "/cm/$SUBDIV/$runlevel/eet/RulesEngine/current/properties/arm.$runlevel.properties";
$propfile = $opts{ 'p' } if $opts{ 'p' };

die( "Cannot find adx file $adx" ) unless ( -e $adx );
die( "Cannot find properties file $propfile" ) unless ( -e $propfile );

my $user = `whoami`;
chomp $user;

my %props;

open( IN, $propfile );
while ( <IN> )
{
    chomp;
    s/#.*//g;
    s/\s*//g;
    next if $_ eq "";
    my ( $l, $r ) = split( /=/, $_, 2 );
    $props{ $l } = $r;
    #print( "$l=$r\n" );
}
close( IN );

if ( $props{ 'unix.chown.user' } ne $user )
{
    warn( "Not running as " . $props{ 'unix.chown.user' } . ", running in test mode\n" );
}


my $xp = XML::XPath->new( filename => $adx );
my $ns1 = $xp->find( '/L1_AppDefinition' );

my $app = "";
my $release = "";
my $apx_file = "";
my $epx_file = "";



foreach my $node1 ( $ns1->get_nodelist )
{
    $app = $node1->getAttribute( 'name' );
    $release = $node1->getAttribute( 'release' );
    $release = "v$release" unless m#^v#;
    $apx_file = "/cm/$SUBDIV/$runlevel/eet/RulesEngine/cf_xml/apx/" . $node1->getAttribute( 'apx_file' );
    $epx_file = "/cm/$SUBDIV/$runlevel/eet/RulesEngine/cf_xml/epx/" . $node1->getAttribute( 'epx_file' );
}

# Add App/Release specific entries
$props{ 'AppNameLC' } = lc( $app );
$props{ 'AppNameUC' } = uc( $app );
$props{ 'AppVerWithV' } = $release;
$props{ 'AppVerWithOutV' } = $release;
$props{ 'AppVerWithOutV' } =~ s/v//g;

my $BASE = evalString( \%props, '${arm.dat.path}/${AppNameLC}/${AppVerWithV}' );
print( "BASE=$BASE\n" );


my $xp_apx = XML::XPath->new( filename => $apx_file );
my $xp_epx = XML::XPath->new( filename => $epx_file );

my $ns2 = $xp->find( '/L1_AppDefinition/L2_AppEnvList/AppEnv' );
foreach my $node2 ( $ns2->get_nodelist )
{
    my $rte = $node2->getAttribute( 'name' );
    my $thread = $node2->getAttribute( 'thread_id' );
    my $build = "" . $node2->getAttribute( 'build' );

    print( "Processing $rte - $thread\n" );

    $props{ 'ThxNameUC' } = uc( $thread );
    $props{ 'ThxNameLC' } = lc( $thread );

    $props{ 'RteNameUC' } = uc( $rte );
    $props{ 'RteNameLC' } = lc( $rte );

    print( "\tProcessing header entries\n" );

    my @paths;
    my $ns3 = $xp_apx->find( '/application-package-model/stageDirs/mkdir' );
    foreach my $node3 ( $ns3->get_nodelist )
    {
        my $path = $node3->getAttribute( 'path' );
        my $evalpath = evalString( \%props, $path );

        if ( -e $evalpath )
        {
            print( "\t\tAlready exists: $evalpath\n" );
        }
        else
        {
            if ( "$build" eq "N" and $evalpath =~ /APPS/ )
            {
                # skipping
            }
            else
            {
                print( "\t\tCreating $evalpath\n" );
                if ( !$test )
                {
                    mkpath( $evalpath ) or warn( "Could not create $evalpath" );
                }
            }
        }
    }
    $ns3 = $xp_apx->find( '/application-package-model/stageDirs/link' );
    foreach my $node3 ( $ns3->get_nodelist )
    {
        my $src = $node3->getAttribute( 'src' );
        my $dst = $node3->getAttribute( 'dst' );
        my $evalsrc = evalString( \%props, $src );
        my $evaldst = evalString( \%props, $dst );

        if ( -e $evalsrc )
        {
            print( "\t\tAlready exists: $evalsrc \n" );
        }
        else
        {
            print( "\t\tLinking $evalsrc to $evaldst\n" );
            if ( !$test )
            {
                symlink( $evaldst, $evalsrc );
            }
        }
    }
    $ns3 = $xp_apx->find( '/application-package-model/stageDirs/exec' );
    foreach my $node3 ( $ns3->get_nodelist )
    {
        my $arg = $node3->getAttribute( 'arg' );
        my $evalarg = evalString( \%props, $arg );

        print( "\t\tExecuting $evalarg\n" );
        if ( !$test )
        {
            system( $evalarg );
        }
    }

    if ( "$build" eq "Y" )
    {
        my %pkgs;
        my $ns4 = $xp_epx->find( "/env_process_definition/pkg_group[\@name='stage']/pkg_grp_action[\@name='createdeploy']/pkg_action[\@name='createdeploy']" );
        foreach my $node4 ( $ns4->get_nodelist )
        {
            my $pkg = $node4->getAttribute( 'pkg_name' );
            $pkgs{ $pkg } = 1;
        }

        for my $pkg ( sort keys %pkgs )
        {
            print( "\tProcessing $pkg package entries\n" );

            my $ns5 = $xp_apx->find( "/application-package-model/application-package[\@id='$pkg']/stageDirs/mkdir" );
            foreach my $node5 ( $ns5->get_nodelist )
            {
                my $path = $node5->getAttribute( 'path' );
                my $evalpath = evalString( \%props, $path );
                if ( -e $evalpath )
                {
                    print( "\t\tAlready exists: $evalpath\n" );
                }
                else
                {
                    print( "\t\tCreating $evalpath\n" );
                    if ( !$test )
                    {
                        mkpath( $evalpath ) or warn( "Could not create $evalpath" );
                    }
                }
            }
            $ns5 = $xp_apx->find( "/application-package-model/application-package[\@id='$pkg']/stageDirs/link" );
            foreach my $node5 ( $ns5->get_nodelist )
            {
                my $src = $node5->getAttribute( 'src' );
                my $dst = $node5->getAttribute( 'dst' );
                my $evalsrc = evalString( \%props, $src );
                my $evaldst = evalString( \%props, $dst );

                if ( -e $evalsrc )
                {
                    print( "\t\tAlready exists: $evalsrc \n" );
                }
                else
                {
                    print( "\t\tLinking $evalsrc to $evaldst\n" );
                    if ( !$test )
                    {
                        symlink( $evaldst, $evalsrc ) or warn( "Could not link $evalsrc to $evaldst" );
                    }
                }
            }
            $ns5 = $xp_apx->find( "/application-package-model/application-package[\@id='$pkg']/stageDirs/exec" );
            foreach my $node5 ( $ns5->get_nodelist )
            {
                my $arg = $node5->getAttribute( 'arg' );
                my $evalarg = evalString( \%props, $arg );

                print( "\t\tExecuting $evalarg\n" );
                if ( !$test )
                {
                    system( $evalarg );
                }
            }
        }
    }
}

print( "Fixing permissions\n" );
#system( "chmod -R g+sw $BASE" );
system( "find $BASE -type d -exec chmod g+sw {} \\;" );

