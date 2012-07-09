package test::LWP::UserAgent::Curl;
use strict;
BEGIN {
    my $file_name = __FILE__;
    $file_name =~ s{[^/]+$}{};
    $file_name ||= '.';
    $file_name .= '/../config/perl/libs.txt';
    open my $file, '<', $file_name or die "$0: $file_name: $!";
    unshift @INC, split /:/, scalar <$file>;
}
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
