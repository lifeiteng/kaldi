#!/bin/bash

# Feiteng 
# 2014.12.25
# 2015.01.14
## most of the job has been done in lls500_make_corpus.sh, though it should be doing here!
## 标准写法 参见 wsj/s5/local wsj_prepare_dict.sh
# 


# Begin configuration.

data=data
corpusname=jp
dict=ko-kr.dict

# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;


mkdir -p $data/local/dict

cp ${dict} $data/local/dict/lexicon.txt.tmp || exit 1;

sed -i 's=([0-9]\+)= =g;s= \+= =g;' $data/local/dict/lexicon.txt.tmp

cat $data/local/dict/lexicon.txt.tmp | sort -k1 | uniq >$data/local/dict/lexicon.txt

## Get phone lists... 获取phones列表
grep -v -w SIL $data/local/dict/lexicon.txt | \
  awk '{for(n=2;n<=NF;n++) { p[$n]=1; }} END{for(x in p) {print x}}' | sort > $data/local/dict/nonsilence_phones.txt

echo '!SIL SIL' >> $data/local/dict/lexicon.txt 

echo SIL > $data/local/dict/silence_phones.txt
echo SIL > $data/local/dict/optional_silence.txt
touch $data/local/dict/extra_questions.txt # no extra questions, as we have no stress or tone markers.

echo "##### Dictionary preparation succeeded[std_prepare_dict.sh]."
