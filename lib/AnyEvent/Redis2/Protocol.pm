package AnyEvent::Redis2::Protocol;

use common::sense;

=head1 NAME

AnyEvent::Redis2::Protocol - generates and parses Redis messages

=head1 DESCRIPTION

This package should not be directly used.  It provides AnyEvent write and read
types capable of generating Redis requests and parsing replies.

=head1 SEE ALSO

L<AnyEvent::Handle>,
Redis Protocol Specification L<http://code.google.com/p/redis/wiki/ProtocolSpecification>

=cut

sub anyevent_write_type {
    my ($handle, @args) = @_;

    use bytes;
    return "*" . scalar @args . "\015\012" .
          join("\015\012", map { '$' . length($_) . "\015\012" . $_ } @args) .
          "\015\012";
}

sub anyevent_read_type {
    my ($handle, $cb) = @_;
    return sub {
        $handle->push_read(line => sub {
            my $line = $_[1];
            if ($line =~ /^\*(-?\d+)/) {
                my $nexpected = $1;
                if ($nexpected == -1) {
                    $cb->($handle, undef, undef);
                } else {
                    my $values = [];
                    for (my $i = 0; $i < $nexpected; $i++) {
                        $handle->push_read('AnyEvent::Redis2::Protocol' => sub {
                                my ($handle, $errmsg, $value) = @_;
                                push @$values, $value;
                                if (scalar @$values == $nexpected) {
                                    $cb->($handle, undef, @$values);
                                }
                        });
                    }
                }
            } elsif ($line =~ /^[\+:](.*)/) {
                # Single line/integer reply
                $cb->($handle, undef, $1);
            } elsif ($line =~ /^-(.*)/) {
                # Single-line error reply
                $cb->($handle, $1);
            } elsif ($line =~ /^\$(-?\d+)/) {
                # Bulk reply
                my $length = $1;
                if ($length == -1) {
                    $cb->($handle, undef, undef);
                } else {
                    # We need to read 2 bytes more than the length (stupid 
                    # CRLF framing).  Then we need to discard them.
                    $handle->unshift_read(chunk => $length + 2, sub {
                        use bytes;
                        my $data = $_[1];
                        $cb->($handle, undef, substr($data, 0, $length));
                    });
                }
            }
        });
        1;
    };
}

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
