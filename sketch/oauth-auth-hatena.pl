use strict;
use warnings;
use Web::UserAgent::Functions::OAuth;

## OAuth1 redirect-based authorization example - Hatena

## Document:
## <http://developer.hatena.ne.jp/documents/auth/apis/oauth/consumer>.
##
## Usage:
## $ perl sketch/oauth-auth-hatena.pl KEY SECRET http://localhost/ read_public write_public
##
## License: Public Domain.

my ($ConsumerKey, $ConsumerSecret, $CallbackURL, @Scope) = @ARGV;
my $Host = 'www.hatena.ne.jp';
my $Path1 = q</oauth/initiate>;
my $Path2 = q</oauth/authorize>;
my $Path3 = q</oauth/token>;

my ($temp_token, $temp_token_secret, $auth_url)
    = http_oauth1_request_temp_credentials
    host => $Host,
    pathquery => $Path1,
    oauth_callback => $CallbackURL,
    oauth_consumer_key => $ConsumerKey,
    client_shared_secret => $ConsumerSecret,
    params => {scope => join ',', @Scope},
    auth => {pathquery => $Path2};
die "Failed" unless defined $temp_token;

my $input_key;
if (defined $CallbackURL and $CallbackURL ne 'oob') {
  print "Open <$auth_url> in the browser, click the Accept button, and paste the redirected URL here: ";
  $input_key = 'current_request_url';
} else {
  print "Open <$auth_url> in the browser, click the Accept button, and paste the verification code here: ";
  $input_key = 'oauth_verifier';
}
my $input = <STDIN>;
chomp $input;

my ($access_token, $access_token_secret, $params) = http_oauth1_request_token
    host => $Host,
    pathquery => $Path3,
    oauth_consumer_key => $ConsumerKey,
    temp_token => $temp_token,
    temp_token_secret => $temp_token_secret,
    client_shared_secret => $ConsumerSecret,
    $input_key => $input;
die "Failed" unless defined $access_token;

print "Access token: $access_token\n";
print "Access token secret: $access_token_secret\n";
print "Hatena ID: id:$params->{url_name}\n";
print "Hatena Nickname: $params->{display_name}\n";
