#!/bin/bash

# Feiteng 
# 2015.11.25
# 2016.04.06

# Begin configuration.

data=data
noise=true
phoneset=9000

# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

set -e

if [ $# -ne 1 ]; then
    echo "##### Argument should be the dict file."
    exit 1;
fi 

if [ ! -f $1 ]; then
    echo "##### no dict file $file !!!"
    exit 1;
fi

dir=$data/local/dict
mkdir -p $dir

cat $1 | grep -v -w "<s>" | grep -v -w "</s>" | grep -v -w "<unk>" | \
    sort | uniq | sed 's= \+= =g' | sed 's:([0-9])::g' >$dir/lexicon_words.txt || exit 1;

if [ $phoneset -eq 9000 ];then
	sed -i 's/AX/AH/g' $dir/lexicon_words.txt
	sed -i 's/TS/T S/g' $dir/lexicon_words.txt
	sed -i 's/DZ/D Z/g' $dir/lexicon_words.txt
fi

grep -v -w SIL $dir/lexicon_words.txt | \
  awk '{for(n=2;n<=NF;n++) { phones[$n]=1; }} END{for(x in phones) {print x}}' | sort > $dir/nonsilence_phones.txt

echo SIL > $dir/silence_phones.txt
echo SIL > $dir/optional_silence.txt
echo -n  > $dir/extra_questions.txt # no extra questions, as we have no stress or tone markers.

if $noise;then
    # Add to the lexicon the silences, noises etc.
    # Typically, you would use "<UNK> NSN" here, but the Cantab Research language models
    # use <unk> instead of <UNK> to represent out of vocabulary words.
    # (echo '!SIL SIL'; echo '[BREATH] BRH'; echo '[NOISE] NSN'; echo '[COUGH] CGH';
    #  echo '[SMACK] SMK'; echo '[UM] UM'; echo '[UH] UHH'
    #  echo '<unk> NSN' ) | \

    (echo '!SIL SIL'; echo '[breath] BRH'; echo '[noise] NSN'; echo '[cough] CGH';
    echo '[smack] SMK'; echo '[um] UM'; echo '[uh] UHH';
    echo '<UNK> NSN' ) | cat - $dir/lexicon_words.txt | sort | uniq > $dir/lexicon.txt
    ( echo SIL; echo BRH; echo CGH; echo NSN ; echo SMK; echo UM; echo UHH ) > $dir/silence_phones.txt
else
    (echo '!SIL SIL'; echo '[breath] SIL'; echo '[noise] SIL'; echo '[cough] SIL';
    echo '[smack] SIL'; echo '[um] SIL'; echo '[uh] SIL';
    echo '<UNK> SIL' ) | cat - $dir/lexicon_words.txt | sort | uniq > $dir/lexicon.txt
    (echo SIL;) > $dir/silence_phones.txt
fi

# Check that the dict dir is okay!
utils/validate_dict_dir.pl $dir || exit 1

echo "$0 Dictionary preparation succeeded."
exit 0;
