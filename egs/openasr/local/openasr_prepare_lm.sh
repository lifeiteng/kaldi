#!/bin/bash

# Feiteng 2014.12.25  
### TODO 参考wsj_train_lms.sh 额外的文本语料

data=data
biglm=""
lambda=0.6
# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

tmpdir=$data/local/lm_tmp
lmdir=$data/local/lm

mkdir -p $tmpdir $lmdir

if [ ! -f "tools/mitlm/bin/estimate-ngram" ]; then
  echo "--- Downloading and compiling MITLM toolkit ..."
  mkdir -p tools
  command -v git >/dev/null 2>&1 ||\
    { echo "git is needed but not found" ; exit 1; }
  git clone https://github.com/mit-nlp/mitlm.git tools/mitlm || exit 1;
  cd tools/mitlm/
  ./autogen.sh
  ./configure --prefix=`pwd`
  make
  make install
  cd ../..
fi

echo "--- Estimating the LM ..."
if [ ! -f "tools/mitlm/bin/estimate-ngram" ]; then
  echo "estimate-ngram not found! MITLM compilation failed?";
  exit 1;
fi


cut -d" " -f2- $data/train/text >$tmpdir/all.text
cut -d" " -f2- $data/test/text >>$tmpdir/all.text
sed -i 's= \+= =g;' $tmpdir/all.text

cat $tmpdir/all.text | sort | uniq >$tmpdir/all.text.t
mv $tmpdir/all.text.t $tmpdir/all.text

./tools/mitlm/bin/estimate-ngram -s FixKN -t $tmpdir/all.text -o 3 -wl $lmdir/trans_tg.arpa || exit 1;

echo "Mix LMs -> mixed_tg.arpa"
# ./tools/mitlm/bin/interpolate-ngram -verbose 3 -l $biglm -t $tmpdir/all.text -wl $lmdir/mixed_tg.arpa || exit 1;

$SRILM/ngram -lm $biglm -lambda $lambda -mix-lm $lmdir/trans_tg.arpa \
  -write-lm $lmdir/mixed_tg.arpa || exit 1;

echo "$0 Finished building the LM model!"

exit 0;
