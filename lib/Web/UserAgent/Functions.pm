package Web::UserAgent::Functions;
use strict;
use warnings;
our $VERSION = '2.0';
use URL::PercentEncode;
use LWP::UserAgent;
use LWP::UserAgent::Curl;
use Encode;
use Exporter::Lite;

our @EXPORT = qw(http_get http_post http_post_data);

our $DEBUG ||= $ENV{WEBUA_DEBUG};

our $DUMP ||= $DEBUG;
our $DUMP_OUTPUT ||= \*STDERR;

our $SOCKSIFYING;

sub enable_socksify_lwp () {
    $SOCKSIFYING = 1;
    *LWP::UserAgent::simple_request = \*LWP::UserAgent::Curl::simple_request;
    print STDERR "Enabled ".__PACKAGE__." socksify support\n";
}

sub check_socksify () {
    if (
        ($ENV{LD_PRELOAD} || '') =~ /\blibdl\.so\b/ ||
        ($ENV{LD_PRELOAD} || '') =~ /\blibdsocks\.so\b/
    ) {
        enable_socksify_lwp;
    }
}

# Warning! $args{params} values MUST be utf8 character strings, not
# byte strings.

sub serialize_form_urlencoded ($) {
    my $params = shift || {};
    return join '&', map {
        my $n = percent_encode_c $_;
        my $vs = $params->{$_};
        if (ref $vs eq 'ARRAY') {
            (map { $n . '=' . percent_encode_c $_ } @$vs);
        } else {
            $n . '=' . percent_encode_c $vs;
        }
    } keys %$params;
}

sub http_get (%) {
    my %args = @_;

    if ($args{oauth}) {
        require OAuth::Lite::Consumer;
        require OAuth::Lite::Token;
        require OAuth::Lite::AuthMethod;
        
        my $oauth_method = $args{oauth_method} || 'authorization';
        if ($oauth_method eq 'query') {
            $oauth_method = OAuth::Lite::AuthMethod::URL_QUERY();
        } else {
            $oauth_method = OAuth::Lite::AuthMethod::AUTH_HEADER();
        }

        my $consumer = OAuth::Lite::Consumer->new(
            consumer_key => $args{oauth}->[0],
            consumer_secret => $args{oauth}->[1],
            auth_method => $oauth_method,
        );
        my $access_token = OAuth::Lite::Token->new(
            token => $args{oauth}->[2],
            secret => $args{oauth}->[3],
        );
        my $params = {map { ref $_ eq 'ARRAY' ? [map { encode 'utf8', $_ } @$_] : encode 'utf8', $_ } %{$args{params} or {}}};
        my $oauth_req = $consumer->gen_oauth_request(
            method => 'GET',
            url => $args{url},
            token => $access_token,
            params => $params,
        );
        my $authorization = $oauth_req->header('Authorization');
        if ($authorization) {
            $args{header_fields}->{Authorization} = $authorization;
        }
        $args{url} = $oauth_req->uri;
    } else {
        my $query = serialize_form_urlencoded $args{params};
        if (length $query) {
            if ($args{url} =~ /\?/) {
                $args{url} .= '&' . $query;
            } else {
                $args{url} .= '?' . $query;
            }
        }
    }

    return _http(%args, method => $args{override_method} || 'GET');
}

sub http_post (%) {
    my %args = @_;

    my $content;
    if ($args{oauth}) {
        require OAuth::Lite::Consumer;
        require OAuth::Lite::Token;
        require OAuth::Lite::AuthMethod;

        my $oauth_method = $args{oauth_method} || 'authorization';
        my $use_query;
        if ($oauth_method eq 'body') {
            $oauth_method = OAuth::Lite::AuthMethod::POST_BODY();
        } elsif ($oauth_method eq 'query') {
            $oauth_method = OAuth::Lite::AuthMethod::URL_QUERY();
            $use_query = 1;
        } else {
            $oauth_method = OAuth::Lite::AuthMethod::AUTH_HEADER();
        }
        
        my $consumer = OAuth::Lite::Consumer->new(
            consumer_key => $args{oauth}->[0],
            consumer_secret => $args{oauth}->[1],
            auth_method => $oauth_method,
        );
        my $access_token = OAuth::Lite::Token->new(
            token => $args{oauth}->[2],
            secret => $args{oauth}->[3],
        );
        my $params = {map { ref $_ eq 'ARRAY' ? [map { encode 'utf8', $_ } @$_] : encode 'utf8', $_ } %{$args{params} or {}}};
        if ($use_query) {
            my $query = join '&', grep { /^oauth_/ } split /&/, $consumer->gen_auth_query('POST', $args{url}, $access_token, $params);
            $args{url} .= '?' . $query;
            $content = serialize_form_urlencoded $args{params};
        } else {
            my $oauth_req = $consumer->gen_oauth_request(
                method => 'POST',
                url => $args{url},
                token => $access_token,
                params => $params,
            );
            my $authorization = $oauth_req->header('Authorization');
            if ($authorization) {
                $args{header_fields}->{Authorization} = $authorization;
            }
            my $oauth_content = $oauth_req->content;
            if (defined $oauth_content and length $oauth_content) {
                $content = $oauth_content;
            }
        }
    } else {
        $content = serialize_form_urlencoded $args{params};
    }
    $args{header_fields}->{'Content-Type'} ||= 'application/x-www-form-urlencoded';
    return _http(content => $content, %args, method => $args{override_method} || 'POST');
}

