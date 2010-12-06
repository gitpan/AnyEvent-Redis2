package AnyEvent::Redis2;

use 5.008;
use common::sense;

use Carp qw(croak);
use AnyEvent::Handle;
use AnyEvent::Redis2::Protocol;

our $VERSION = 0.1;

=head1 NAME

AnyEvent::Redis2 - an event-driven Redis client

=head1 SYNOPSIS

 use AnyEvent::Redis2;
 my $redis = AnyEvent::Redis2->connect(
     host => 'redis',
     on_connect => $cb, 
     on_connect_error => $errcb,
     on_error => $errcb,
 );

 # Generic query method
 $redis->query('SET', $key, $value, $cb);

 # Autoloaded query method
 $redis->set($key, $value, $cb);

=head1 DESCRIPTION

This module is an AnyEvent user; you must use and run a supported event
loop.

AnyEvent::Redis2 is an event-driven (asynchronous) client for the Redis
key-value (NoSQL) database server.  Every operation is supported, B<except>
subscription to Redis "classes" (i.e. channels), which is supported by
AnyEvent::Redis::Subscriber.  However, this module may be used to publish to
channels.

=head2 Establishing a connection

To connect to the Redis server, use the connect() method:

 my $redis = AnyEvent::Redis2->connect(host => <host>, ...);

The C<host> argument is required.

Optional (but recommended) arguments include:

=over

=item port => $port

Connect to the server on the specified port number.  (If not specified,
the default port will be used.)

=item auth => $password

Authenticate to the server with the given password.

=item on_connect => $cb->($conn, $host, $port)

Specifies a callback to be executed upon a successful connection.  The
connection object and the actual peer host and port number will be passed as
arguments to the callback.

=item on_connect_error => $cb->($conn, $errmsg)

Specifies a callback to be executed if the connection failed (or authentication
failed).  The connection object and the error message will be passed as
arguments to the callback.  The connection is not reusable.

=item on_error => $cb->($conn, $errmsg)

Specifies a callback to be executed if an I/O error occurs (e.g. connection
reset by peer).  The connection object and the error message will be passed as
arguments to the callback.  The connection is not reusable.

=back

=cut

sub connect {
    my ($class, %args) = @_;
    
    $args{host} or croak "Missing host";
    $args{port} ||= 6379;

    my $self = { %args };
    bless $self, $class;

    $self->{handle} = AnyEvent::Handle->new(
        connect => [ $self->{host}, $self->{port} ],
        keepalive  => 1,
        no_delay   => 1,
        on_connect => sub { 
            my ($handle, $host, $port) = @_;
            if ($self->{auth}) {
                $self->{handle}->push_write('AnyEvent::Redis2::Protocol', 
                                            AUTH => $self->{auth});
                $self->{handle}->push_read('AnyEvent::Redis2::Protocol' => sub {
                        my ($handle, $ok) = @_;
                        if ($ok) {
                            $self->{on_connect}->($self, $host, $port) 
                                if $self->{on_connect};
                        } else {
                            $self->{handle}->destroy;
                            $self->{on_connect_error}->($self, $_[2])
                                if $self->{on_connect_error};
                        }
                });
            } else {
                $self->{on_connect}->($self, $host, $port) 
                    if $self->{on_connect};
            }
        },
        on_connect_error => sub { 
            $self->{on_connect_error}->($self, $_[1]) 
                if $self->{on_connect_error};
        },
        on_error   => sub { 
            $self->{handle}->destroy; 
            $self->{on_error}->($self, $_[2]) if $self->{on_error};
        }, 
    );

    return $self;
}

=head2 Queries and responses

After you have successfully connected to the server, you can issue 
queries to it.  (You'll want to do this in the C<on_connect> callback
handler fired by connect(), above.)  

To issue a query, use the query() method:

  $redis->query(@args, $cb->($errmsg, @data)));

The initial list of arguments to query() comprise the actual command.
(See the command reference
L<http://code.google.com/p/redis/wiki/CommandReference> for a list of available
commands.)

The final argument to query() specifies a callback (code reference) that will
be fired when a response to the query is received.  It will be called with the
error message (which will be C<undef> if there was no error) as the first
argument; the remaining arguments will be the values (if any) that comprise the
response.  

=cut

sub query {
    my ($self, @args) = @_;

    my $cb = pop @args;
    ref($cb) eq 'CODE' or croak 'Missing callback';
    scalar @args or croak "Missing args";

    $args[0] !~ /^P?(?:UN)?SUBSCRIBE/ 
        or croak 'Subscriptions not supported; use AnyEvent::Redis2::Subscriber instead';

    $self->{handle}->push_write('AnyEvent::Redis2::Protocol', @args);
    $self->{handle}->push_read('AnyEvent::Redis2::Protocol' => sub {
        my ($handle, $errmsg, @values) = @_;
        $cb->($errmsg, @values);
    });
}

=pod

Alternatively, you may invoke Redis commands as methods, e.g.: 

 $redis->set(key1 => $val1, sub { ... });
 $redis->get(key1 => sub { ... });

=cut

sub AUTOLOAD {
    use vars '$AUTOLOAD';
    my $op = $AUTOLOAD;
    $op =~ s/.*:://;
    my ($self, @args) = @_;
    $self->query(uc($op), @args);
}

sub DESTROY {
    # Don't delete this, or AUTOLOAD will be invoked on DESTROY.
}

=head1 SEE ALSO

Redis Command Reference L<http://code.google.com/p/redis/wiki/CommandReference>

=head1 AUTHOR

Michael S. Fischer <michael+cpan@dynamine.net>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 Michael S. Fischer.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;

__END__

# vim:syn=perl:ts=4:sw=4:et:ai
