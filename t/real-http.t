use strict;
use warnings;
use Path::Class;
use lib glob file (__FILE__)->dir->parent->subdir
    ('t_deps/modules/*/lib');
use Test::X1;
use Test::More;
use Promise;
use Promised::Flow;
use Web::UserAgent::Functions qw(http_get);

for my $url (
  q<http://www.example.com>,
  q<http://www.yahoo.co.jp>,
  q<http://www.google.com>,
  q<http://hatenacorp.jp>,
) {
  test {
    my $c = shift;
    return promised_cleanup {
      done $c;
      undef $c;
    } Promise->new (sub {
      my ($ok, $ng) = @_;
      http_get
          url => $url,
          timeout => 60*3,
          cb => sub {
            my ($req, $res) = @_;
            $ok->($res);
          };
    })->then (sub {
      my $res = $_[0];
      test {
        ok $res->code == 200 ||
           $res->code == 301 ||
           $res->code == 302, $res->code;
      } $c;
    });
  } n => 1, name => [$url, 'LWP mode'];
}

run_tests;
