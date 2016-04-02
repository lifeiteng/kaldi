#!/bin/bash

# Feiteng 
# 2015.11.25

# Begin configuration.

data=data

# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

if [ $# -ne 1 ]; then
 	echo "##### Argument should be the dict, see ../run.sh for example."
 	exit 1;
fi 

for file in $1;do
	if [ ! -f $file ]; then
		echo "##### no file $file !!!"
		exit 1;
	fi
done

mkdir -p $data/local/dict

cat $1 | sort | uniq >$data/local/dict/lexicon.txt || exit 1;
sed -i 's= \+= =g;' $data/local/dict/lexicon.txt

for lex in $data/local/dict/lexicon.txt;do
	(echo '[breath] SIL'; echo '[noise] SIL'; echo '[cough] SIL';
	echo '[smack] SIL'; echo '[um] SIL'; echo '[uh] SIL'
	echo '<unk> SIL' ) >>$lex
	cat $lex | sort | uniq >$lex.t 
	mv $lex.t $lex
done

for dict in dict ;do
	for dir in local;do
		## Get phone lists... 获取phones列表
		grep -v -w SIL $data/$dir/$dict/lexicon.txt | \
		  awk '{for(n=2;n<=NF;n++) { p[$n]=1; }} END{for(x in p) {print x}}' | sort > $data/$dir/$dict/nonsilence_phones.txt

		echo '!SIL SIL' >> $data/$dir/$dict/lexicon.txt 

		echo SIL > $data/$dir/$dict/silence_phones.txt
		echo SIL > $data/$dir/$dict/optional_silence.txt
		touch $data/$dir/$dict/extra_questions.txt # no extra questions, as we have no stress or tone markers.
	done
done

echo "$0 Dictionary preparation succeeded."
exit 0;


