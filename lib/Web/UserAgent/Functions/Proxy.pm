package Web::UserAgent::Functions::Proxy;
use strict;
use warnings;
our $VERSION = '1.0';
use Exporter::Lite;

our @EXPORT = qw(choose_socks_proxy_url);

our $DEBUG;

sub choose_socks_proxy_url ($$) {
  my ($conf, $url) = @_;
  my $socks_url;
  for (@{$conf or []}) {
    my $pattern = join '\.',
        map { $_ eq '*' ? '.+' : quotemeta }
        split /\./,
        defined $_->{target_hostname} ? $_->{target_hostname} : '*';
    if ($url =~ m{^https?://$pattern[:/]}i) {
      warn "<$url> matches /$_->{target_hostname}/ ($pattern)\n" if $DEBUG;
      $socks_url = 'socks5://' .
          (defined $_->{hostname} ? $_->{hostname} : 'localhost') . 
          ':' . ($_->{port} || 0);
      last;
    } else {
      warn "<$url> does not match /$pattern/ ($_->{target_hostname})\n" if $DEBUG;
    }
  }
  return $socks_url;
} # choose_socks_proxy_url

1;

=head1 LICENSE

Copyright 2013-2014 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
