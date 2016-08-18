#!/bin/bash

## Feiteng 2016.08.17

make_mfcc=false
nj=10
dict=""
train=true
test=false

. ./cmd.sh 
. ./path.sh
. ./utils/parse_options.sh
set -e

if [ $# != 2 ]; then
   echo "Usage: local/data/prepare_data_from_corpus.sh <corpus-dir> <data-dir>"
   echo "e.g.: local/data/prepare_data_from_corpus.sh /data/openasr-data-02 /data/ASR_datasets/openasr-02"
   echo "main options (for others, see top of script file)"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo "  --make-mfcc <true|false>                         # wether compute mfcc feature."
   exit 1;
fi

corpus_dir=$1
data_dir=$2

mkdir -p tmp

echo ============================================================================
echo "                               Data Preparation                           "
echo ============================================================================

local/data/std_prepare_data.sh --train $train --test $test --corpus "openasr" --user-filter local/data/users.filter.base64 \
    --data $data_dir $corpus_dir || exit 1;

subsets=""
$train && subsets="train"
$test && subsets="$subsets test"
if [ -z $subsets ];then
  echo "$0: you must set one of train/test true"
  exit 1;
fi

if [ ! -z $dict ];then

  if [ ! -z $subsets ];then
    for x in $subsets;do
      local/data/clean_trans.py --lower True --clean-oov True $dict $data_dir/$x/text $data_dir/$x/text || exit 1;
    done
  fi
fi

for x in $subsets;do
  utils/fix_data_dir.sh $data_dir/$x || exit 1;
  utils/data/get_utt2dur.sh $data_dir/$x || exit 1;
  awk 'BEGIN{sum=0;} {sum+=sprintf("%f",$2)} END{printf("%.3f seconds %.3f hours\n",sum, sum/3600);}' $data_dir/$x/utt2dur
done


if $make_mfcc;then
    echo "========  compute mfcc feature ========"
    mfccdir=$data_dir/mfcc
    for x in $subsets;do
        steps/make_mfcc.sh --nj $nj --mfcc-config conf/mfcc.conf \
          --cmd "$train_cmd" $data_dir/$x exp/make_mfcc/$data_dir/$x $mfccdir || exit 1;
        steps/compute_cmvn_stats.sh $data_dir/$x exp/make_mfcc/$data_dir/$x $mfccdir || exit 1;
    done
else
    echo "skip mfcc feature computation"
fi

echo "$0: DONE!"
exit 0;
