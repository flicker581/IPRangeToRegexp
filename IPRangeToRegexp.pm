#!/usr/bin/perl

package IPRangeToRegexp;

=head1 IPRangeToRegexp
Данный пакет предназначен для преобразования диапазонов адресов IPv4 
в регулярные выражения, совпадающие со всеми IP из данного диапазона.

=cut

use strict;
use warnings;

BEGIN {
    use Exporter ();
    our $VERSION = '1.0';
    our @ISA = qw(Exporter);
    our @EXPORT = qw( &regexp_from_iprange &regexp_from_ipsubnet );
}


=head2 Параметры
Параметры передаются процедурам в виде ссылки на хэш в последнем необязательном
аргументе.

Режим loose_ip генерирует более краткие регулярные выражения, но за счёт
ослабленной проверки входных данных. В этом режиме, регулярное выражение может
совпадать с невалидным адресом IP.

Адрес IP в канонической форме состоит из 4-х целых чисел от 0 до 255, разделённых
точками. Числа не могут иметь нулей в начале, за исключение числа "0".

В режиме loose_ip выражение может ошибочно совпасть:

    1. С адресом, некоторые октеты в котором начинаются с 0.
    2. С адресами, содержащими числа более 255.

Стиль re_style определяет, какой синтаксис регулярных выражений будет использован.
Для Perl мы отключаем сохранение совпадений и для читаемости применяем '\d'.

Стиль egrep подходит также и для Perl, но менее эффективен.

=cut

my %default_param = (
    loose_ip => 0,
    re_style => 'perl',
);

my %perl_param = (
    re_digit => '\d',
    re_lbracket => '(?:',
    re_rbracket => ')',
);

my %egrep_param = (
    re_digit => '[0-9]',
    re_lbracket => '(',
    re_rbracket => ')',
);

use Data::Dumper;

sub ceil9 ($) {
    my ( $a ) = @_;
    return '9' x length($a);
}

sub floor9 ($) {
    my ( $a ) = @_;
    return '0' x length($a);
}

sub expand_tree ($);

sub expand_tree ($) {
    my ( $leaf ) = @_;

    my ( $a, $b ) = ( $leaf->{a}, $leaf->{b} );

# Разбиваем все интервалы на отрезки с концами, выражаемыми числами равной длины
    if ( length( $a ) < length ( $b ) ) {
        $leaf->{l} = { a => $a, b => ceil9( $a ) };
        $leaf->{r} = { a => ceil9( $a ) + 1, b => $b };
    }
    
# Разбиваем на диапазоны, отличающиеся одной цифрой
    if ( !defined( $leaf->{l} ) ) {
#	print Dumper($leaf);
	die "Internal error; number of digits should be equal" unless length( $a ) == length( $b );

	my ( $comm, $diff_a, $diff_b, $tail_a, $tail_b ) = ( '', '', '', '', '' );
	for ( my $i = 0; $i < length($a); $i++ ) {
	    my $char_a = substr( $a, $i, 1 );
	    my $char_b = substr( $b, $i, 1 );
	    if ( $diff_a eq '' ) {
		if ( $char_a eq $char_b ) {
		    # This is common part of two numbers
		    $comm .= $char_a;
		} else {
		    # This is first symbol of the difference
		    $diff_a = $char_a;
		    $diff_b = $char_b;
		}
	    } else {
		# These are part after first different character
		$tail_a .= $char_a;
		$tail_b .= $char_b;
	    }
	}
	$leaf->{common} = $comm;
	$leaf->{diff_a} = $diff_a;
	$leaf->{diff_b} = $diff_b;
	$leaf->{tail_a} = $tail_a;
	$leaf->{tail_b} = $tail_b;

	if ( length( $tail_a ) > 0 ) {
	    my ( $l_b, $r_a );
	    if ( $tail_a !~ /^0*$/ ) {
		# left expand
		$l_b = $comm . $diff_a . ( ceil9( $tail_a ) );
		$r_a = $l_b + 1;
	    } elsif ( $tail_b !~ /^9*$/ ) {
		# right expand
		$r_a = $comm . $diff_b . ( floor9( $tail_b ) );
		$l_b = $r_a - 1;
	    }
	    if ( defined( $l_b ) ) {
		$leaf->{l} = { a => $a, b => $l_b };
		$leaf->{r} = { a => $r_a, b => $b };
	    }
	}
    }

    if ( defined( $leaf->{l} ) ) {
	expand_tree( $leaf->{l} );
	expand_tree( $leaf->{r} );

    }
}

