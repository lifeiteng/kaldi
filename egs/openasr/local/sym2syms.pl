#!/usr/bin/perl
# Feiteng


$ignore_oov = 0;

for($x = 0; $x < 2; $x++) {
  if ($ARGV[0] eq "--map-oov") {
    shift @ARGV; 
    $map_oov = shift @ARGV;
    if ($map_oov eq "-f" || $map_oov =~ m/words\.txt$/ ) { #|| $map_oov eq ""
      # disallow '-f', the empty string and anything ending in words.txt as the
      # OOV symbol because these are likely command-line errors.
      die "the --map-oov option requires an argument";
    }
  }
  # if ($ARGV[0] eq "-f") {
  #   shift @ARGV;
  #   $field_spec = shift @ARGV; 
  #   if ($field_spec =~ m/^\d+$/) {
  #     $field_begin = $field_spec - 1; $field_end = $field_spec - 1;
  #   }
  #   if ($field_spec =~ m/^(\d*)[-:](\d*)/) { # accept e.g. 1:10 as a courtesty (properly, 1-10)
  #     if ($1 ne "") {
  #       $field_begin = $1 - 1;  # Change to zero-based indexing.
  #     }
  #     if ($2 ne "") {
  #       $field_end = $2 - 1;    # Change to zero-based indexing.
  #     }
  #   }
  #   if (!defined $field_begin && !defined $field_end) {
  #     die "Bad argument to -f option: $field_spec"; 
  #   }
  # }
}

$symtab = shift @ARGV;
if (!defined $symtab) {
  print STDERR "Usage: sym2int.pl [options] symtab [input transcriptions] > output transcriptions\n" .
    "options: [--map-oov <oov-symbol> ]  [-f <field-range> ]\n" .
      "note: <field-range> can look like 4-5, or 4-, or 5-, or 1.\n";
}
open(F, "<$symtab") || die "Error opening symbol table file $symtab";
while(<F>) {
    # @A = split(" ", $_);
    # @A == 2 || die "bad line in symbol table file: $_";
    # $sym2int{$A[0]} = $A[1] + 0;
    if(m/^;/) { next; }
    m/(.+) (.+)/ || die "bad line $_"; #这里根据$input_snr的格式做匹配
    #print $1," ",$2,"\n";
    $sym2syms{$1} = $2;
}

if (defined $map_oov && $map_oov !~ m/^\d+$/) { # not numeric-> look it up
  if (!defined $sym2syms{$map_oov}) { die "OOV symbol $map_oov not defined."; }
  $map_oov = $sym2syms{$map_oov};
}

$num_warning = 0;
$max_warning = 20;

while (<>) {
  @A = split(" ", $_);
  @B = ();
  for ($n = 0; $n < @A; $n++) {
    $a = $A[$n];
    {
      $i = $sym2syms{$a};
      print $a
      # if (!defined ($i)) {
      #   if (defined $map_oov) {
      #     if ($num_warning++ < $max_warning) {
      #       print STDERR "sym2syms.pl: replacing $a with $map_oov\n";
      #       if ($num_warning == $max_warning) {
      #         print STDERR "sym2syms.pl: not warning for OOVs any more times\n";
      #       }
      #     }
      #     $i = $map_oov;
      #   } else {
      #     $pos = $n+1;
      #     die "sym2syms.pl: undefined symbol $a (in position $pos)\n";
      #   }
      # }
      $a = $i;
    }
    push @B, $a;
  }
  # print join(" ", @B);
  print "\n";
}
if ($num_warning > 0) {
  print STDERR "** Replaced $num_warning instances of OOVs with $map_oov\n"; 
}

exit(0);
