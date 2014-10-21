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
        use bytes;
        $handle->push_read(line => sub {
            my $line = $_[1];
            my $type = substr($line, 0, 1);
            my $value = substr($line, 1);
            if ($type eq '*') {
                # Multi-bulk reply 
                my $remaining = $value;
                if ($remaining == 0) {
                    $cb->([]);
                } elsif ($remaining == -1) {
                    $cb->(undef);
                } else {
                    my $results = [];
                    $handle->push_read(sub {
                        my $need_more_data = 0;
                        do {
                            if ($handle->{rbuf} =~ /^(\$(-?\d+)\015\012)/) {
                                my ($match, $vallen) = ($1, $2);
                                if ($vallen == -1) {
                                    # Delete the bulk header.
                                    substr($handle->{rbuf}, 0, length($match), '');
                                    push @$results, undef;
                                    $remaining--;
                                    unless ($remaining) {
                                        $cb->($results);
                                        return 1;
                                    }
                                } elsif (length $handle->{rbuf} >= (length($match) + $vallen + 2)) {
                                    # OK, we have enough in our buffer.
                                    # Delete the bulk header.
                                    substr($handle->{rbuf}, 0, length($match), '');
                                    push @$results, substr($handle->{rbuf}, 0, $vallen, '');
                                    $remaining--;
                                    # Delete trailing data characters.
                                    substr($handle->{rbuf}, 0, 2, '');
                                    unless ($remaining) {
                                        $cb->($results);
                                        return 1;
                                    }
                                } else {
                                    $need_more_data = 1;
                                }
                            } elsif ($handle->{rbuf} =~ s/^([\+\-:])([^\015\012]*)\015\012//) {
                                my ($type, $value) = ($1, $2);
                                if ($type eq '+' || $type eq ':') {
                                    push @$results, $value;
                                    $remaining--;
                                    unless ($remaining) {
                                        $cb->($results);
                                        return 1;
                                    }
                                } elsif ($type eq '-') {
                                    # Error - abort early
                                    $cb->($value, 1);
                                    return 1;
                                }
                            } else {
                                # Nothing matched - read more...
                                $need_more_data = 1;
                            }
                        } until $need_more_data;
                        return undef; # get more data
                    });
                }
            } elsif ($type eq '+' || $type eq ':') {
                # Single line/integer reply
                $cb->($value);
            } elsif ($type eq '-') {
                # Single-line error reply
                $cb->($value, 1);
            } elsif ($type eq '$') {
                # Bulk reply
                if ($value == -1) {
                    $cb->(undef);
                } else {
                    # We need to read 2 bytes more than the length (stupid 
                    # CRLF framing).  Then we need to discard them.
                    $handle->unshift_read(chunk => $value + 2, sub {
                        my $data = $_[1];
                        $cb->(substr($data, 0, $value));
                    });
                }
            }
            return 1;
        });
        return 1;
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
