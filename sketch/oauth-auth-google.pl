use strict;
use warnings;
use Web::UserAgent::Functions;

my ($ClientID, $ClientSecret, $CallbackURL, @Scope) = @ARGV;
die "Usage: $0 client-id client-secret callback-url scope1 scope2 ..."
    unless @Scope;
$CallbackURL = 'urn:ietf:wg:oauth:2.0:oob' if $CallbackURL eq 'oob';

## <https://developers.google.com/accounts/docs/OAuth2InstalledApp>

my $URL1 = sprintf q<https://accounts.google.com/o/oauth2/auth?scope=%s&redirect_uri=%s&response_type=code&client_id=%s>,
    (join '%20', @Scope), $CallbackURL, $ClientID;

if (not $CallbackURL =~ /^urn:ietf:wg:oauth:2.0:oob/) {
  print "Open <$URL1> in the browser, click the Accept button, and paste the redirected URL here: ";
} else {
  print "Open <$URL1> in the browser, click the Accept button, and paste the verification code here: ";
}
my $input = <STDIN>;
chomp $input;

my $code = $input;
if ($input =~ /\bcode=([^&#]+)/) {
  $code = $1;
}

my (undef, $res) = http_post
    url => q<https://accounts.google.com/o/oauth2/token>,
    params => {
      code => $code,
      client_id => $ClientID,
      client_secret => $ClientSecret,
      redirect_uri => $CallbackURL,
      grant_type => 'authorization_code',
    };

warn $res->content;
my $body = $res->content;
$body =~ /"access_token"\s*:\s*"([^"]+)"/;
my $access_token = $1;

=pod

my (undef, $res) = http_get
    url => q<https://www.googleapis.com/plus/v1/people/me/openIdConnect>,
    params => {
    },
    header_fields => {
      authorization => 'Bearer ' . $access_token,
    };

warn $res->content;


my (undef, $res) = http_get
    url => q<https://www.googleapis.com/oauth2/v3/userinfo>,
    params => {
    },
    header_fields => {
      authorization => 'Bearer ' . $access_token,
    };

warn $res->content;

=cut

my (undef, $res) = http_get
    url => q<https://openidconnect.googleapis.com/v1/userinfo>,
    params => {
    },
    header_fields => {
      authorization => 'Bearer ' . $access_token,
    };

warn $res->content;
