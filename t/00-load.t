#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'AnyEvent::Redis2' ) || print "Bail out!
";
}

diag( "Testing AnyEvent::Redis2 $AnyEvent::Redis::VERSION, Perl $], $^X" );
