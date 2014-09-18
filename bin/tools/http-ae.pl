#!/usr/bin/perl
use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->parent->subdir('lib')->stringify;
use Getopt::Long;
use Pod::Usage;
use Encode;
use AnyEvent;

my $class = 'Web::UserAgent::Functions';
my $url;
my $is_test_server;
my %param;
my @cookie;
my @header_field;
my @basic_auth;
my @wsse_auth;
my @oauth;
my $oauth_method;
my $method = 'GET';
my $no_body;
my $timeout;
my $body;
my $max_redirect = 0;

GetOptions(
    '--class=s' => \$class,
    '--url=s' => \$url,
    '--follow-redirect' => sub { $max_redirect = 10 },
    '--is-test-server' => \$is_test_server,
    '--get' => sub { $method = 'GET' },
    '--post' => sub { $method = 'POST' },
    '--cookie=s' => sub { push @cookie, split /=/, (decode 'utf8', $_[1]), 2 },
    '--param=s' => sub {
        my ($n, $v) = split /=/, (decode 'utf8', $_[1]), 2;
        if ($param{$n}) {
            push @{$param{$n}}, $v;
        } else {
            $param{$n} = [$v];
        }
    },
    '--timeout=s' => \$timeout,
    '--header-field=s' => sub { push @header_field, split /:/, $_[1], 2 },
    '--basic-auth=s' => sub { @basic_auth = split /\s+/, $_[1], 2 },
    '--wsse-auth=s' => sub { @wsse_auth = split /\s+/, $_[1], 2 },
    '--oauth=s' => sub { @oauth = split /\s+/, $_[1] },
    '--oauth-method=s' => \$oauth_method,
    '--no-body' => \$no_body,
    '--body=s' => sub { $body = $_[1] },
    '--help' => sub { pod2usage(-verbose => 2) },
) or pod2usage(1);

pod2usage(1) unless $url and $class and $method;

eval qq{ require $class } or die $@;
$class->import(qw(http_get http_post http_post_data));

{
    no warnings 'once';
    $Web::UserAgent::Functions::DUMP_OUTPUT = \*STDOUT;
    if ($no_body) {
        $Web::UserAgent::Functions::DUMP = 1;
    } else {
        $Web::UserAgent::Functions::DUMP = 2;
    }
}

my $cv = AE::cv;
if ($method eq 'POST') {
    if (defined $body) {
        http_post_data(
            url => $url,
            timeout => $timeout,
            is_test_server => $is_test_server,
            max_redirect => $max_redirect,
            header_fields => {@header_field},
            (@basic_auth ? (basic_auth => \@basic_auth) : ()),
            (@wsse_auth ? (wsse_auth => \@wsse_auth) : ()),
            (@oauth ? (oauth => \@oauth, oauth_method => $oauth_method) : ()),
            params => \%param,
            cookies => {@cookie},
            content => $body,
            anyevent => 1,
            cb => sub {
                $cv->send;
            },
        );
    } else {
        http_post(
            url => $url,
            timeout => $timeout,
            is_test_server => $is_test_server,
            max_redirect => $max_redirect,
            header_fields => {@header_field},
            (@basic_auth ? (basic_auth => \@basic_auth) : ()),
            (@wsse_auth ? (wsse_auth => \@wsse_auth) : ()),
            (@oauth ? (oauth => \@oauth, oauth_method => $oauth_method) : ()),
            params => \%param,
            cookies => {@cookie},
            anyevent => 1,
            cb => sub {
                $cv->send;
            },
        );
    }
} else {
    http_get(
        url => $url,
        timeout => $timeout,
        is_test_server => $is_test_server,
        max_redirect => $max_redirect,
        header_fields => {@header_field},
        (@basic_auth ? (basic_auth => \@basic_auth) : ()),
        (@wsse_auth ? (wsse_auth => \@wsse_auth) : ()),
        (@oauth ? (oauth => \@oauth, oauth_method => $oauth_method) : ()),
        params => \%param,
        cookies => {@cookie},
        anyevent => 1,
        cb => sub {
            $cv->send;
        },
    );
}
$cv->recv;

__END__

=head1 NAME

http.pl - Simple HTTP client

=head1 SYNOPSIS

  $ perl http.pl --url=http://www.w3.org/ [OPTIONS]

=head1 OPTIONS

=over 4

=item --basic-auth="NAME PASS"

Enables the HTTP basic authorization with the specified user name and
password.

=item --body=STRING

Specify the response body.  This option is ignored unless the
C<--post> option is also specified.

=item --class=PERL::PACKAGE::NAME

The fully-qualified name of the Perl package which contains
L<Web::UserAgent::Functions> functionality.  The default value is
C<Web::UserAgent::Functions>.  This option can be used to invoke
customized version of the module.

=item --cookie=NAME=VALUE

Specify the name-value pairs included in the HTTP Cookie.  This option
can be specified multiple times.

The value of the option must be the name-value pair separated by a
C<=> character.  Both name and value must be encoded in UTF-8.
Percent-encode is performed by the script automatically if necessary.
If you don't want name and values to be encoded, or if you want to
control order of name-value pairs, or if you want to use same name
multiple times, please specify the entire C<Cookie:> header field
using the C<--header-field> option.

=item --follow-redirect

If specified, follow HTTP redirects.  Otherwise it does not follow any
redirect and show the redirect response.

=item --header-field=NAME:BODY

Specify the name-value pairs included in the HTTP request.  This
option can be specified multiple times.

The value of the option must be the name-value pair separated by a
C<:> character.  Both name and value must be encoded in US-ASCII.

=item --get

Set the HTTP request method to C<GET>.  This option is meaningless as
the default method is C<GET>.

=item --help

Show help message and exit.

=item --is-test-server

A boolean hook for customized classes.

=item --no-body

Disable printing of request-body and response-body.

=item --oauth="CONSUMER_TOKEN CONSUMER_SECRET ACCESS_TOKEN ACCESS_SECRET"

Enable OAuth 1.0a support, with specified consumer- and access- tokens
and secrets.  The value of this option must contain four (4) values
separated by spaces.

=item --param=NAME=VALUE

Specify the name-value pairs included in the HTTP request.  This
option can be specified multiple times.

The value of the option must be the name-value pair separated by a
C<=> character.  Both name and value must be encoded in UTF-8.
Percent-encode is performed by the script automatically if necessary.

The specified parameters are used as query parameter in C<GET> request
or as part of C<application/x-www-form-urlencoded> POST body in
C<POST> request and are signed if the OAuth support is enabled.

=item --post

Set the HTTP request method to C<POST>.

=item --url=HTTP_URL (required)

The URL to retrieve.  This option is required.  It must be an absolute
URL.

=item --wsse-auth="NAME PASS"

Enables the WSSE authorization with the specified user name and
password.

=back

=head1 SEE ALSO

L<Web::UserAgent::Functions>.

=head1 AUTHOR

Wakaba <wakabatan@hatena.ne.jp>.

=head1 LICENSE

Copyright 2011-2013 Hatena <http://www.hatena.ne.jp/>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

=cut
