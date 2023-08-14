
# Assumptions
# - data file is a flat file
# - ... with no field separators ("")
# - ... and line separator is either "\n" or "\r\n"
# - format file is BCP generated format file

use v5.32;
# use strict;
use warnings;
use Fcntl 'SEEK_SET';
use Getopt::Long;
use Term::ANSIColor;
# use Data::Printer;

my %config = (
    frmFile => undef,
    dataFile => undef,
    showTop => 0,
    showTop_first => 1,
    showTop_last => 3,
    no_colored_output => 0,
    search_term => undef,
);

######### FUNCTIONS ########################

sub trim {
   return $_[0] =~ s/^\s+|\s+$//rg;
}

sub print_usage {
    say <<~ "END_USAGE";
    
    USAGE: perl script.pl [-t] [-nc] -f FormatFile.fmt -d DataFile [-s SearchTerm]
    
      -f,  --format FILE    Specify format file
      -d,  --data FILE      Specify plain text data file; a data string is also accepted
      -s,  --search         Search/filter term; checks all fields. Allows regexes
                            Case insesitive by default; use (?c) flag to make case sensitive
                            Other flags: https://www.regular-expressions.info/modifiers.html
      -t,  --top            Process first three lines of data file
      -nc, --nocolor        Do not use colors in output (useful for redirect to a file)
    
    END_USAGE
    exit(1);
}

sub print_value {
    my ($field_name, $field_value, $field_names_column_width) = @_;

    print colored ['bright_cyan'], $field_name;
    print colored ['white'], ' ['. length($field_value) .']: ';
    print ' ' x ( $field_names_column_width - length($field_name) - length(length($field_value)) );
    say '['. colored(['black on_bright_yellow'], $field_value) .'] ';

}

############################################

use constant {
    FILE_ORDER       => 0,   # 0- Host file field order
    FILE_DATA_TYPE   => 1,   # 1- Host file data type
    PREFIX_LENGTH    => 2,   # 2- Prefix length
    FILE_DATA_LENGTH => 3,   # 3- Host file data length
    TERMINATOR       => 4,   # 4- Terminator
    SERVER_COL_ORDER => 5,   # 5- Server column order
    SERVER_COL_NAME  => 6,   # 6- Server column name
    COL_COLLATION    => 7,   # 7- Column collation
};

use constant {
    Name  => 0,
    Data  => 1,
};    


GetOptions (
    'format|f=s' => \$config{frmFile},      # path to format file
    'data|d=s'   => \$config{dataFile},     # path to data file OR a string with data
    'search|s=s' => \$config{search_term},  # filter output by this term
    'top|t'      => \$config{showTop},      # process top N rows (see %config)
    'nocolor|nc' => \$config{no_colored_output},  # do not color output (useful for redirecting to a file)
    'help|?'     => \&print_usage,
) or die "Error in command line arguments\n" ;

print_usage unless $config{frmFile} and $config{dataFile};

$ENV{NO_COLOR} = 1 if $config{no_colored_output};


######### READ FORMAT FILE #################

my @fmtColumns;
open my $fh, '<', $config{frmFile} or die $!;
my $fmtVersion = <$fh>;
my $fmtFieldsCount = <$fh>;
while (my $line = <$fh>) {
    chomp $line;
    next if trim($line) eq '';
    my @parts = split /\s+/, $line;
    push @fmtColumns, \@parts;
}
close $fh;


######### BUILD UNPACK STRING ##############

my $unpackString = '';
my $dataLength = 0;
my @longest_col_name_lengths = (
    0,  # column Name length
    0,  # column Data length
);
$fmtColumns[$#fmtColumns]->[TERMINATOR] = '""';  # last terminator (new line) is not needed because we'll chomp() it whatever it is, \n or \r\n
for my $col (@fmtColumns) {
    $col->[TERMINATOR] = eval $col->[TERMINATOR]; # turn "\t" into a tab char, and "" into a blank string
    my $length = $col->[FILE_DATA_LENGTH] + length($col->[TERMINATOR]);
    $unpackString .= "a$length ";
    $dataLength += $length;
    if ( $longest_col_name_lengths[Name] < length($col->[SERVER_COL_NAME]) ) {
        $longest_col_name_lengths[Name] = length($col->[SERVER_COL_NAME]);
        $longest_col_name_lengths[Data] = length($length);
    }
}
$unpackString = trim($unpackString);

# print "[$unpackString], ";
# say "total record length: $dataLength";


######### READ DATA FILE ###################

# if it's a file - open file; otherwise open a string as a file
my $open_this = $config{dataFile} !~ /\n/ && -f $config{dataFile} ? $config{dataFile} : \$config{dataFile};
open my $dh, '<:crlf', $open_this or die $!;

# check if data conforms to format file
my $line = <$dh>;
chomp $line;
if (length($line) != $dataLength) {
    say colored ['bright_red on_black'], "\nERROR: Data length mismatch!";
    say "Expected: $dataLength chars (Format file: $config{frmFile})";
    say "Actual:   ".length($line)." chars (Data file: $config{dataFile})";
    exit 1;
}

seek $dh, 0, SEEK_SET;      # go back to the beginning of the file
$dh->input_line_number(0);  # reset read lines back to 0, as we start from the begining

while (my $line = <$dh>) {
    
    chomp $line;
    if ($config{showTop}) {
        next if $dh->input_line_number < $config{showTop_first};
        last if $dh->input_line_number > $config{showTop_last};
    }
    
    if (not $config{search_term} or ( $config{search_term} and $line =~ qr/$config{search_term}/i )) {        
        say "\n--- ". $dh->input_line_number ." (line length is ". length($line) ." chars; expected ". $dataLength ." chars) ---------------";
        my $i = 0;
        for my $val ( unpack($unpackString, $line) ) {
            print_value 
                $fmtColumns[$i]->[SERVER_COL_NAME],
                $val, 
                $longest_col_name_lengths[Name] + $longest_col_name_lengths[Data];
            $i++;
        }
    }
}

close $dh;
