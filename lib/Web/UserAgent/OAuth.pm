package Web::UserAgent::OAuth;
use strict;
use warnings;
our $VERSION = '2.0';
require utf8;
use Carp qw(croak);
use Encode;
use Digest::SHA;
use MIME::Base64;

sub new {
    my $class = shift;
    return bless {@_}, $class;
}

sub reset {
  my $self = $_[0];
  delete $self->{$_} for qw(
    request_url http_authorization form_body
    oauth_params
  );
}

sub oauth_consumer_key {
    if (@_ > 1) {
        $_[0]->{oauth_consumer_key} = $_[1];
    }
    return $_[0]->{oauth_consumer_key};
}

sub client_shared_secret {
    if (@_ > 1) {
        $_[0]->{client_shared_secret} = $_[1];
    }
    return $_[0]->{client_shared_secret};
}

sub oauth_callback {
    if (@_ > 1) {
        $_[0]->{oauth_callback} = $_[1];
    }
    return $_[0]->{oauth_callback};
}

sub oauth_token {
    if (@_ > 1) {
        $_[0]->{oauth_token} = $_[1];
    }
    return $_[0]->{oauth_token};
}

sub token_shared_secret {
    if (@_ > 1) {
        $_[0]->{token_shared_secret} = $_[1];
    }
    return $_[0]->{token_shared_secret};
}

sub oauth_verifier {
    if (@_ > 1) {
        $_[0]->{oauth_verifier} = $_[1];
    }
    return $_[0]->{oauth_verifier};
}

sub oauth_signature_method {
    return 'HMAC-SHA1';
}

sub oauth_timestamp {
    if (@_ > 1) {
        $_[0]->{oauth_timestamp} = $_[1];
    }
    return $_[0]->{oauth_timestamp};
}

sub oauth_nonce {
    if (@_ > 1) {
        $_[0]->{oauth_nonce} = $_[1];
    }
    return $_[0]->{oauth_nonce};
}

sub oauth_version {
    return '1.0';
}

sub oauth_signature {
    return $_[0]->{oauth_signature};
}

sub request_method {
    if (@_ > 1) {
        $_[0]->{request_method} = $_[1];
    }
    return $_[0]->{request_method};
}

sub url_scheme {
    if (@_ > 1) {
        $_[0]->{url_scheme} = $_[1];
    }
    return $_[0]->{url_scheme};
}

sub request_url {
    if (@_ > 1) {
        $_[0]->{request_url} = $_[1];
    }
    return $_[0]->{request_url};
}

sub http_authorization {
    if (@_ > 1) {
        $_[0]->{http_authorization} = $_[1];
    }
    return $_[0]->{http_authorization};
}

sub http_host {
    if (@_ > 1) {
        $_[0]->{http_host} = $_[1];
    }
    return $_[0]->{http_host};
}

sub form_body {
    if (@_ > 1) {
        $_[0]->{form_body} = $_[1];
    }
    return $_[0]->{form_body};
}

sub oauth_params {
    return $_[0]->{oauth_params};
}

sub signature_base_string {
    return $_[0]->{signature_base_string};
}

my @Alphabet = ('A'..'Z', 'a'..'z', '0'..'9');
sub set_timestamp_and_nonce {
    $_[0]->oauth_timestamp(time);
    my $nonce = '';
    $nonce .= $Alphabet[rand @Alphabet] for 0..30+rand 14;
    $_[0]->oauth_nonce($nonce);
}

# 3.6.
sub percent_encode ($) {
    # 1.
    my $s = utf8::is_utf8($_[0]) ? Encode::encode('utf-8', ''.$_[0]) : ''.$_[0];
    
    # 2.
    $s =~ s/([^0-9A-Za-z._~-])/sprintf '%%%02X', ord $1/ge;

    return $s;
}

