use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->subdir('lib')->stringify;
use lib glob file(__FILE__)->dir->parent->subdir('modules', '*', 'lib')->stringify;
use lib glob file(__FILE__)->dir->parent->subdir('t_deps', 'modules', '*', 'lib')->stringify;
use base qw(Test::Class);
use Test::More;
use Web::UserAgent::Functions::OAuth;

is Web::UserAgent::Functions::OAuth::http_oauth1_get_auth_url
    (url => q<http://hoge/fuga?a#b>, temp_token => q<a+?b=>),
    q<http://hoge/fuga?a&oauth_token=a%2B%3Fb%3D>;

done_testing;
