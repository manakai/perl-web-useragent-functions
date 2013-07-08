use strict;
use warnings;
use LWP::UserAgent;
use Web::UserAgent::Functions;

my $ua = LWP::UserAgent->new;
$ua->mirror (q<http://www.hatena.com/> => 'hoge.txt');
