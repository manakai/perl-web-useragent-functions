package Web::UserAgent::Functions;
use strict;
use warnings;
our $VERSION = '8.0';
use Path::Class;
use Encode;
use Exporter::Lite;

our @EXPORT = qw(http_get http_post http_post_data);

our $DEBUG ||= $ENV{WEBUA_DEBUG};

our $DUMP ||= $DEBUG;
our $DUMP_OUTPUT ||= \*STDERR;
our $ENABLE_CURL;

our $SOCKSIFYING;

if ($ENABLE_CURL) {
    require LWP::UserAgent;
    require LWP::UserAgent::Curl;
    *LWP::UserAgent::simple_request = \*LWP::UserAgent::Curl::simple_request;
}

sub enable_socksify_lwp () {
    $SOCKSIFYING = 1;
    require LWP::UserAgent;
    require LWP::UserAgent::Curl;
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
    my $http_method = $args{override_method} || 'GET';

    if (not defined $args{url}) {
      $args{url} = ($args{url_scheme} || 'http') . '://' . $args{host} . $args{pathquery};
    }

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
            method => $http_method,
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

    return _http(%args, method => $http_method);
}

my @boundary_alphabet = ('a'..'z', '0'..'9');

sub mime_param_value ($) {
    my $v = $_[0];
    $v =~ s/([^0-9A-Za-z_.-])/\\$1/g;
    return $v;
}

