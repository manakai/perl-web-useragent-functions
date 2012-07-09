package test::Web::UA::Functions;
use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->subdir('lib')->stringify;
use lib glob file(__FILE__)->dir->parent->parent->subdir('*', 'lib')->stringify;
use base qw(Test::Class);
use Test::MoreMore;
use HTTest::Mock;
use HTTest::Mock::Server;
use Web::UserAgent::Functions;

our $LastRequestURL;
our $LastAuthorization;
our $LastPostBody;
HTTest::Mock::Server->add_handler(qr<^(http://test/get.*)> => sub {
    my ($server, $req, $res) = @_;
    $LastRequestURL = $1;
    $LastAuthorization = $req->header('Authorization');
    $LastPostBody = $req->content;
});
HTTest::Mock::Server->add_handler(qr<^(http://test/post.*)> => sub {
    my ($server, $req, $res) = @_;
    $LastRequestURL = $1;
    $LastAuthorization = $req->header('Authorization');
    $LastPostBody = $req->content;
});

sub _http_get_not_found : Test(3) {
    my ($req, $res) = http_get
        url => q<http://test/not/found>;
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 404;
}

sub _http_get_params_array : Test(5) {
    my ($req, $res) = http_get
        url => q<http://test/get>,
        params => {
            'abc$' => "xyz",
            abd => ["\x{1000}\x{2000}", 123],
        };
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    is $LastRequestURL, qq<http://test/get?abc%24=xyz&abd=%E1%80%80%E2%80%80&abd=123>;
    is $LastPostBody, qq<>;
}

sub _http_get_params_oauth_array_query : Test(6) {
    my ($req, $res) = http_get
        url => q<http://test/get>,
        params => {
            'abc&' => ['xyz123%', 'xyz'],
            abd => "\x{1000}\x{2000}",
        },
        oauth => ['consumerkey', 'consumersecret', 'accesskey', 'accesssecret'],
        oauth_method => 'query';
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    like $LastRequestURL, qr<^http://test/get\?abc%26=xyz&abc%26=xyz123%25&abd=%E1%80%80%E2%80%80&oauth_consumer_key=consumerkey&oauth_nonce=[^&]+&oauth_signature=[^&]+&oauth_signature_method=HMAC-SHA1&oauth_timestamp=\d+&oauth_token=accesskey&oauth_version=1.0$>;
    is $LastAuthorization, undef;
    is $LastPostBody, q<>;
}

sub _http_get_params_oauth_array_auth : Test(6) {
    my ($req, $res) = http_get
        url => q<http://test/get>,
        params => {
            'abc&' => ['xyz123%', 'xyz'],
            abd => "\x{1000}\x{2000}",
        },
        oauth => ['consumerkey', 'consumersecret', 'accesskey', 'accesssecret'],
        oauth_method => 'authorization';
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    like $LastRequestURL, qr<^http://test/get\?abc%26=xyz&abc%26=xyz123%25&abd=%E1%80%80%E2%80%80$>;
    like $LastAuthorization, qr<^OAuth realm="", oauth_consumer_key="consumerkey", oauth_nonce="[^"]+", oauth_signature="[^"]+", oauth_signature_method="HMAC-SHA1", oauth_timestamp="\d+", oauth_token="accesskey", oauth_version="1.0"$>;
    is $LastPostBody, q<>;
}

sub _http_post_params : Test(5) {
    my ($req, $res) = http_post
        url => q<http://test/post>,
        params => {
            abc => "xyz",
            abd => "\x{1000}\x{2000}",
        };
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    is $LastRequestURL, qq<http://test/post>;
    is $LastPostBody, qq<abc=xyz&abd=%E1%80%80%E2%80%80>;
}

sub _http_post_params_array : Test(5) {
    my ($req, $res) = http_post
        url => q<http://test/post>,
        params => {
            'abc$' => "xyz",
            abd => ["\x{1000}\x{2000}", 123],
        };
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    is $LastRequestURL, qq<http://test/post>;
    is $LastPostBody, qq<abc%24=xyz&abd=%E1%80%80%E2%80%80&abd=123>;
}

