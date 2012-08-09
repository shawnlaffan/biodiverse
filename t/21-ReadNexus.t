#!/usr/bin/perl -w
use strict;
use warnings;
use Data::Section::Simple qw(get_data_section);


use Test::More tests => 23;

local $| = 1;

use mylib;

use Biodiverse::ReadNexus;
use Biodiverse::Tree;

#  from Statistics::Descriptive
sub is_between
{
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    
    my ($have, $want_bottom, $want_top, $blurb) = @_;

    ok (
        (($have >= $want_bottom) &&
        ($want_top >= $have)),
        $blurb
    );
}


my $tol = 1E-13;

#  clean read of 'neat' nexus file
{
    my $nex_tree = get_nex_tree();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $nex_tree);
    };

    is ($result, 1, 'import nexus trees, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 2, 'two trees extracted');

    my $tree = $trees[0];

    run_tests ($tree);
}


#  clean read of working newick file
{
    my $data = get_newick_tree();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };

    is ($result, 1, 'import clean newick trees, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 1, 'one tree extracted');

    my $tree = $trees[0];

    run_tests ($tree);
}

{
    my $data = get_tabular_tree();

    my $trees = Biodiverse::ReadNexus->new;
    my $result = eval {
        $trees->import_data (data => $data);
    };

    is ($result, 1, 'import clean tabular tree, no remap');

    my @trees = $trees->get_tree_array;

    is (scalar @trees, 1, 'one tree extracted');

    my $tree = $trees[0];

    run_tests ($tree);
}



#  read of a 'messy' nexus file with no newlines
SKIP:
{
    skip 'No system parses nexus trees with no newlines', 2;
    my $data = get_nex_tree();

    #  eradicate newlines
    $data =~ s/[\r\n]+//gs;
    #print $data;
  TODO:
    {
        local $TODO = 'issue 149';

        my $trees = Biodiverse::ReadNexus->new;
        my $result = eval {
            $trees->import_data (data => $data);
        };
    
        is ($result, 1, 'import nexus trees, no newlines, no remap');
    
        my @trees = $trees->get_tree_array;
    
        is (scalar @trees, 2, 'two trees extracted');
    
        my $tree = $trees[0];

        #run_tests ($tree);
    }
}



sub run_tests {
    my $tree = shift;

    my @tests = (
        {sub => 'get_node_count',    ex => 61,},
        {sub => 'get_tree_depth',    ex => 12,},
        {sub => 'get_tree_length',   ex => 0.992769230769231,},
        {sub => 'get_length_to_tip', ex => 0.992769230769231,},

        {sub => 'get_total_tree_length',  ex => 21.1822419987155,},    
    );

    foreach my $test (@tests) {
        my $sub   = $test->{sub};
        my $upper = $test->{ex} + $tol;
        my $lower = $test->{ex} - $tol;
        my $msg = "$sub expected $test->{ex}";

        #my $val = $tree->$sub;
        #warn "$msg, $val\n";

        is_between (eval {$tree->$sub}, $lower, $upper, $msg);
    }

    return;    
}

sub get_nex_tree {
    return get_data_section('NEXUS_TREE');
}

sub get_newick_tree {
    return get_data_section('NEWICK_TREE');
}

sub get_tabular_tree {
    return get_data_section('TABULAR_TREE');
}

__DATA__

@@ NEWICK_TREE
(((((((((((44:0.6,47:0.6):0.077662337662338,(18:0.578947368421053,58:0.578947368421053):0.098714969241285):0.106700478344225,31:0.784362816006563):0.05703610742759,(6:0.5,35:0.5):0.341398923434153):0.03299436960061,(((((1:0.434782608695652,52:0.434782608695652):0.051317777404734,57:0.486100386100386):0.11249075347436,22:0.598591139574746):0.0272381982058111,46:0.625829337780557):0.172696292660468,(7:0.454545454545455,9:0.454545454545455):0.34398017589557):0.075867662593738):0.057495084175743,((4:0,25:0):0.666666666666667,16:0.666666666666667):0.265221710543839):0.026396763298318,((0:0.789473684210526,12:0.789473684210526):0.111319966583125,(15:0.6,30:0.6):0.300793650793651):0.0574914897151729):0.020427284632173,48:0.978712425140997):0.00121523842637206,(24:0.25,55:0.25):0.729927663567369):0.00291112550535999,((((38:0.461538461538462,13:0.461538461538462):0.160310277957336,(50:0.166666666666667,59:0.166666666666667):0.455182072829131):0.075519681556834,32:0.697368421052632):0.258187134502923,2:0.955555555555555):0.027283233517174):0.00993044169650192,42:0.992769230769231):0;