# 3.4.1.2.
sub create_base_string_url {
    my $self = $_[0];

    my $path = $self->request_url;
    croak '|request_url| is not set' unless defined $path;
    $path =~ s/\#.*//s;
    $path =~ s/\?.*//s;
    $path =~ s{^[^:/]+:}{};
    $path =~ s{^//+[^/]*}{};
    
    my $scheme = $self->url_scheme;
    $scheme = 'http' unless defined $scheme;
    $scheme =~ tr/A-Z/a-z/;

    my $host = $self->http_host;
    croak '|http_host| is not set' unless defined $host;
    $host =~ tr/A-Z/a-z/;

    if ($scheme eq 'http') {
        $host =~ s/:0*80\z//;
    } elsif ($scheme eq 'https') {
        $host =~ s/:0*443\z//;
    }

    return $scheme . '://' . $host . $path;
}

sub create_oauth_params {
    my $self = $_[0];
    my @param;
    for my $key (qw(oauth_consumer_key oauth_signature_method
                    oauth_timestamp oauth_nonce oauth_version)) {
        my $value = $self->$key;
        croak "|$key| is not set" unless defined $value;
        push @param, [$key => $value];
    }
    for ($self->oauth_callback) { push @param, [oauth_callback => $_] if defined $_ }
    for ($self->oauth_token) { push @param, [oauth_token => $_] if defined $_ }
    for ($self->oauth_verifier) { push @param, [oauth_verifier => $_] if defined $_ }
    return $self->{oauth_params} = \@param;
}

sub create_request_params {
    my $self = $_[0];

    # 3.4.1.3.1.
    my @param;

    my $url = $self->request_url;
    croak '|request_url| is not set' unless defined $url;
    $url =~ s/\#.*//s;
    if ($url =~ s/\?(.*)//s) {
        push @param, map { [map { s/\+/ /; s/%([0-9A-Fa-f]{2})/pack 'C', hex $1/ge; $_ } split /=/, $_, 2] } split /&/, $1, -1;
    }

    my $header = $self->http_authorization;
    if (defined $header and $header =~ s/^[Oo][Aa][Uu][Tt][Hh][\x09\x0A\x0D\x20]+//) {
        while ($header =~ s/^([^=\x09\x0A\x0D\x20]+)="([^\\"]*)"(?:,[\x09\x0A\x0D\x20]*)?//) {
            my ($n, $v) = ($1, $2);
            next if $n =~ /\A[Rr][Ee][Aa][Ll][Mm]\z/;
            $n =~ s/%([0-9A-Fa-f]{2})/pack 'C', hex $1/ge;
            $v =~ s/%([0-9A-Fa-f]{2})/pack 'C', hex $1/ge;
            push @param, [$n => $v];
        }
    }

    my $body = $self->form_body;
    if (defined $body) {
        push @param, map { [map { s/\+/ /; s/%([0-9A-Fa-f]{2})/pack 'C', hex $1/ge; $_ } split /=/, $_, 2] } split /&/, $body, -1;
    }

    my $oauth_params = $self->oauth_params;
    croak '|oauth_params| is not set' unless defined $oauth_params;
    push @param, @$oauth_params;

    # 3.4.1.3.2.

    # 1.
    for (@param) {
        $_ = [percent_encode $_->[0],
              defined $_->[1] ? percent_encode $_->[1] : ''];
    }

    # 4.
    return join '&',

        # 3.
        map { $_->[0] . '=' . $_->[1] }

        # 2.
        sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @param;
}

# 3.4.1.1.
sub create_signature_base_string {
    my $self = $_[0];
    my $string = '';

    # 1.
    my $method = $self->request_method;
    croak "|request_method| is not set" unless defined $method;
    $method =~ tr/a-z/A-Z/;
    $string .= percent_encode $method;

    # 2.
    $string .= '&';

    # 3.
    $string .= percent_encode $self->create_base_string_url;

    # 4.
    $string .= '&';

    # 5.
    $string .= percent_encode $self->create_request_params;

    return $self->{signature_base_string} = $string;
}

