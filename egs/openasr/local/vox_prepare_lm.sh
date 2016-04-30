#!/bin/bash

# Feiteng 2014.12.25  
### TODO 参考wsj_train_lms.sh 额外的文本语料

data=data
# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

tmpdir=$data/local/lm_tmp
lmdir=$data/local/lm
mkdir -p $tmpdir $lmdir

if [ ! -f "tools/mitlm-svn/bin/estimate-ngram" ]; then
  echo "--- Downloading and compiling MITLM toolkit ..."
  mkdir -p tools
  command -v svn >/dev/null 2>&1 ||\
    { echo "SVN client is needed but not found" ; exit 1; }
  svn checkout http://mitlm.googlecode.com/svn/trunk/ tools/mitlm-svn
  cd tools/mitlm-svn/
  ./autogen.sh
  ./configure --prefix=`pwd`
  make
  make install
  ln mitlm-svn mitlm
  cd ../..
fi

echo "--- Estimating the LM ..."
if [ ! -f "tools/mitlm/bin/estimate-ngram" ]; then
  echo "estimate-ngram not found! MITLM compilation failed?";
  exit 1;
fi


cut -d" " -f1 --complement $data/train/text >$tmpdir/all.text
cut -d" " -f1 --complement $data/test/text >>$tmpdir/all.text
cut -d" " -f1 $data/local/dict/lexicon.txt >$tmpdir/vocab.fixed

sed -i 's= \+= =g;' $tmpdir/all.text

tools/mitlm/bin/estimate-ngram -s FixKN -t $tmpdir/all.text -o 1 \
 -vocab $tmpdir/vocab.fixed -wl $lmdir/lm_ug.arpa || exit 1;

tools/mitlm/bin/estimate-ngram -s FixKN -t $tmpdir/all.text -o 2 \
 -vocab $tmpdir/vocab.fixed -wl $lmdir/lm_bg.arpa || exit 1;

tools/mitlm/bin/estimate-ngram -s FixKN -t $tmpdir/all.text -o 3 \
 -vocab $tmpdir/vocab.fixed -wl $lmdir/lm_tg.arpa || exit 1;

# tools/mitlm/bin/estimate-ngram -s FixKN -t $tmpdir/all.text -o 2 \
#  -write-vocab $tmpdir/vocab-full.txt -wl $lmdir/lm_bg.arpa || exit 1;

# tools/mitlm/bin/estimate-ngram -s FixKN -t $tmpdir/all.text -o 3 \
#  -write-vocab $tmpdir/vocab-full.txt -wl $lmdir/lm_tg.arpa || exit 1;



# echo "-----use KenLM to train LM (tri-gram) ..."
# #tools/kenlm/bin/lmplz -o 2 <$dir/text >$lmdir/lm_bg.arpa
# if [ ! -f "tools/kenlm/bin/lmplz" ]; then
#   echo "tools/kenlm/bin/lmplz not found! KenLM compilation failed?";
#   exit 1;
# fi

# cut -d" " -f1 --complement $data/train/text >$tmpdir/all.text
# cut -d" " -f1 --complement $data/test/text >>$tmpdir/all.text

# sed -i 's= \+= =g;' $tmpdir/all.text

# tools/kenlm/bin/lmplz -o 3 <$tmpdir/all.text >$lmdir/lm_tg.arpa

echo "##### std_prpeare_lm.sh succeeded. Finished building the LM model!"