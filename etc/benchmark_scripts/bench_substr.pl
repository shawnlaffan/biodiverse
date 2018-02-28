
use Benchmark qw {:all};
use 5.016;
use Data::Dumper;

local $| = 1;

say substr_only('P_BARRY');
say substr_and_concat('P_BARRY');
say regex_it('P_BARRY');

cmpthese (
    -5,
    {
        substr_only       => sub {substr_only ('P_BARRY')},
        substr_and_concat => sub {substr_and_concat ('P_BARRY')},
        regex             => sub {regex_it ('P_BARRY')},
    }
);


sub substr_only {
    my $name = shift;
    substr ($name, 0, 1) = 'C';
    substr ($name, 0, 1) = 'Q';
    #$name;
}

sub substr_and_concat {
    my $name = shift;
    my $namex = substr $name, 1;
    my $name2 = "C$namex";
    my $name3 = "Q$namex";
    #$name3;
}

sub regex_it {
    my $name = shift;
    my $namex = $name;
    $namex =~ s/^P//;
    my $name2 = "C$namex";
    my $name3 = "Q$namex";
    #$name3;
}



__END__

