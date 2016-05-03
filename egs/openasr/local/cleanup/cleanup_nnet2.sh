#!/bin/bash

# Copyright 2016 Feiteng
#

# Begin configuration.

cmd=run.pl
stage=-4
max_wer=0
nj=12

# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

if [ $# != 4 ]; then
   echo "Usage: local/cleanup/cleanup_nnet2.sh <data-dir> <lang-dir> <alignment-dir> <exp-dir>"
   echo "e.g.: local/cleanup/cleanup_nnet2.sh data/train data/lang exp/fbank40_h5t1024 data/train_cleanup"
   echo "main options (for others, see top of script file)"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo "  --config <config-file>                           # config containing options"
   echo "  --stage <stage>                                  # stage to do partial re-run from."
   exit 1;
fi

data=$1
lang=$2
alidir=$3
dir=$4

bad_utts_dir=${data}_bad_utts
if [ $stage -le 1 ]; then
  steps/cleanup/find_bad_utts_nnet.sh --cmd "$cmd" --nj $nj $data $lang $alidir $bad_utts_dir || exit 1;
fi

local/cleanup/sort_bad_utts.py --bad-utt-info-file $bad_utts_dir/all_info.sorted.txt \
  --max-wer $max_wer --output-file $bad_utts_dir/wer_sorted_utts_${max_wer}wer || exit 1;

utils/copy_data_dir.sh --validate-opts "--no-wav" $data $dir || exit 1;
utils/filter_scp.pl $bad_utts_dir/wer_sorted_utts_${max_wer}wer \
  $data/feats.scp  > $dir/feats.scp || exit 1;
utils/fix_data_dir.sh $dir || exit 1;

echo "$0: Done cleanup [$data] -> [$dir]"
exit 0;