sub http_post_data (%) {
    my %args = @_;

    $args{header_fields}->{'Content-Type'} = $args{content_type}
        if defined $args{content_type};
    return _http(%args, method => $args{override_method} || 'POST');
}

our $Proxy;
our $Timeout;
our $RequestPostprocessor;

sub _http {
    my %args = @_;

    my $class = 'LWP::UserAgent';
    $class .= '::Curl' if $SOCKSIFYING;

    my %lwp_args = (parse_head => 0);
    $lwp_args{timeout} = $args{timeout} || $Timeout || 5;
    
    my $ua = $class->new(%lwp_args);
    $ua->proxy(http => $Proxy) if $Proxy;
    my $req = HTTP::Request->new($args{method} => $args{url});
    
    # If you don't need percent-encode, use |header_fields| instead.
    $args{header_fields}->{Cookie} ||= join '; ', map { (percent_encode_c $_->[0]) . '=' . percent_encode_c $_->[1] } grep { defined $_->[1] } map { [$_ => $args{cookies}->{$_}] } sort { $a cmp $b } keys %{$args{cookies}} if $args{cookies};

    if ($args{basic_auth}) {
        require MIME::Base64;
        $args{header_fields}->{'Authorization'} ||= 'Basic ' . MIME::Base64::encode_base64(encode 'utf-8', ($args{basic_auth}->[0] . ':' . $args{basic_auth}->[1]));
    }

    while (my ($n, $v) = each %{$args{header_fields} or {}}) {
        $req->header($n => $v);
    }
    $req->content($args{content}) if defined $args{content};

    $RequestPostprocessor->($req, \%args) if $RequestPostprocessor;

    if ($DEBUG or $DUMP) {
        warn "<$args{url}>...\n" if $DEBUG;
        if ($DUMP >= 2) {
            print $DUMP_OUTPUT "====== REQUEST ======\n";
            print $DUMP_OUTPUT $req->as_string;
            print $DUMP_OUTPUT "====== WEBUA_F ======\n";
        } else {
            print $DUMP_OUTPUT "====== REQUEST ======\n";
            print $DUMP_OUTPUT $req->method, ' ', $req->uri, ' ', ($req->protocol || ''), "\n";
            print $DUMP_OUTPUT $req->headers_as_string;
            print $DUMP_OUTPUT "====== WEBUA_F ======\n";
        }
    }
    
    my $res = $ua->request($req);

    if ($DUMP) {
        if ($DUMP >= 2) {
            print $DUMP_OUTPUT "====== RESPONSE =====\n";
            print $DUMP_OUTPUT $res->as_string;
            print $DUMP_OUTPUT "====== WEBUA_F ======\n";
        } else {
            print $DUMP_OUTPUT "====== RESPONSE =====\n";
            print $DUMP_OUTPUT $res->protocol, ' ', $res->status_line, "\n";
            print $DUMP_OUTPUT $res->headers_as_string;
            print $DUMP_OUTPUT "====== WEBUA_F ======\n";
        }
    }
    
    if ($res->is_success) {
        $args{onsuccess}->($req, $res) if $args{onsuccess};
    } else {
        ($args{onerror} || sub {
            warn sprintf "URL <%s>, status %s\n",
                map { s/\x0D\x0A?|\x0D/\n/g; $_ }
                    $args{url}, $res->status_line;
        })->($req, $res);
    }

    return ($req, $res);
}


1;
