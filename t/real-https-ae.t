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

for my $host (qw(
www.google.com
mail.google.com
github.com
gist.github.com
gist.githubusercontent.com
httpd.apache.org
soulsphere.org
whatwg.org
dom.spec.whatwg.org
www.facebook.com
helloworld.letsencrypt.org
www.hatena.ne.jp
hatena.g.hatena.ne.jp
roomhub.jp
opendata500.herokuapp.com
www.realtokyoestate.co.jp
www.amazon.co.jp
)) {
  my $url = qq<https://$host>;
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
          anyevent => 1,
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
  } n => 1, name => [$url, 'AEHTTP mode'];
}

run_tests;
