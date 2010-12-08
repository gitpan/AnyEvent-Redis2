package AnyEvent::Redis2;

use 5.008;
use common::sense;

use Carp qw(croak);
use AnyEvent::Handle;
use AnyEvent::Redis2::Protocol;

our $VERSION = 0.3;

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
L<AnyEvent::Redis::Subscriber>.  However, this module may be used to publish to
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

=item on_connect => $cb->($host, $port)

Specifies a callback to be executed upon a successful connection.  The actual
peer host and port number will be passed as arguments to the callback.

=item on_connect_error => $cb->($errmsg)

Specifies a callback to be executed if the connection failed (or authentication
failed).  The error message will be passed to the callback. 

The callback may return an interval value (as a fractional number); if
specified, the client will automatically attempt to reconnect at that interval
until successful.

=item on_error => $cb->($errmsg)

Specifies a callback to be executed if an I/O error occurs (e.g. connection
reset by peer).  The error message will be passed to the callback.

The callback may return an interval value (as a fractional number); if
specified, the client will automatically attempt to reconnect at that interval
until successful.

=back

=cut

sub connect {
    my ($class, %args) = @_;
    
    $args{host} or croak "Missing host";
    $args{port} ||= 6379;

    my $self = { %args };
    bless $self, $class;

    $self->_connect;
    return $self;
}

sub _connect {
    my $self = shift;
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
                            $self->{on_connect}->($host, $port) 
                                if $self->{on_connect};
                        } else {
                            $self->{handle}->destroy;
                            $self->{on_connect_error}->($_[2])
                                if $self->{on_connect_error};
                        }
                });
            } else {
                $self->{on_connect}->($host, $port) 
                    if $self->{on_connect};
            }
        },
        on_connect_error => sub { 
            if ($self->{on_connect_error}) {
                if (defined(my $interval = $self->{on_connect_error}->($_[1]))) {
                    my $t; $t = AE::timer($interval, 0, sub {
                            $self->_connect;
                            undef $t;
                    });
                }
            }
        },
        on_error   => sub { 
            $self->{handle}->destroy; 
            if ($self->{on_error}) {
                if (defined(my $interval = $self->{on_error}->($_[2]))) {
                    my $t; $t = AE::timer($interval, 0, sub {
                            $self->_connect;
                            undef $t;
                    });
                }
            }
        }, 
    );
}

=head2 Queries and responses

After you have successfully connected to the server, you can issue 
queries to it.  (You'll want to do this in the C<on_connect> callback
handler fired by connect(), above.)  

To issue a query, use the query() method:

  $cv = $redis->query(@args, [ $cb->($data, $error) ]);

The initial list of arguments to query() comprise the actual command.
(See the command reference
L<http://code.google.com/p/redis/wiki/CommandReference> for a list of available
commands.)

The final argument to query() specifies a optional callback (code reference)
that will be fired when a response to the query is received.  It will be called
with the data (either a scalar, or an ARRAY reference for a multi-bulk
response) as the first argument, and a scalar indicating whether the data is an
error message as the second argument.

query() will return an L<AnyEvent> condition variable that can also be used to
retrieve the results via its recv() method (or via cb() if you don't want to
block).  If an error occurs, recv() will die, so be sure to wrap it in an
C<eval>:

  my $cv = $redis->query(@args);
  eval { 
      my $result = $cv->recv; 
      # ...
  };
  if ($@) {
      warn "server error: $@";
      ...
  }

=cut

sub query {
    my ($self, @args) = @_;

    my $cb; $cb = pop @args if ref($_[-1]) eq 'CODE';
    scalar @args or croak "Missing args";

    $args[0] !~ /^P?(?:UN)?SUBSCRIBE/ 
        or croak 'Subscriptions not supported; use AnyEvent::Redis2::Subscriber instead';

    my $cv = AnyEvent->condvar;
    $self->{handle}->push_write('AnyEvent::Redis2::Protocol', @args);
    $self->{handle}->push_read('AnyEvent::Redis2::Protocol' => sub {
            $cb->(@_) if $cb;
            # croak if error occurred; otherwise send data
            $_[1] ? $cv->croak($_[0]) : $cv->send($_[0]);
            1;
    });
    return $cv;
}

=pod

Alternatively, you may invoke Redis commands as methods, e.g.: 

 $cv = $redis->set(key1 => $val1, [ $cb->($result, $error) ]);
 $cv = $redis->lrange('list', 0, 1000, [ $cb->($result, $error) ]);
 $cv = $redis->get(key1, [ $cb->($result, $error) ]);

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

=head1 WHY NOT AnyEvent::Redis?

AnyEvent::Redis2 began as a from-scratch implementation of a Redis module for
AnyEvent.  (When I began writing it, I didn't know such a module already
existed.)  Instead of abandoning it when I realized my oversight, I decided to
contribute it. 

The substantive differences from AnyEvent::Redis are:

=over

=item Better documentation

=item Automatic reconnection capability

=item on_connect() callback 

=item Simpler, faster protocol parser (about 30% faster sending large numbers
of queries; about 10% faster receiving bulk responses)

=item Easier-to-read code

=item Explicit separation of subscriber functionality (into
AnyEvent::Redis2::Subscriber) 

=back

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
