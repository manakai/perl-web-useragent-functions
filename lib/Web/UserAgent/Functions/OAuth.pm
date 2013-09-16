package Web::UserAgent::Functions::OAuth;
use strict;
use warnings;
our $VERSION = '1.0';
use Carp qw(croak);
use Encode;
use Web::UserAgent::Functions qw(http_post_data);
use Web::UserAgent::OAuth;
use Exporter::Lite;

our @EXPORT;
our @EXPORT_OK;

## <http://tools.ietf.org/html/rfc5849#section-2.2>
push @EXPORT_OK, qw(http_oauth1_get_auth_url);
sub http_oauth1_get_auth_url (%) {
  my %args = @_;

  if (not defined $args{url}) {
    $args{url} = ($args{url_scheme} || 'https') . '://' . $args{host} . $args{pathquery};
  }

  $args{url} =~ s/\#.*//s;
  $args{url} .= $args{url} =~ /\?/ ? '&' : '?';

  my $token = $args{temp_token};
  croak '|temp_token| is not specified' unless defined $token;
  $token =~ s/([^0-9A-Za-z._~-])/sprintf '%%%02X', ord $1/ge;

  $args{url} .= 'oauth_token=' . $token;

  return $args{url};
} # http_oauth1_get_auth_url

## <http://tools.ietf.org/html/rfc5849#section-2.1>.
push @EXPORT, qw(http_oauth1_request_temp_credentials);
sub http_oauth1_request_temp_credentials (%) {
  my %args = @_;

  my $scheme = $args{url_scheme} || 'https';
  my $cb = $args{oauth_callback};
  $cb = 'oob' unless defined $cb;

  my $oauth = Web::UserAgent::OAuth->new (
    url_scheme => $scheme,
    request_method => 'POST',
    http_host => $args{host},
    request_url => $args{pathquery},
    form_body => Web::UserAgent::Functions::serialize_form_urlencoded ({%{$args{params} or {}}, oauth_callback => $cb}),
    oauth_consumer_key => $args{oauth_consumer_key},
    client_shared_secret => $args{client_shared_secret},
    oauth_token => undef,
    token_shared_secret => '',
  );
  $oauth->authenticate_by_oauth1 (container => 'authorization');

  my ($temp_token, $temp_token_secret, $auth_url);
  http_post_data
      url_scheme => $scheme,
      host => $args{host},
      pathquery => $oauth->request_url,
      header_fields => {Authorization => $oauth->http_authorization,
                        'Content-Type' => 'application/x-www-form-urlencoded'},
      content => $oauth->form_body,
      anyevent => $args{anyevent},
      cb => sub {
        my ($req, $res) = @_;
        if ($res->code == 200) {
          ## Don't check Content-Type for interoperability...
          my %param = map { tr/+/ /; s/%([0-9A-Fa-f]{2})/pack 'C', hex $1/ge; $_ } map { (split /=/, $_, 2) } split /&/, $res->content, -1;
          unless ($param{oauth_callback_confirmed} eq 'true') {
            warn "<@{[$req->uri]}>: |oauth_callback_confirmed| is not |true|\n";
          }
          warn "<@{[$req->uri]}>: No |oauth_token| in response\n"
              unless defined $param{oauth_token};
          warn "<@{[$req->uri]}>: No |oauth_token_secret| in response\n"
              unless defined $param{oauth_token_secret};
          $temp_token = $param{oauth_token};
          $temp_token_secret = $param{oauth_token_secret};
        } else {
          warn "<@{[$req->uri]}>: Not OAuth response\n";
        }
        $auth_url = http_oauth1_get_auth_url
            url_scheme => $args{url_scheme},
            host => $args{host},
            %{$args{auth} or []},
            temp_token => $temp_token
                if defined $temp_token;
        $args{cb}->($temp_token, $temp_token_secret, $auth_url) if $args{cb};
      };

  return ($temp_token, $temp_token_secret, $auth_url);
} # http_oauth1_request_temp_credentials

## <http://tools.ietf.org/html/rfc5849#section-2.3>.
push @EXPORT, qw(http_oauth1_request_token);
sub http_oauth1_request_token (%) {
  my %args = @_;

  croak "|temp_token| is not specified" unless defined $args{temp_token};
  if (defined $args{oauth_verifier}) {
    if (defined $args{current_request_oauth_token} and
        $args{current_request_oauth_token} ne $args{temp_token}) {
      croak "|current_request_oauth_token| is not equal to |temp_token|";
    }
  } else {
    croak "Neither |oauth_verifier| or |current_request_url| is specified"
        unless defined $args{current_request_url};
    my $url = $args{current_request_url};
    $url =~ s/\#.*//s;
    if ($url =~ /\?(.+)/s) {
      my %param = map { tr/+/ /; s/%([0-9A-Fa-f]{2})/pack 'C', hex $1/ge; $_ } map { (split /=/, $_, 2) } split /&/, $1, -1;
      if (not defined $param{oauth_token}) {
        croak "|current_request_url| does not have |oauth_token|";
      }
      if ($param{oauth_token} ne $args{temp_token}) {
        croak "|current_request_url|'s |oauth_token| is not equal to |temp_token|";
      }
      if (not defined $param{oauth_verifier}) {
        croak "|current_request_url| does not have |oauth_verifier|";
      }
      $args{oauth_verifier} = $param{oauth_verifier};
    } else {
      croak "|current_request_url| does not have |oauth_token| and |oauth_verifier|";
    }
  }

  my $scheme = $args{url_scheme} || 'https';
  my $oauth = Web::UserAgent::OAuth->new (
    url_scheme => $scheme,
    request_method => 'POST',
    http_host => $args{host},
    request_url => $args{pathquery},
    oauth_consumer_key => $args{oauth_consumer_key},
    client_shared_secret => $args{client_shared_secret},
    oauth_token => $args{temp_token},
    token_shared_secret => $args{temp_token_secret},
    oauth_verifier => $args{oauth_verifier},
  );

  $oauth->authenticate_by_oauth1 (container => 'authorization');

  my ($token, $token_secret, %param);
  http_post_data
      url_scheme => $scheme,
      host => $args{host},
      pathquery => $oauth->request_url,
      header_fields => {Authorization => $oauth->http_authorization},
      content => '',
      anyevent => $args{anyevent},
      cb => sub {
        my ($req, $res) = @_;
        if ($res->code == 200) {
          ## Don't check Content-Type for interoperability...
          %param = map { tr/+/ /; s/%([0-9A-Fa-f]{2})/pack 'C', hex $1/ge; decode 'utf-8', $_ } map { (split /=/, $_, 2) } split /&/, $res->content, -1;
          warn "<@{[$req->uri]}>: No |oauth_token| in response\n"
              unless defined $param{oauth_token};
          warn "<@{[$req->uri]}>: No |oauth_token_secret| in response\n"
              unless defined $param{oauth_token_secret};
          $token = delete $param{oauth_token};
          $token_secret = delete $param{oauth_token_secret};
        } else {
          warn "<@{[$req->uri]}>: Not OAuth response\n";
        }
        $args{cb}->($token, $token_secret, \%param) if $args{cb};
      };
  return ($token, $token_secret, \%param);
} # http_oauth1_request_token

1;
