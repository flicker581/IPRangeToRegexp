#!/usr/bin/perl

use strict;
use warnings;

# Include modules from the directory of the script 
BEGIN {
    use FindBin;
    push @INC, $FindBin::Bin;
}

use IPRangeToRegexp;

# Perform internal test
IPRangeToRegexp::test();

print "\n";
print regexp_from_iprange( '10.0.0.0', '10.1.255.253', {loose_ip=>1} ) . "\n\n";

print regexp_from_ipsubnet( '10.10.192.0/18', {loose_ip=>1} ) . "\n\n";

use IPToDomain;

print domain_from_ip( '10.11.12.134' ) . "\n\n";
