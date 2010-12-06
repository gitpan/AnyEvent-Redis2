package AnyEvent::Redis2::Subscriber;

use 5.008;
use common::sense;

use base 'Object::Event';
use Carp qw(croak);
use AnyEvent::Handle;
use AnyEvent::Redis2::Protocol;

=head1 NAME

AnyEvent::Redis2::Subscriber - event-driven Redis subscriber client

=head1 SYNOPSIS

 use AnyEvent::Redis2::Subscriber;
 my $subscriber = AnyEvent::Redis2::Subscriber->subscribe(
     host => 'redis', 
     channel => 'z'
 );
 $subscriber->reg_cb(message => sub {
     my ($subscriber, $message) = @_;
     # ...
 };

=head1 DESCRIPTION

This module is an AnyEvent user; you must use and run a supported event
loop.

AnyEvent::Redis2::Subscriber is an event-driven (asynchronous) subscriber for
the Redis publish/subscribe system.  

The main idea is that other clients (such as AnyEvent::Redis2) publish messages
to a specified channel (or class, in Redis-speak), which are then received by
each client that has subscribed to the channel.

Unlike some other publish/subscribe mechanisms which are producer-consumer
based, Redis' publish/subscribe mechanism is broadcast-based: every subscriber
to a channel receives every message sent to that channel; and messages are not
queued for future delivery if there are no subscribers for that channel.

=head2 Subscribing to a channel

To subscribe to a channel, call the subscribe() method:

 my $subscriber = AnyEvent::Redis2::Subscriber->subscribe(
    host => $host,
    channel => $channel,
    ...
 );

This immediately establishes a connection to the Redis server at the given host
and subscribes to the specified channel. 

Pattern-based subscriptions are also possible.  Instead of specifying a
C<channel>, a C<pattern> may be specified consisting of a glob pattern that
matches channel names.  For example, if C<chan_*> is specified, then the client
will receive every message sent to "chan_1", "chan_2", "chan_zebra", and so
forth while connected to the server:

 my $subscriber = AnyEvent::Redis2::Subscriber->subscribe(
    host => $host,
    pattern => $pattern,
    ...
 );

Optional arguments include:

=over 

=item port => $port

Connect to the Redis server at L<$port>.  If undefined, the default port (6379)
is used.

=item auth => $password

Authenticate to the server with the given password.

=back

=head2 Receiving messages

To receive messages, register a callback for the C<message> event.  When a
message is received, the callback will be fired with the message and the
channel it was received on:

 $subscriber->reg_cb(message => sub {
     my ($subscriber, $channel, $message) = @_;
     print "Received message $message on channel $channel";
 });

=head2 Dealing with errors

To be notified of errors (which can occur at connect time or thereafter), 
register a callback as follows:

 $subscriber->reg_cb(error => sub {
    my ($subscriber, $errmsg) = @_;
    # ...
 });

B<WARNING:> As with all AnyEvent modules, B<you must not die() in a callback!> 

=head2 Unsubscribing

To unsubscribe, just undef the subscriber handle.  Reusing handles for
subsequent subscriptions is not supported.  Even though the wire protocol
technically supports it, trust me, it's better this way :-).

=cut

sub subscribe {
    my ($class, %args) = @_;
    
    $args{host} or croak "Missing host";
    $args{channel} or $args{pattern} or croak "Missing channel/pattern";
    $args{channel} and $args{pattern} and croak "Both pattern and channel specified";
    $args{port} ||= 6379;

    my $self = $class->SUPER::new(%args);
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
                        my ($handle, $errmsg) = @_;
                        if ($errmsg) {
                            $self->{handle}->destroy;
                            $self->event('error', $errmsg);
                        } else {
                            $self->_subscribe;
                        }
                });
            } else {
                $self->_subscribe;
            }
        },
        on_connect_error => sub { 
            $self->event('error', $_[1]);
        },
        on_error => sub { 
            $self->{handle}->destroy; 
            $self->event('error', $_[2]);
        }, 
    );

    return $self;
}

sub _subscribe {
    my $self = shift;
    if ($self->{pattern}) {
        $self->{handle}->push_write('AnyEvent::Redis2::Protocol', 
                                    PSUBSCRIBE => $self->{pattern});
    } else {
        $self->{handle}->push_write('AnyEvent::Redis2::Protocol', 
                                    SUBSCRIBE => $self->{channel});
    }
    $self->{handle}->push_read('AnyEvent::Redis2::Protocol' => sub {
            my ($handle, $errmsg, @values) = @_;
            if ($errmsg) { 
                $self->event('error', $errmsg);
            } else {
                if (($self->{channel} && $values[0] eq 'subscribe' && $values[1] eq $self->{channel})
                    || ($self->{pattern} && $values[0] eq 'psubscribe' && $values[1] eq $self->{pattern})) {
                    $self->{handle}->on_read(sub {
                            $self->{handle}->push_read('AnyEvent::Redis2::Protocol' => sub {
                                    if ($_[2] eq 'message') {
                                        $self->event('message', $_[3], $_[4]);
                                    } elsif ($_[2] eq 'pmessage') {
                                        $self->event('message', $_[4], $_[5]);
                                    }
                            });
                    });
                } else {
                    $self->event('error', 'Unexpected response to [P]SUBSCRIBE command');
                }
            }
    });
}

=head1 SEE ALSO

L<AnyEvent::Redis2>, Redis PublishSubscribe
L<http://code.google.com/p/redis/wiki/PublishSubscribe>

=head1 AUTHOR

Michael S. Fischer <michael+cpan@dynamine.net>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 Michael S. Fischer

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;

__END__

# vim:syn=perl:ts=4:sw=4:et:ai
