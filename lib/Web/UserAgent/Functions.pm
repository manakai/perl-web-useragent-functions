package Web::UserAgent::Functions;
use strict;
use warnings;
our $VERSION = '3.0';
use Path::Class;
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

sub percent_encode_c ($) {
    my $s = Encode::encode ('utf-8', ''.$_[0]);
  $s =~ s/([^0-9A-Za-z._~-])/sprintf '%%%02X', ord $1/ge;
  return $s;
} # percent_encode_c

# Warning! $args{params} values MUST be utf8 character strings, not
# byte strings.
sub serialize_form_urlencoded ($) {
    my $params = shift || {};
    return join '&', map {
        my $n = percent_encode_c $_;
        my $vs = $params->{$_};
        if (defined $vs and ref $vs eq 'ARRAY') {
            (map { $n . '=' . percent_encode_c $_ } grep { defined $_ } @$vs);
        } elsif (defined $vs) {
            ($n . '=' . percent_encode_c $vs);
        } else {
            ();
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
        my $params = {map { ref $_ eq 'ARRAY' ? [map { encode 'utf-8', $_ } @$_] : encode 'utf-8', $_ } %{$args{params} or {}}};
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

my @boundary_alphabet = ('a'..'z', '0'..'9');

sub mime_param_value ($) {
    my $v = $_[0];
    $v =~ s/([^0-9A-Za-z_.-])/\\$1/g;
    return $v;
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
        my $params = {map { ref $_ eq 'ARRAY' ? [map { encode 'utf-8', $_ } @$_] : encode 'utf-8', $_ } %{$args{params} or {}}};
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
        if (keys %{$args{files} or {}}) {
            my $boundary = '';
            $boundary .= $boundary_alphabet[rand @boundary_alphabet] for 1..50;
            $args{header_fields}->{'Content-Type'} = 'multipart/form-data; boundary=' . $boundary;
            
            my @part;

            for my $key (keys %{$args{params} or {}}) {
                for my $value (ref $args{params}->{$key} eq 'ARRAY'
                                     ? @{$args{params}->{$key}}
                                     : ($args{params}->{$key})) {
                    push @part, 
                        "Content-Type: text/plain; charset=utf-8\x0D\x0A" .
                        'Content-Disposition: form-data; name="'.mime_param_value($key).'"' . "\x0D\x0A" .
                        "\x0D\x0A" . 
                        (encode 'utf-8', $value);
                }
            }

            local $/ = undef;
            for my $key (keys %{$args{files} or {}}) {
                for my $value (ref $args{files}->{$key} eq 'ARRAY'
                                     ? @{$args{files}->{$key}}
                                     : ($args{files}->{$key})) {
                    my $mime = $value->{mime_type} || 'application/octet-stream';
                    $mime =~ s/([\x00-\x1F;])//g;
                    my $file_name = $value->{mime_filename};
                    $file_name = $key unless defined $file_name;
                    $file_name =~ s/([\x00-\x1F])//g;
                    push @part, 
                        "Content-Type: $mime\x0D\x0A" .
                        'Content-Disposition: form-data; name="'.mime_param_value($key).'"; filename="'.mime_param_value($file_name).'"' . "\x0D\x0A" .
                        "\x0D\x0A" . 
                        ($value->{glob}
                             ? do { my $v = $value->{glob}; <$v> } :
                         $value->{file_name}
                             ? scalar file($value->{file_name})->slurp :
                         $value->{f}
                             ? scalar $value->{f}->slurp :
                         $value->{ref}
                             ? encode 'utf-8', ${$value->{ref}} :
                         ${$value->{byteref} or \''});
                }
            }

            $content = "--$boundary\x0D\x0A" .
                join "\x0D\x0A--$boundary\x0D\x0A", @part;
            $content .= "\x0D\x0A--$boundary--\x0D\x0A";
        } else {
            $content = serialize_form_urlencoded $args{params};
        }
    }
    $args{header_fields}->{'Content-Type'} ||= 'application/x-www-form-urlencoded';
    return _http(content => $content, %args, method => $args{override_method} || 'POST');
}

sub http_post_data (%) {
    my %args = @_;

    $args{header_fields}->{'Content-Type'} = $args{content_type}
        if defined $args{content_type};

    my $query = serialize_form_urlencoded $args{params};
    if (length $query) {
        if ($args{url} =~ /\?/) {
            $args{url} .= '&' . $query;
        } else {
            $args{url} .= '?' . $query;
        }
    }

    return _http(%args, method => $args{override_method} || 'POST');
}

our $Proxy;
our $UseProxyIfCookie;
our $Timeout;
our $RequestPostprocessor;
our $MaxRedirect;
our $SocksProxyURL;
our $MaxSize;
our $AcceptSchemes ||= [qw(http https)];
our $SeqID = int rand 1000000;

sub _http {
    my %args = @_;

    my $class = 'LWP::UserAgent';
    $class .= '::Curl' if $SOCKSIFYING;

    my %lwp_args = (parse_head => 0);
    $lwp_args{timeout} = $args{timeout} || $Timeout || 5;
    $lwp_args{max_redirect} = $args{max_redirect} || $MaxRedirect;
    $lwp_args{max_size} = $args{max_size} || $MaxSize
        if defined $args{max_size} || defined $MaxSize;
    $lwp_args{protocols_allowed} = $AcceptSchemes;
    
    my $ua = $class->new(%lwp_args);
    my $req = HTTP::Request->new($args{method} => $args{url});
    
    # If you don't need percent-encode, use |header_fields| instead.
    $args{header_fields}->{Cookie} ||= join '; ', map { (percent_encode_c $_->[0]) . '=' . percent_encode_c $_->[1] } grep { defined $_->[1] } map { [$_ => $args{cookies}->{$_}] } sort { $a cmp $b } keys %{$args{cookies}} if $args{cookies};

    if ($args{basic_auth}) {
        require MIME::Base64;
        my $auth = MIME::Base64::encode_base64(encode 'utf-8', ($args{basic_auth}->[0] . ':' . $args{basic_auth}->[1]));
        $auth =~ s/\s+//g;
        $args{header_fields}->{'Authorization'} ||= 'Basic ' . $auth;
        $args{header_fields}->{'Authorization'} =~ s/[\x0D\x0A]/ /g;
    }

    for (qw(
        Cookie cookie Authorization authorization X-WSSE x-wsse
        X-Hatena-Star-Key
    )) {
        if ($args{header_fields}->{$_}) {
            $lwp_args{max_redirect} = 0;
        }
    }

    if ($Proxy and not $args{no_proxy} and
        ($UseProxyIfCookie or 
         (not $args{header_fields}->{Cookie} and
          not $args{header_fields}->{cookie}))) {
        $ua->proxy(http => $Proxy);
    }

    while (my ($n, $v) = each %{$args{header_fields} or {}}) {
        $req->header($n => $v);
    }
    $req->content($args{content}) if defined $args{content};

    my $seq_id = $SeqID++;
    $RequestPostprocessor->($req, \%args) if $RequestPostprocessor;

    if ($DEBUG or $DUMP) {
        warn "<$args{url}>...\n" if $DEBUG;
        print $DUMP_OUTPUT "====== REQUEST($seq_id) ======\n";
        if ($args{anyevent} and $SocksProxyURL) {
            print $DUMP_OUTPUT "== PROXY $SocksProxyURL ==\n";
        } elsif (not $args{anyevent} and $SOCKSIFYING) {
            print $DUMP_OUTPUT "== SOCKSIFY ==\n";
        }
        if ($DUMP >= 2) {
            print $DUMP_OUTPUT "TIMEOUT: $lwp_args{timeout}\n";
            print $DUMP_OUTPUT $req->as_string;
            print $DUMP_OUTPUT "====== WEBUA_F($seq_id) ======\n";
        } else {
            print $DUMP_OUTPUT $req->method, ' ', $req->uri, ' ', ($req->protocol || ''), "\n";
            print $DUMP_OUTPUT $req->headers_as_string;
            print $DUMP_OUTPUT "====== WEBUA_F($seq_id) ======\n";
        }
    }

    my $done = sub {
        my $res = shift;
        
        if ($DUMP) {
            if ($DUMP >= 2) {
                print $DUMP_OUTPUT "====== RESPONSE($seq_id) =====\n";
                print $DUMP_OUTPUT $res->as_string;
                print $DUMP_OUTPUT "====== WEBUA_F($seq_id) ======\n";
            } else {
                print $DUMP_OUTPUT "====== RESPONSE($seq_id) =====\n";
                print $DUMP_OUTPUT $res->protocol, ' ', $res->status_line, "\n";
                print $DUMP_OUTPUT $res->headers_as_string;
                print $DUMP_OUTPUT "====== WEBUA_F($seq_id) ======\n";
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

        if ($args{cb}) {
            $args{cb}->($req, $res);
        }
    };
    
    if ($args{anyevent}) {
        require AnyEvent;
        require AnyEvent::HTTP;
        require HTTP::Response;
        my $aeclass = 'AnyEvent::HTTP';
        my $socks_url;
        if ($SocksProxyURL) {
            $aeclass .= '::Socks';
            require AnyEvent::HTTP::Socks;
            $socks_url = $SocksProxyURL;
        }
        
        my $timer = AE::timer($lwp_args{timeout}, 0, sub {
            my $res = HTTP::Response->new(598, 'Timeout', [], '');
            $res->protocol('HTTP/?.?');
            $res->request($req);
            $res->content(sprintf 'AE::HTTP timeout (%d)', $lwp_args{timeout});
            $done->($res) if $done;
            undef $done;
        }) if $lwp_args{timeout};
        $aeclass->can('http_request')->(
            $req->method,
            $args{url},
            socks => $socks_url,
            body => $req->content,
            headers => {
                map { s/[\x0D\x0A]/ /g; $_ }
                map { ( $_ => $req->header($_) ) } $req->header_field_names
            },
            sub {
                my ($body, $headers) = @_;
                my $code = delete $headers->{Status};
                my $msg = delete $headers->{Reason};
                my $http_version = 'HTTP/' .
                    (delete $headers->{HTTPVersion} || '?.?');
                my $res = HTTP::Response->new(
                    $code,
                    $msg,
                    [map { $_ => $headers->{$_} }
                     grep { not /[A-Z]/ } keys %$headers],
                    $body,
                );
                $res->protocol($http_version);
                $res->request($req);
                $done->($res) if $done;
                undef $done;
                undef $timer;
            },
        );
        return ($req, undef);
    } else {
        my $res;
        {
            local $@;
            $res = eval { $ua->request($req) };
            if ($@) {
                require HTTP::Response;
                $res = HTTP::Response->new(500, 'LWP Error');
                $res->content($@);
            }
        }
        $done->($res);
        return ($req, $res);
    }
}

1;
