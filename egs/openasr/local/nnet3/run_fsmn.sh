#!/bin/bash

# this is the standard "tdnn" system, built in nnet3; it's what we use to
# call multi-splice.

. cmd.sh


# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call train_tdnn.sh with --gpu false,
# --num-threads 16 and --minibatch-size 128.

stage=0
affix=
train_stage=-10
common_egs_dir=
reporting_email=
remove_egs=false
decode_sets="forum non-native"

decode_nj=6
decode_iter="final"
suffix=
exit_stage=1000000

initial_lr=0.0017
final_lr=0.00017
momentum=0.0

. cmd.sh
. ./path.sh
. ./utils/parse_options.sh


if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

if [ "$speed_perturb" == "true" ]; then
  suffix=${suffix}_sp
fi
dir=exp/nnet3/tdnn
dir=$dir${affix:+_$affix}
dir=${dir}$suffix

train_set=train


data=data_all_mfcc_hires

ali_dir=ep0-exp/tri3_ali
graph_dir=ep0-exp/tri3/graph_tg

# local/nnet3/run_ivector_common.sh --stage $stage \
# 	--speed-perturb $speed_perturb || exit 1;

if [ $stage -le 9 ]; then
  echo "$0: creating neural net configs";

  # create the config files for nnet initialization
  python steps/nnet3/fsmn/make_configs.py  \
    --feat-dir $data/${train_set} \
    --ali-dir $ali_dir \
    --relu-dim 1024 \
    --splice-indexes "-2,-1,0,1,2 -1,2 -3,3 -7,2 0"  \
    --use-presoftmax-prior-scale true \
   $dir/configs || exit 1;
fi

if [ $stage -le 10 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{3,4,5,6}/$USER/kaldi-data/egs/swbd-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi
  echo "496666" | sudo -S nvidia-smi -c 0
  steps/nnet3/train_dnn.py --stage=$train_stage --exit-stage $exit_stage \
    --cmd="$decode_cmd" \
    --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
    --trainer.num-epochs 3 \
    --trainer.optimization.num-jobs-initial 2 \
    --trainer.optimization.num-jobs-final 4 \
    --trainer.optimization.initial-effective-lrate $initial_lr \
    --trainer.optimization.final-effective-lrate $final_lr \
    --trainer.optimization.momentum $momentum \
    --egs.dir "$common_egs_dir" \
    --cleanup.remove-egs $remove_egs \
    --cleanup.preserve-model-interval 100 \
    --use-gpu true \
    --gpus "-1 -1" --sudo-password "496666" \
    --feat-dir $data/${train_set} \
    --ali-dir $ali_dir \
    --lang $data/lang \
    --dir=$dir  || exit 1;

fi

if [ $stage -le 11 ]; then
  echo "496666" | sudo -S nvidia-smi -c 0
  for decode_set in $decode_sets ; do
    steps/nnet3/decode.sh --nj $decode_nj --cmd "$decode_cmd" --iter $decode_iter \
       $graph_dir $data/${decode_set} $dir/decode_${decode_iter}_${decode_set}|| exit 1;
  done
fi

exit 0;

