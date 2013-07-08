package Test::WebService::LWPAuthen;
use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common;
use URI;
use Exporter::Lite;

our @EXPORT = qw(with_lwp_authen);

our $Debug ||= $ENV{TEST_WS_DEBUG} || 0;
our $DUMP_OUTPUT = \*STDERR;

our $Hostname = q[webservice.test];
our $Port = 80;
our $Scheme = q[http];
our $Realm = q[TestRealm];
our $UserID = q[test-user];
our $Password = q[test-password];

sub with_lwp_authen (&$%) {
    my ($code, $url, %args) = @_;

    my $base = qq[$Scheme://$Hostname:$Port/];
    $url = URI->new_abs($url, $base);
    my $hostport = $url->host . ':' . $url->port;

    my $realm = exists $args{realm} ? $args{realm} : $Realm;
    my $userid = exists $args{userid} ? $args{userid} : $UserID;
    my $password = exists $args{password} ? $args{password} : $Password;
    
    my $ua = LWP::UserAgent->new(parse_head => 0);
    $ua->credentials($hostport, $realm, $userid, $password);
    
    my $method = $args{request_method} || 'GET';
    my $content = $args{params} ? $args{params} : [];
    my $req = $method eq 'POST' ? POST $url, $content : GET $url;

    if ($Debug >= 2) {
        print $DUMP_OUTPUT "====== REQUEST ======\n";
        print $DUMP_OUTPUT $req->as_string;
        print $DUMP_OUTPUT "====== EXTERNAL =====\n";
    } elsif ($Debug) {
        print $DUMP_OUTPUT "====== REQUEST ======\n";
        print $DUMP_OUTPUT $req->method, ' ', $req->uri, ' ', ($req->protocol || ''), "\n";
        print $DUMP_OUTPUT $req->headers_as_string;
        print $DUMP_OUTPUT "====== EXTERNAL =====\n";
    }
    
    my $res = $ua->request($req);

    if ($Debug >= 2) {
        print $DUMP_OUTPUT "====== RESPONSE =====\n";
        print $DUMP_OUTPUT $res->as_string;
        print $DUMP_OUTPUT "====== EXTERNAL =====\n";
    } elsif ($Debug) {
        print $DUMP_OUTPUT "====== RESPONSE =====\n";
        print $DUMP_OUTPUT $res->protocol, ' ', $res->status_line, "\n";
        print $DUMP_OUTPUT $res->headers_as_string;
        print $DUMP_OUTPUT "====== EXTERNAL =====\n";
    }
    
    $code->($req, $res);
}

1;
