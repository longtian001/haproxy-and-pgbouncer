#!/usr/bin/perl -w
use strict;
use POSIX;
use DBI;
use Try::Tiny;
use HTTP::Daemon;
use HTTP::Response;
use HTTP::Status;
use threads;

# web config
my $web_ip = "192.168.0.108";
my $web_port = 8080;

# db config
my $db = "testdb";
my $db_host = "127.0.0.1";
my $drive = "Pg";

# startup web server
my $d = HTTP::Daemon->new(LocalAddr => $web_ip,
                          LocalPort => $web_port,
                          Listen => SOMAXCONN,
                          Reuse => 1); 

die "$0: can't setup server" unless $d;

print "Web Server started!\n";
print "Server Address: ", $d->sockhost(), "\n";
print "Server Port: ", $d->sockport(), "\n";

# accept http get request
while (my $c = $d->accept) {
    # fork new child, if not exit process
    my $pid=$$;
    unless ($pid = fork()){
        # receive access
        process_get_request($c);
        exit;     
    }
}

# Func: process get request
sub process_get_request {
    my $c = shift;
    while (my $r = $c->get_request) {
            if ($r->method eq 'GET') {
                # parse url 
                my $path = $r->uri->as_string;
                my @url_path = split(/\//,$path);
                my $user=$url_path[3];
                my $port=$url_path[5];
                # print access url params: user, port
                # print "$user,$port\n";
                # access postgresql,check hostname
                my $http_status= &pgcheck($user,$port);
                # print "$http_status\n";
                my $timestamp = getLoggingTime();
                print "$timestamp, pgbouncer user: $user, port: $port, http status: $http_status.\n";
                # successfull, return 200
                if ( $http_status == 200 ){
                    _http_response($c, { content_type => 'text/plain' }, 200);
                } else{
                    $c->send_error(RC_NOT_FOUND);
                }
            # other URL method not allowed 
            } else {
                $c->send_error(RC_FORBIDDEN)
            }
        }
        $c->close;
        undef($c);
}


# Func: check hostname in local postgresql db's in storage procedure: check_ha()
sub pgcheck{
    my ($user,$port) = @_;
    try {
        # use URL params: user, port, then conn local pg database
        my $dbh = DBI->connect("dbi:Pg:dbname=$db;host=$db_host;port=$port", "$user", '',
          { PrintError => 0, RaiseError => 1,pg_server_prepare => 0, }) or die $DBI::errstr;
        # do not use database if check_ha() returns 'false'
        my $sth = $dbh->prepare("select public.check_ha()");
        my $rv = $sth->execute;
        if($rv < 0){
            print $DBI::errstr;
        } else{
            my @row = $sth->fetchrow_array;
            if ( $row[0] == 0 ) {
                return 503;
            }
            # find hostname, http 200 => "Database '$db' at '$host' is alive";
            return 200;
        }
        $dbh->disconnect();
    } catch{
      # when conn db or execute sth error
      print "Error: ".$_;
    }
}

# Func: http response
sub _http_response {
    my $c = shift;
    my $options = shift;

    $c->send_response(
        HTTP::Response->new(
            RC_OK,
            undef,
            [
                'Content-Type' => $options->{content_type},
                'Cache-Control' => 'no-store, no-cache, must-revalidate, post-check=0, pre-check=0',
                'Pragma' => 'no-cache',
                'Expires' => 'Thu, 01 Dec 1994 16:00:00 GMT',
            ],
            join("\n", @_),
        )
    );
}

# get current system time
sub getLoggingTime {

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
    my $nice_timestamp = sprintf ( "%04d-%02d-%02d %02d:%02d:%02d",
                                   $year+1900,$mon+1,$mday,$hour,$min,$sec);
    return $nice_timestamp;
}
