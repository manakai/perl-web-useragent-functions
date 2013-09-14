use strict;
use warnings;
use Web::UserAgent::Functions::OAuth;

## OAuth1 redirect-based authorization example - Twitter

## Document:
## <https://dev.twitter.com/docs/auth/3-legged-authorization>,
## <https://dev.twitter.com/docs/auth/sign-twitter>.
##
## Usage:
## $ perl sketch/oauth-auth-twitter.pl KEY SECRET http://localhost/
##
## License: Public Domain.

my ($ConsumerKey, $ConsumerSecret, $CallbackURL) = @ARGV;
my $Host = 'api.twitter.com';
my $Path1 = q</oauth/request_token>;
my $Path2 = q</oauth/authorize>; # or q</oauth/authenticate> for "Sign in"
my $Path3 = q</oauth/access_token>;

my ($temp_token, $temp_token_secret, $auth_url)
    = http_oauth1_request_temp_credentials
    host => $Host,
    pathquery => $Path1,
    oauth_callback => $CallbackURL,
    oauth_consumer_key => $ConsumerKey,
    client_shared_secret => $ConsumerSecret,
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
print "Twitter ID (#): $params->{user_id}\n";
print "Twitter name: \@$params->{screen_name}\n";