@@ NEXUS_TREE
#NEXUS
[ID: blah blah]
begin trees;
	[this is a comment with a semicolon ; ]
	Translate 
		0 'Genus:sp9',
		1 'Genus:sp23',
		2 'Genus:sp13',
		3 '18___',
		4 'Genus:sp28',
		5 '15___',
		6 'Genus:sp26',
		7 'Genus:sp21',
		8 '22___',
		9 'Genus:sp18',
		10 '17___',
		11 '26___',
		12 'Genus:sp8',
		13 'Genus:sp3',
		14 '1___',
		15 'Genus:sp14',
		16 'Genus:sp27',
		17 '13___',
		18 'Genus:sp15',
		19 '5___',
		20 '16___',
		21 '6___',
		22 'Genus:sp29',
		23 '23___',
		24 'Genus:sp24',
		25 'Genus:sp31',
		26 '8___',
		27 '0___',
		28 '29___',
		29 '25___',
		30 'Genus:sp16',
		31 'Genus:sp10',
		32 'Genus:sp4',
		33 '21___',
		34 '10___',
		35 'Genus:sp20',
		36 '27___',
		37 '20___',
		38 'Genus:sp2',
		39 '28___',
		40 '24___',
		41 '11___',
		42 'Genus:sp22',
		43 '4___',
		44 'Genus:sp19',
		45 '7___',
		46 'Genus:sp12',
		47 'Genus:sp5',
		48 'Genus:sp17',
		49 '3___',
		50 'Genus:sp6',
		51 '9___',
		52 'Genus:sp30',
		53 '19___',
		54 '2___',
		55 'Genus:sp25',
		56 '12___',
		57 'Genus:sp11',
		58 'Genus:sp1',
		59 'Genus:sp7',
		60 '14___'
		;
	Tree 'Example_tree1' = (((((((((((44:0.6,47:0.6):0.077662337662338,(18:0.578947368421053,58:0.578947368421053):0.098714969241285):0.106700478344225,31:0.784362816006563):0.05703610742759,(6:0.5,35:0.5):0.341398923434153):0.03299436960061,(((((1:0.434782608695652,52:0.434782608695652):0.051317777404734,57:0.486100386100386):0.11249075347436,22:0.598591139574746):0.0272381982058111,46:0.625829337780557):0.172696292660468,(7:0.454545454545455,9:0.454545454545455):0.34398017589557):0.075867662593738):0.057495084175743,((4:0,25:0):0.666666666666667,16:0.666666666666667):0.265221710543839):0.026396763298318,((0:0.789473684210526,12:0.789473684210526):0.111319966583125,(15:0.6,30:0.6):0.300793650793651):0.0574914897151729):0.020427284632173,48:0.978712425140997):0.00121523842637206,(24:0.25,55:0.25):0.729927663567369):0.00291112550535999,((((38:0.461538461538462,13:0.461538461538462):0.160310277957336,(50:0.166666666666667,59:0.166666666666667):0.455182072829131):0.075519681556834,32:0.697368421052632):0.258187134502923,2:0.955555555555555):0.027283233517174):0.00993044169650192,42:0.992769230769231):0;
        Tree 'Example_tree2' = (((((((((((44:0.6,47:0.6):0.077662337662338,(18:0.578947368421053,58:0.578947368421053):0.098714969241285):0.106700478344225,31:0.784362816006563):0.05703610742759,(6:0.5,35:0.5):0.341398923434153):0.03299436960061,(((((1:0.434782608695652,52:0.434782608695652):0.051317777404734,57:0.486100386100386):0.11249075347436,22:0.598591139574746):0.0272381982058111,46:0.625829337780557):0.172696292660468,(7:0.454545454545455,9:0.454545454545455):0.34398017589557):0.075867662593738):0.057495084175743,((4:0,25:0):0.666666666666667,16:0.666666666666667):0.265221710543839):0.026396763298318,((0:0.789473684210526,12:0.789473684210526):0.111319966583125,(15:0.6,30:0.6):0.300793650793651):0.0574914897151729):0.020427284632173,48:0.978712425140997):0.00121523842637206,(24:0.25,55:0.25):0.729927663567369):0.00291112550535999,((((38:0.461538461538462,13:0.461538461538462):0.160310277957336,(50:0.166666666666667,59:0.166666666666667):0.455182072829131):0.075519681556834,32:0.697368421052632):0.258187134502923,2:0.955555555555555):0.027283233517174):0.00993044169650192,42:0.992769230769231):0;
