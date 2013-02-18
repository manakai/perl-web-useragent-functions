package Test::WebService::LWP;
use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request::Common ();
use URI;
use Exporter::Lite;

our @EXPORT = qw(with_lwp GET POST);

our $Debug ||= $ENV{TEST_WS_DEBUG} || 0;
our $DUMP_OUTPUT = \*STDERR;

our $Hostname = q[webservice.test];
our $Port = 80;
our $Scheme = q[http];

sub with_lwp (&$%) {
    my ($code, $url, %args) = @_;

    my $base = qq[$Scheme://$Hostname:$Port/];
    $url = URI->new_abs($url, $base);
    my $hostport = $url->host . ':' . $url->port;
    
    my $ua = LWP::UserAgent->new(parse_head => 0);
    
    my $method = $args{request_method} || 'GET';
    my $content = $args{params} ? $args{params} : [];
    my $req = $method eq 'POST'
        ? HTTP::Request::Common::POST $url, $content
        : HTTP::Request::Common::GET $url;

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
    
    return $code->($req, $res);
}

sub GET (&$%) {
    my ($code, $url, %args) = @_;
    return &with_lwp($code, $url, %args, request_method => 'GET');
}

sub POST (&$%) {
    my ($code, $url, %args) = @_;
    return &with_lwp($code, $url, %args, request_method => 'POST');
}

1;
