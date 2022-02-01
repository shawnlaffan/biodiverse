use strict;
use warnings;

use 5.010;

my $toc_leader  = '**Table of contents:**';
my $re_toc_leader = qr /\*{2}Table of contents:?\*{2}:?/;
my $header_flag = 'XXXXXXXXHEADERGOESHEREXXXXXX';

my @files = glob '*.md';

foreach my $file (@files) {
    next if $file =~/^_/;

    open (my $fh, '<', $file) or die "Cannot open $file";
    #say $file;

    my $full_file;
    my $changed;
    my @headers;
    my ($in_code_block, $in_header);

    while (my $line = <$fh>) {
        if ($line =~ /$re_toc_leader/) {
            $in_header = !$in_header;
            $full_file .= $header_flag;
        }
        if (!$in_header) {
            $full_file .= $line;
        }
        if ($in_header && $line =~ /^\s*$/) {
            $in_header = !$in_header;
        }

        if (!$in_code_block && $line =~ /^#/) {
            push @headers, $line;
        }
        elsif ($line =~ /```/) {
            $in_code_block = !$in_code_block;
        }        
    }
    
    $fh->close;

    if (scalar @headers > 1) {
        say "\n\n---  $file ---\n";
        my $header_block = "$toc_leader\n";

        foreach my $header (@headers) {
            $header =~ s/[\n\r]+$//;
            my ($anchor, $header_text, $indent);

            if ($header =~ /^#{1}\s/) {
                $indent = '';
            }
            elsif ($header =~ /^#{2}\s/) {
                $indent = ' ' x 2;
            }
            elsif ($header =~ /^#{3}\s/) {
                $indent = ' ' x 4;
            }
            elsif ($header =~ /^#{4}\s/) {
                $indent = ' ' x 6;
            }
            $anchor .= convert_header_to_anchor($header);

            $header_text = $header;
            $header_text =~ s/^#+\s+//;  #  strip off any heading markdown
            $header_text =~ s/\s+#+$//;

            $header_block .= "$indent\* \[$header_text\]($anchor)\n";
        }
        $header_block .= "\n";

        $full_file =~ s/$header_flag/$header_block/;

        open(my $ofh, '>', $file) or die "Cannot open $file to write to";
        print {$ofh} $full_file;
    }
    
}


#  https://github.com/gitlabhq/gitlabhq/blob/master/doc/markdown/markdown.md#header-ids-and-links
sub convert_header_to_anchor {
    my $header = shift;
    $header = lc $header;
    $header =~ s/^#+\s+//;
    $header =~ s/\s+#+$//;
    $header =~ s/\.//g;  #  URL above seems incorrect about this one
    $header =~ s/[^a-z0-9_-]/-/g;
    $header =~ s/-+/-/g;
    $header =~ s/-+$//;

    return '#' . $header;
}

