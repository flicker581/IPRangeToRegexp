#!/usr/bin/perl

package IPToDomain;

=head1 IPToDomain
Данный пакет предназначен для сопоставления имён "доменов" адресам IP.

Сопоставление подсетей и доменов считывается из файла IPToDomain.map.

=cut

use strict;
use warnings;

BEGIN {
    use Exporter ();
    our $VERSION = '1.0';
    our @ISA = qw(Exporter);
    our @EXPORT = qw( &domain_from_ip );
}

use IPRangeToRegexp;

require "IPToDomain.map";

our %ipsubnet_to_domain;

my %subnet_to_regex;

INIT {
    our %ipsubnet_to_domain;
    foreach my $subnet ( keys %ipsubnet_to_domain ) {
	eval {
	    my $r = '^(?:' . regexp_from_ipsubnet( $subnet, { loose_ip => 0 } ) . ')$';
	    $subnet_to_regex{ $subnet } = qr/$r/ ;
	}
    }
}

#use re 'debug';

sub domain_from_ip ($) {
    my ( $ip ) = @_;

    foreach my $subnet ( keys %subnet_to_regex ) {
#	print $r . "\n";
	if ( $ip =~ $subnet_to_regex{$subnet} ) {
	    return $ipsubnet_to_domain{$subnet};
	}
    }
    return undef;
}

1;
