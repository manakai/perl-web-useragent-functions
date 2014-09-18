use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->subdir('lib')->stringify;
use lib glob file(__FILE__)->dir->parent->subdir('modules', '*', 'lib')->stringify;
use lib glob file(__FILE__)->dir->parent->subdir('t_deps', 'modules', '*', 'lib')->stringify;
use Test::More;
use Web::UserAgent::Functions::Proxy;

is choose_socks_proxy_url ([], q<http://www.example.com/>), undef;
is choose_socks_proxy_url ([
  {target_hostname => 'www.example.com',
   hostname => 'socks1.test', port => 123},
], q<http://www.example.com/>), 'socks5://socks1.test:123';
is choose_socks_proxy_url ([
  {target_hostname => '*.example.com',
   hostname => 'socks2.test', port => 1234},
  {target_hostname => 'www.example.com',
   hostname => 'socks1.test', port => 123},
], q<http://www.example.com/>), 'socks5://socks2.test:1234';

done_testing;

=head1 LICENSE

Copyright 2014 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
