package test::LWP::UserAgent::Curl;
use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->subdir('lib')->stringify;
use base qw(Test::Class);
use Test::More;

sub _use : Test(1) {
    use_ok 'LWP::UserAgent::Curl';
}

__PACKAGE__->runtests;

1;
