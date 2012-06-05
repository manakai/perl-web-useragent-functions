package LWP::UserAgent::Curl;
use strict;
use warnings;
our $VERSION = '1.0';
use base qw(LWP::UserAgent);
use File::Temp qw(tempfile);
use Path::Class;
use HTTP::Response;

our $Debug ||= $ENV{WEBUA_DEBUG} || 0;

# XXX Redirect handling

sub execute_request ($) {
    my $req = shift;
    
    my (undef, $header_file_name) = tempfile;
    my (undef, $body_file_name) = tempfile;
    
    $req->remove_header('Accept-Encoding') if $Debug;
    my @header;
    $req->scan(sub {
        push @header, $_[0] . ': ' . $_[1];
    });
    push @header, 'Expect: ';

    if ($Debug) {
        print STDERR "========== REQUEST ==========\n";
        print STDERR $req->method eq 'POST' ? 'POST' : 'GET';
        print STDERR ' ', $req->uri, "\n";
        print STDERR $_, "\n" for @header;
        print STDERR "\n";
        print STDERR $req->content, "\n" if $Debug >= 2;
        print STDERR "======== LWP::UA::Curl =======\n";
    }
    
    my @opt = (map { ('--header' => $_) } @header);
    push @opt, ('--data-binary' => $req->content) if $req->method eq 'POST';

    system 'curl',
        '--dump-header' => $header_file_name,
        -o => $body_file_name,
        @opt,
        $req->uri;
    
    my $header_f = file($header_file_name);
    my $body_f = file($body_file_name);

    my $header = $header_f->slurp;
    if ($Debug) {
        print STDERR "========== RESPONSE ==========\n";
        print STDERR $header;
        print STDERR "\n";
        print STDERR $body_f->slurp, "\n" if $Debug >= 2;
        print STDERR "======== LWP::UA::Curl =======\n";
    }
    
    my $res = HTTP::Response->parse($header . $body_f->slurp);
    $res->request($req);
    return $res;
}

# ------ |LWP::UserAgent::request|-compatibile interface ------

sub simple_request {
    my ($self, $req) = @_;
    
    return execute_request $req;
}

1;