sub http_post (%) {
    my %args = @_;
    my $http_method = $args{override_method} || 'POST';

    if (not defined $args{url}) {
      $args{url} = ($args{url_scheme} || 'http') . '://' . $args{host} . $args{pathquery};
    }

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
            my $query = join '&', grep { /^oauth_/ } split /&/, $consumer->gen_auth_query($http_method, $args{url}, $access_token, $params);
            $args{url} .= '?' . $query;
            $content = serialize_form_urlencoded $args{params};
        } else {
            my $oauth_req = $consumer->gen_oauth_request(
                method => $http_method,
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
    return _http(content => $content, %args, method => $http_method);
}

sub http_post_data (%) {
    my %args = @_;
    my $http_method = $args{override_method} || 'POST';

    if (not defined $args{url}) {
      $args{url} = ($args{url_scheme} || 'http') . '://' . $args{host} . $args{pathquery};
    }

    if ($args{oauth}) {
        require OAuth::Lite::Consumer;
        require OAuth::Lite::Token;
        require OAuth::Lite::AuthMethod;
        
        my $oauth_method = $args{oauth_method} || 'authorization';
        my $use_query;
        if ($oauth_method eq 'query') {
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
            my $query = join '&', grep { /^oauth_/ } split /&/, $consumer->gen_auth_query($http_method, $args{url}, $access_token, $params);
            $args{url} .= '?' . $query;
            my $q = serialize_form_urlencoded $args{params};
            $args{url} .= '&' . $q if defined $q and length $q;
        } else {
            my $oauth_req = $consumer->gen_oauth_request(
                method => $http_method,
                url => $args{url},
                token => $access_token,
                params => $params,
            );
            my $authorization = $oauth_req->header('Authorization');
            if ($authorization) {
                $args{header_fields}->{Authorization} = $authorization;
            }
        }
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

    $args{header_fields}->{'Content-Type'} = $args{content_type}
        if defined $args{content_type};

    return _http(%args, method => $http_method);
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

    my %lwp_args = (parse_head => 0);
    $lwp_args{timeout} = $args{timeout} || $Timeout || 5;
    $lwp_args{max_redirect} = defined $args{max_redirect}
        ? $args{max_redirect} : $MaxRedirect;
    $lwp_args{max_size} = $args{max_size} || $MaxSize
        if defined $args{max_size} || defined $MaxSize;
    $lwp_args{protocols_allowed} = $AcceptSchemes;
    
    # If you don't need percent-encode, use |header_fields| instead.
    $args{header_fields}->{Cookie} ||= join '; ', map { (percent_encode_c $_->[0]) . '=' . percent_encode_c $_->[1] } grep { defined $_->[1] } map { [$_ => $args{cookies}->{$_}] } sort { $a cmp $b } keys %{$args{cookies}} if $args{cookies};

    if ($args{basic_auth}) {
        require MIME::Base64;
        my $auth = MIME::Base64::encode_base64(encode 'utf-8', ($args{basic_auth}->[0] . ':' . $args{basic_auth}->[1]), '');
        $auth =~ s/\s+//g;
        $args{header_fields}->{'Authorization'} = 'Basic ' . $auth;
        $args{header_fields}->{'Authorization'} =~ s/[\x0D\x0A]/ /g;
    }

    if ($args{wsse_auth}) {
        # <http://suika.suikawiki.org/~wakaba/wiki/sw/n/WSSE>

        require MIME::Base64;
        require Digest::SHA1;
        my $user = $args{wsse_auth}->[0];
        my $pass = $args{wsse_auth}->[1];

        my ($s, $m, $h, $d, $M, $y) = gmtime;
        my $now = sprintf '%04d-%02d-%02dT%02d:%02d:%02dZ',
            $y+1900, $M+1, $d, $h, $m, $s;

        my $nonce = Digest::SHA1::sha1(time() . {} . rand() . $$);
        my $nonce_b64 = MIME::Base64::encode_base64($nonce, '');
        my $digest = MIME::Base64::encode_base64(
            Digest::SHA1::sha1($nonce . $now . $pass), '',
        );
        
        $user =~ s/(["\\])/\\$1/g;
        $args{header_fields}->{Authorization} = 'WSSE profile="UsernameToken"';
        $args{header_fields}->{'X-WSSE'} = sprintf 'UsernameToken Username="%s", PasswordDigest="%s", Nonce="%s", Created="%s"',
            $user, $digest, $nonce_b64, $now;
        $args{header_fields}->{'X-WSSE'} =~ s/[\x0D\x0A]/ /g;
    }

    my $has_header = {};
    for (keys %{$args{header_fields} or {}}) {
        my $name = $_;
        $name =~ tr/A-Z/a-z/; ## ASCII case-insensitive.
        $has_header->{$name} = 1;
    }

    if (defined $lwp_args{max_redirect} and $lwp_args{max_redirect} > 0) {
        for (qw(
            cookie authorization x-wsse x-hatena-star-key
        )) {
            if ($has_header->{$_}) {
                $lwp_args{max_redirect} = 0;
            }
        }
    }

    my $use_proxy;
    if ($Proxy and not $args{no_proxy} and
        ($UseProxyIfCookie or not $has_header->{cookie})) {
        $use_proxy = 1;
    }

    require HTTP::Request;
    my $req = HTTP::Request->new($args{method} => $args{url});
    while (my ($n, $v) = each %{$args{header_fields} or {}}) {
        if (ref $v eq 'ARRAY') {
            $req->push_header($n => $_) for @$v;
        } else {
            $req->push_header($n => $v);
        }
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
        
        if ($DUMP and $res) {
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
        
        if (not $res) { # dry
            #
        } elsif ($res->is_success) {
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

    if ($args{dry}) {
        $done->(undef);
        return ($req, undef);
    } elsif ($args{anyevent}) {
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

        my %ae_args;
        if ($use_proxy) {
            if ($Proxy =~ m{^[Hh][Tt][Tt][Pp]://(.+)\:([0-9]+)/?$}) {
                $ae_args{proxy} = [$1, $2];
            } elsif ($Proxy =~ m{^(.+):([0-9]+)$}) {
                $ae_args{proxy} = [$1, $2];
            }
        }
        
        my $timer = AE::timer($lwp_args{timeout}, 0, sub {
            my $res = HTTP::Response->new(598, 'Timeout', [], '');
            $res->protocol('HTTP/?.?');
            $res->request($req);
            $res->content(sprintf 'AE::HTTP timeout (%d)', $lwp_args{timeout});
            $done->($res) if $done;
            undef $done;
        }) if $lwp_args{timeout};
        my @req_args = (
            $req->method,
            $args{url},
            socks => $socks_url,
            (defined $lwp_args{max_redirect} ? (recurse => $lwp_args{max_redirect}) : ()),
            %ae_args,
            body => $req->content,
            headers => {
                map { s/[\x0D\x0A]/ /g; $_ }
                map { ( $_ => $req->header($_) ) } $req->header_field_names
            },
        );
        my $process_res = sub {
            my ($body, $headers) = @_;
            my $code = delete $headers->{Status};
            my $msg = delete $headers->{Reason};
            my $http_version = 'HTTP/' .
                (delete $headers->{HTTPVersion} || '?.?');
            my $res = HTTP::Response->new(
                $code,
                $msg,
                [map { $_ => $headers->{$_} } grep { not /[A-Z]/ } keys %$headers],
                $body,
            );
            $res->protocol($http_version);
            $res->request($req);
            $done->($res) if $done;
            undef $done;
            undef $timer;
        };
        $aeclass->can('http_request')->(
            @req_args,
            sub {
                my ($body, $headers) = @_;
                if ($headers->{Status} == 599 and
                    $headers->{Reason} eq 'Too many redirections' and
                    defined $lwp_args{max_redirect} and
                    $lwp_args{max_redirect} == 0) {
                    ## AnyEvent 2.15 fails to retry the request if the
                    ## keep-alived connection has just closed and
                    ## |recurse| == 0.
                    $aeclass->can('http_request')->(
                        @req_args,
                        keepalive => 0,
                        $process_res,
                    );
                } else {
                    $process_res->(@_);
                }
            },
        );
        return ($req, undef);
    } else {
        my $class = 'LWP::UserAgent';
        if ($SOCKSIFYING) {
            $class .= '::Curl';
        }
        eval qq{ require $class } or die $@;
        my $ua = $class->new(%lwp_args);
        if ($use_proxy) {
            $ua->proxy(http => $Proxy);
            # LWP::UserAgent does not support https: proxy
        }

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