sub regexp_from_tree ($$);

# Генерация регулярного выражения из дерева
sub regexp_from_tree ($$) {
    my ( $leaf, $p ) = @_;

    if ( defined( $leaf->{l} ) ) {
	return regexp_from_tree( $leaf->{l}, $p ) . '|' . regexp_from_tree( $leaf->{r}, $p );
    }

    my $regex = $leaf->{common};

    if ( $leaf->{diff_a} eq '' ) {
	# Do nothing
    }
    elsif ( $leaf->{diff_b} eq '9' and $leaf->{diff_a} eq '0' ) {
	# Optimization for one digit
	$regex .= $p->{re_digit};
    }
    elsif ( $leaf->{diff_b} eq '9' and $leaf->{diff_a} eq '1' 
	and $p->{loose_ip} and $regex eq '' and $leaf->{tail_a} ne '' ) {
	# First digit supposedly cannot be zero, but in loose mode only
	$regex .= $p->{re_digit};
    }
    elsif ( $leaf->{diff_b} - $leaf->{diff_a} > 1 ) {
	# Range of digits
	$regex .= '[' . $leaf->{diff_a} . '-' . $leaf->{diff_b} . ']';
    }
    else {
	# Only one of two digits
	$regex .= '[' . $leaf->{diff_a} . $leaf->{diff_b} . ']';
    }
    # Fill with any digits
    $regex .= $p->{re_digit} x length( $leaf->{tail_a} );
    return $regex;
}

sub regexp_from_range ($$;$) {
    my ( $a, $b, $p ) = @_;

    regexp_set_defaults( \$p );

    # Make sure the range is defined numerically and without leading zeroes
    die "Incorrect range specification"
	unless $a eq int($a) and $b eq int($b);

    if ( $p->{loose_ip} && $b == 255 ) {
	if ( $a == 0 ) {
	    # Loose optimization for whole digit
	    return $p->{re_digit} . '+';
	}
	# Loose optimization
	$b = 299;
    }

    my $tree = { a => $a, b => $b };
    #print Dumper($tree);

    expand_tree($tree);

    #print Dumper( $tree );

    my $regex = regexp_from_tree( $tree, $p );
    return $regex;
}

=pod
Некоторые диапазоны требуется предварительно разбить на поддиапазоны. Пример:

10.110.176.10-10.110.186.15
=> left split =>
10.110.176.10-10.110.176.255, 10.110.177.0-10.110.186.15
=> right split =>
10.110.176.10-10.110.176.255, 10.110.177.0-10.110.185.255, 10.110.186.0-10.110.186.15

=cut

sub expand_iptree ($);

sub expand_iptree ($) {
    my ( $leaf ) = @_;
    die if !defined( $leaf );

    my $common = 0;
    my $split;
    # Iterate octets
    OCTET: for ( my $i = 0; $i < 4; $i ++ ) {
	my $octet_a = $leaf->{a}->[$i];
	my $octet_b = $leaf->{b}->[$i];
	# while octets are identical, increment $common counter
	if ( $common == $i ) {
	    if ( $octet_a eq $octet_b ) {
		$common++;
	    }
	    next OCTET;
	} else {
	    # Now analyzing octets after first difference.
	    # Check if we need to split range from the left or right.
	    # This happens when after non-matching octet there is a non-zero octet.
    	    if ( $octet_a ne '0' ) {
		$split = 'left';
		last OCTET;
	    } elsif ( $octet_b ne '255' ) {
		$split = 'right';
		last OCTET;
	    } else {
		next OCTET;
	    }
	}
    }

    $leaf->{common_octets} = $common;

    if ( defined( $split ) ) {
	my @l_b;
	my @r_a;
	for ( my $j = 0; $j < 4; $j++ ) {
	    if ( $j < $common ) {
	        push @l_b, $leaf->{a}->[$j];
		push @r_a, $leaf->{a}->[$j];
	    } elsif ( $j == $common and $split eq 'left' ) {
	        push @l_b, $leaf->{a}->[$j];
	        push @r_a, $leaf->{a}->[$j] + 1;
	    } elsif ( $j == $common and $split eq 'right' ) {
	        push @l_b, $leaf->{b}->[$j] - 1;
	        push @r_a, $leaf->{b}->[$j];
	    } else {
	        push @l_b, '255';
	        push @r_a, '0';
	    }
	}

	$leaf->{l} = { a => $leaf->{a}, b => \@l_b };
	$leaf->{r} = { a => \@r_a, b => $leaf->{b} };
	expand_iptree( $leaf->{l} );
	expand_iptree( $leaf->{r} );
    }
}