sub create_hmac_sha1_key {
    my $self = $_[0];
    
    # 1.
    my $client_secret = $self->client_shared_secret;
    croak '|client_shared_secret| is not set' unless defined $client_secret;
    my $s = percent_encode $client_secret;

    # 2.
    $s .= '&';

    # 3.
    my $token_secret = $self->token_shared_secret;
    croak '|token_shared_secret| is not set' unless defined $token_secret;
    $s .= percent_encode $token_secret;

    return $s;
}

sub create_signature {
    my $self = $_[0];
    return $self->create_hmac_sha1_signature;
}

# 3.4.2.
sub create_hmac_sha1_signature {
    my ($self) = @_;

    my $base = $self->signature_base_string;
    croak '|signature_base_string| is not set' unless defined $base;

    my $key = $self->create_hmac_sha1_key;

    return $self->{oauth_signature} = MIME::Base64::encode_base64(Digest::SHA::hmac_sha1($base, $key), '');
}

# 3.5.
sub append_oauth_params {
    my ($self, $container) = @_;

    my $oauth_params = $self->oauth_params;
    croak '|oauth_params| is not set' unless defined $oauth_params;

    my $oauth_signature = $self->oauth_signature;
    croak '|oauth_signature| is not set' unless defined $oauth_signature;

    if ($container eq 'authorization') {
        my $header = $self->http_authorization;
        $header = 'OAuth ' if not defined $header;
        $header .= ($header =~ /=/ ? ', ' : '')
            . join ', ',
                ($header =~ /\brealm="/ ? () : ('realm=""')),
                map { (percent_encode $_->[0]) . '="' . (percent_encode $_->[1]) . '"' }
                    @$oauth_params,
                    [oauth_signature => $oauth_signature];
        $self->http_authorization($header);
    } elsif ($container eq 'query') {
        my $url = $self->request_url;
        my $fragment = '';
        if ($url =~ s/(\#.*)//s) {
            $fragment = $1;
        }
        $url .= '?' unless $url =~ /\?/;
        $url = join '&',
            $url,
            map { (percent_encode $_->[0]) . '=' . (percent_encode $_->[1]) }
                @$oauth_params,
                [oauth_signature => $oauth_signature];
        $url .= $fragment;
        $self->request_url($url);
    } elsif ($container eq 'body') {
        my $body = $self->form_body;
        $body = join '&',
            (defined $body && length $body ? $body : ()),
            map { (percent_encode $_->[0]) . '=' . (percent_encode $_->[1]) }
                @$oauth_params,
                [oauth_signature => $oauth_signature];
        $self->form_body($body);
    } else {
        croak "Unknown parameter container |$container|";
    }
}

# 3.
sub authenticate_by_oauth1 {
    my ($self, %args) = @_;
    my $container = $args{container} || 'authorization';

    $self->set_timestamp_and_nonce;
    $self->create_oauth_params;
    $self->create_signature_base_string;
    $self->create_signature;
    $self->append_oauth_params($container);
}

1;

__END__

Input parameters MUST be byte strings, conforming to HTTP and/or OAuth
(RFC 5849) specifications.

my $oauth = Web::UserAgent::OAuth->new(
    url_scheme => 'http',
    request_method => 'GET',
    request_url => q</applications/my.json>,
    http_host => 'n.hatena.ne.jp',
    http_authorization => undef,
    form_body => undef,

    oauth_consumer_key => ...,
    client_shared_secret => ...,
    oauth_token => ...,
    token_shared_secret => ...,
);

$oauth->authenticate_by_oauth1(
    container => 'authorization',
    #container => 'query',
    #container => 'body',
);

warn "Signature base string: " . $oauth->signature_base_string . "\n";
warn "Request URL: " . $oauth->request_url . "\n";
warn "Authorization: " . ($oauth->http_authorization // '') . "\n";
warn "Body: " . ($oauth->form_body // '') . "\n";