sub _http_post_params_oauth_body : Test(6) {
    my ($req, $res) = http_post
        url => q<http://test/post>,
        params => {
            abc => "xyz",
            abd => "\x{1000}\x{2000}",
        },
        oauth => ['consumerkey', 'consumersecret', 'accesskey', 'accesssecret'],
        oauth_method => 'body';
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    is $LastRequestURL, qq<http://test/post>;
    is $LastAuthorization, undef;
    like $LastPostBody, qr<abc=xyz&abd=%E1%80%80%E2%80%80&oauth_consumer_key=consumerkey&oauth_nonce=[^&]+&oauth_signature=[^&]+&oauth_signature_method=HMAC-SHA1&oauth_timestamp=\d+&oauth_token=accesskey&oauth_version=1.0>;
}

sub _http_post_params_oauth_query : Test(6) {
    my ($req, $res) = http_post
        url => q<http://test/post>,
        params => {
            abc => "xyz",
            abd => "\x{1000}\x{2000}",
        },
        oauth => ['consumerkey', 'consumersecret', 'accesskey', 'accesssecret'],
        oauth_method => 'query';
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    like $LastRequestURL, qr<http://test/post\?oauth_consumer_key=consumerkey&oauth_nonce=[^&]+&oauth_signature=[^&]+&oauth_signature_method=HMAC-SHA1&oauth_timestamp=\d+&oauth_token=accesskey&oauth_version=1.0>;
    is $LastAuthorization, undef;
    is $LastPostBody, q<abc=xyz&abd=%E1%80%80%E2%80%80>;
}

sub _http_post_params_oauth_authorization : Test(6) {
    my ($req, $res) = http_post
        url => q<http://test/post>,
        params => {
            abc => "xyz",
            abd => "\x{1000}\x{2000}",
        },
        oauth => ['consumerkey', 'consumersecret', 'accesskey', 'accesssecret'],
        oauth_method => 'authorization';
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    is $LastRequestURL, qq<http://test/post>;
    like $LastAuthorization, qr<OAuth realm="", oauth_consumer_key="consumerkey", oauth_nonce="[^"]+", oauth_signature="[^"]+", oauth_signature_method="HMAC-SHA1", oauth_timestamp="\d+", oauth_token="accesskey", oauth_version="1.0">;
    is $LastPostBody, q<abc=xyz&abd=%E1%80%80%E2%80%80>;
}

sub _http_post_params_oauth_array : Test(5) {
    my ($req, $res) = http_post
        url => q<http://test/post>,
        params => {
            'abc&' => ['xyz123%', 'xyz'],
            abd => "\x{1000}\x{2000}",
        },
        oauth => ['consumerkey', 'consumersecret', 'accesskey', 'accesssecret'],
        oauth_method => 'body';
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    is $LastRequestURL, qq<http://test/post>;
    like $LastPostBody, qr<abc%26=xyz&abc%26=xyz123%25&abd=%E1%80%80%E2%80%80&oauth_consumer_key=consumerkey&oauth_nonce=[^&]+&oauth_signature=[^&]+&oauth_signature_method=HMAC-SHA1&oauth_timestamp=\d+&oauth_token=accesskey&oauth_version=1.0>;
}

sub _http_post_data : Test(5) {
    my ($req, $res) = http_post_data
        url => q<http://test/post>,
        content => "\x12\x81\x21\x60\x98\xA2",
        content_type => 'application/octet-stream';
    isa_ok $req, 'HTTP::Request';
    isa_ok $res, 'HTTP::Response';
    is $res->code, 200;
    is $LastRequestURL, qq<http://test/post>;
    is $LastPostBody, qq<\x12\x81\x21\x60\x98\xA2>;
}

sub _cookies : Test(1) {
    my ($req, $res) = http_post
        url => q<http://test/post>,
        cookies => {
            'Cookie A' => "ab \x{4000}; !",
            'Cookie B"' => "ab \x{4000}; !",
            'CookieC' => undef,
            "\x{5000}Cookie D" => '',
        };
    is $req->header('Cookie'), 'Cookie%20A=ab%20%E4%80%80%3B%20%21; Cookie%20B%22=ab%20%E4%80%80%3B%20%21; %E5%80%80Cookie%20D=';
}

sub _lwp_broken : Test(4) {
#line 1 "_lwp_broken"
    local *LWP::UserAgent::request = sub { die "Internal LWP error!!1" };
    my ($req, $res) = http_get url => q<http://hoge/fuga>;
    isa_ok $res, 'HTTP::Response';
    is $res->code, 500;
    is $res->message, 'LWP Error';
    is $res->content, "Internal LWP error!!1 at _lwp_broken line 1.\n"
}

__PACKAGE__->runtests;

1;