sub regexp_from_iptree ($$);

sub regexp_from_iptree ($$) {
    my ( $leaf, $p ) = @_;

    if ( defined( $leaf->{l} ) ) {
	return regexp_from_iptree( $leaf->{l}, $p ) . '|' . regexp_from_iptree( $leaf->{r}, $p );
    }

#    print Dumper( $leaf );
    my @regex;
    for ( my $i = 0; $i < 4 ;$i++ ) {
	if ( $i < $leaf->{common_octets} ) { 
	    push @regex, $leaf->{a}->[$i];
	} elsif ( $i == $leaf->{common_octets} ) {
	    push @regex, regexp_from_range( $leaf->{a}->[$i], $leaf->{b}->[$i], $p );
	} else {
	    push @regex, regexp_from_range( 0, 255, $p );
	}
	if ( $regex[$i] =~ /\|/ ) {
	    $regex[$i] = $p->{re_lbracket} . $regex[$i] . $p->{re_rbracket};
	}
    }
    
    my $regex = join( '\.', @regex );

    return $regex;
}

sub regexp_set_defaults ($) {
    my ( $pp ) = @_;

    $$pp = {} unless ref( $$pp ) eq 'HASH';
    my $p = $$pp;
    foreach my $k ( keys %default_param ) {
	$p->{$k} = $default_param{$k} unless exists $p->{$k};
    }
    if ( $p->{re_style} eq 'perl' ) {
	foreach my $k ( keys %perl_param ) {
	    $p->{$k} = $perl_param{$k} unless exists $p->{$k};
	}
    } elsif ( $p->{re_style} eq 'egrep' ) {
	foreach my $k ( keys %egrep_param ) {
	    $p->{$k} = $egrep_param{$k} unless exists $p->{$k};
	}
    } else {
	die 'Unknown regexp style';
    }

}

=item regexp_from_iprange( $range_start, $range_finish[, { parameter => value ... } ] )
Возвращает: регулярное выражение в виде строки.
Аргументы: начало диапазона, конец диапазона, параметры

=cut

sub regexp_from_iprange ($$;$) {
    my ( $a, $b, $p ) = @_;

    regexp_set_defaults( \$p );

    my @a = split /\./, $a;
    my @b = split /\./, $b;

    my $iptree = { a => \@a, b => \@b };
    expand_iptree( $iptree );

    my $regex = regexp_from_iptree( $iptree, $p );
    return $regex;
}

sub inet_ntoa ($) {
    my ( $n_addr ) = @_;
    my @s;
    for ( my $i = 3; $i >= 0; $i-- ) {
	$s[$i] = $n_addr & 255;
	$n_addr >>= 8;
    }
    
    my $addr = join( '.', @s );
    return $addr;
}

sub inet_aton ($) {
    my ( $addr ) = @_;

    my $n_addr = 0;

    my @s = split( /\./, $addr );
    die 'Invalid IP' unless @s == 4;

    foreach my $octet ( @s ) {
	$n_addr = ( $n_addr << 8 ) | $octet;
    }
    return $n_addr;
}

=item regexp_from_ipsubnet( $subnet[, { parameter => value ... } ] )
Возвращает: регулярное выражение в виде строки.
Аргументы: подсеть в нотации CIDR, параметры