end;


@@ TABULAR_TREE
Element	Axis_0	LENGTHTOPARENT	NAME	NODE_NUMBER	PARENTNODE	TREENAME
1	1	0		1	0	'Example_tree'
10	10	0.106700478		10	9	'Example_tree'
11	11	0.077662338		11	10	'Example_tree'
12	12	0.6	Genus:sp19	12	11	'Example_tree'
13	13	0.6	Genus:sp5	13	11	'Example_tree'
14	14	0.098714969		14	10	'Example_tree'
15	15	0.578947368	Genus:sp15	15	14	'Example_tree'
16	16	0.578947368	Genus:sp1	16	14	'Example_tree'
17	17	0.784362816	Genus:sp10	17	9	'Example_tree'
18	18	0.341398923		18	8	'Example_tree'
19	19	0.5	Genus:sp26	19	18	'Example_tree'
2	2	0.009930442		2	1	'Example_tree'
20	20	0.5	Genus:sp20	20	18	'Example_tree'
21	21	0.075867663		21	7	'Example_tree'
22	22	0.172696293		22	21	'Example_tree'
23	23	0.027238198		23	22	'Example_tree'
24	24	0.112490753		24	23	'Example_tree'
25	25	0.051317777		25	24	'Example_tree'
26	26	0.434782609	Genus:sp23	26	25	'Example_tree'
27	27	0.434782609	Genus:sp30	27	25	'Example_tree'
28	28	0.486100386	Genus:sp11	28	24	'Example_tree'
29	29	0.59859114	Genus:sp29	29	23	'Example_tree'
3	3	0.002911126		3	2	'Example_tree'
30	30	0.625829338	Genus:sp12	30	22	'Example_tree'
31	31	0.343980176		31	21	'Example_tree'
32	32	0.454545455	Genus:sp21	32	31	'Example_tree'
33	33	0.454545455	Genus:sp18	33	31	'Example_tree'
34	34	0.265221711		34	6	'Example_tree'
35	35	0.666666667		35	34	'Example_tree'
36	36	0	Genus:sp28	36	35	'Example_tree'
37	37	0	Genus:sp31	37	35	'Example_tree'
38	38	0.666666667	Genus:sp27	38	34	'Example_tree'
39	39	0.05749149		39	5	'Example_tree'
4	4	0.001215238		4	3	'Example_tree'
40	40	0.111319967		40	39	'Example_tree'
41	41	0.789473684	Genus:sp9	41	40	'Example_tree'
42	42	0.789473684	Genus:sp8	42	40	'Example_tree'
43	43	0.300793651		43	39	'Example_tree'
44	44	0.6	Genus:sp14	44	43	'Example_tree'
45	45	0.6	Genus:sp16	45	43	'Example_tree'
46	46	0.978712425	Genus:sp17	46	4	'Example_tree'
47	47	0.729927664		47	3	'Example_tree'
48	48	0.25	Genus:sp24	48	47	'Example_tree'
49	49	0.25	Genus:sp25	49	47	'Example_tree'
5	5	0.020427285		5	4	'Example_tree'
50	50	0.027283234		50	2	'Example_tree'
51	51	0.258187135		51	50	'Example_tree'
52	52	0.075519682		52	51	'Example_tree'
53	53	0.160310278		53	52	'Example_tree'
54	54	0.461538462	Genus:sp2	54	53	'Example_tree'
55	55	0.461538462	Genus:sp3	55	53	'Example_tree'
56	56	0.455182073		56	52	'Example_tree'
57	57	0.166666667	Genus:sp6	57	56	'Example_tree'
58	58	0.166666667	Genus:sp7	58	56	'Example_tree'
59	59	0.697368421	Genus:sp4	59	51	'Example_tree'
6	6	0.026396763		6	5	'Example_tree'
60	60	0.955555556	Genus:sp13	60	50	'Example_tree'
61	61	0.992769231	Genus:sp22	61	1	'Example_tree'
7	7	0.057495084		7	6	'Example_tree'
8	8	0.03299437		8	7	'Example_tree'
9	9	0.057036107		9	8	'Example_tree'