=cut
sub regexp_from_ipsubnet ($;$) {
    my ( $subnet, $p ) = @_;
    my ( $addr, $mask_len ) = split( /\//, $subnet );
    $mask_len = 32 unless defined $mask_len;

    die 'Invalid netmask' if $mask_len < 0 or $mask_len > 32;

    my $n_addr = inet_aton( $addr );
    my $inv_mask = ( 2 ** ( 32 - $mask_len ) - 1 );

    my ( $a_addr, $b_addr ) = ( $n_addr & ~ $inv_mask, $n_addr | $inv_mask );

    my ( $a, $b ) = ( inet_ntoa( $a_addr ), inet_ntoa( $b_addr ) );

    return regexp_from_iprange( $a, $b, $p );
}

=item IPRangeToRegexp::test()
Запускается для проверки корректности кода.

=cut
sub test () {

    my @testcase = (
	{ input => '9-255', loose_ip => 0, re_style => 'perl', output => '9|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]' },
	{ input => '0-255', loose_ip => 0, re_style => 'perl', output => '\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5]' },
        { input => '0-255', loose_ip => 1, re_style => 'perl', output => '\d+' },
        { input => '0-255', loose_ip => 0, re_style => 'egrep', output => '[0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5]' },
        { input => '0-255', loose_ip => 1, re_style => 'egrep', output => '[0-9]+' },
        { input => '137-237', loose_ip => 0, re_style => 'perl', output => '13[7-9]|1[4-9]\d|2[0-2]\d|23[0-7]' },
        { input => '137-237', loose_ip => 1, re_style => 'perl', output => '13[7-9]|1[4-9]\d|2[0-2]\d|23[0-7]' },
        { input => '137-237', loose_ip => 0, re_style => 'egrep', output => '13[7-9]|1[4-9][0-9]|2[0-2][0-9]|23[0-7]' },
        { input => '137-237', loose_ip => 1, re_style => 'egrep', output => '13[7-9]|1[4-9][0-9]|2[0-2][0-9]|23[0-7]' },
        { input => '7-100', loose_ip => 0, re_style => 'perl', output => '[7-9]|[1-9]\d|100' },
        { input => '188-188', loose_ip => 0, re_style => 'perl', output => '188' },
    );

    print "Testing single octets\n";

    foreach my $case ( @testcase ) {
        my @r = split /-/, $case->{input};
    
        my $regex = regexp_from_range( $r[0], $r[1], $case );
        print $case->{input} . ' -> ' . $regex . "\n";
        die "WRONG RESULT!" if $case->{output} ne $regex;
    }

    my @iptestcase = (
        { input => '10.0.0.17-10.1.3.255', loose_ip => 0, re_style => 'perl', output => '10\.0\.0\.(?:1[7-9]|[2-9]\d|1\d\d|2[0-4]\d|25[0-5])|10\.0\.(?:[1-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])|10\.1\.[0-3]\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])' },
        { input => '10.0.0.17-10.1.3.255', loose_ip => 1, re_style => 'perl', output => '10\.0\.0\.(?:1[7-9]|[2-9]\d|[12]\d\d)|10\.0\.(?:[1-9]|\d\d|[12]\d\d)\.\d+|10\.1\.[0-3]\.\d+' },
        { input => '10.0.0.0-10.1.3.255', loose_ip => 0, re_style => 'perl', output => '10\.0\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])|10\.1\.[0-3]\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])' },
        { input => '10.0.0.0-10.1.3.255', loose_ip => 1, re_style => 'perl', output => '10\.0\.\d+\.\d+|10\.1\.[0-3]\.\d+' },
        { input => '10.201.192.0-10.201.255.255', loose_ip => 0, re_style => 'perl', output => '10\.201\.(?:19[2-9]|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])' },
        { input => '10.201.192.0-10.201.255.255', loose_ip => 1, re_style => 'perl', output => '10\.201\.(?:19[2-9]|2\d\d)\.\d+' },
        { input => '10.1.0.0-10.9.255.255', loose_ip => 0, re_style => 'perl', output => '10\.[1-9]\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])' },
        { input => '10.221.0.0-10.221.255.255', loose_ip => 0, re_style => 'perl', output => '10\.221\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])' },
        { input => '10.231.0.0-10.231.255.255', loose_ip => 0, re_style => 'perl', output => '10\.231\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])' },
        { input => '10.201.0.0-10.201.127.255', loose_ip => 0, re_style => 'perl', output => '10\.201\.(?:\d|[1-9]\d|1[01]\d|12[0-7])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])' },
        { input => '10.201.128.0-10.201.191.255', loose_ip => 0, re_style => 'perl', output => '10\.201\.(?:12[89]|1[3-8]\d|19[01])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])' },
        { input => '7.0.255.0-11.1.255.255', loose_ip => 0, re_style => 'perl', output => '7\.0\.255\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])|7\.(?:[1-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])|(?:[89]|10)\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])|11\.[01]\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])\.(?:\d|[1-9]\d|1\d\d|2[0-4]\d|25[0-5])' },
    );

    print "Testing IP ranges\n";

    foreach my $case ( @iptestcase ) {
        my @r = split /-/, $case->{input};

        my $regex = regexp_from_iprange ( $r[0], $r[1], $case ) ;

        print $case->{input} . ' -> ' . $regex . "\n";
        die "WRONG RESULT!" if defined( $case->{output} ) and $case->{output} ne $regex;
    }

}

1;
