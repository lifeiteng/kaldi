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

exit_stage=1000000

splice_indexes="-2,-1,0,1,2 -1,2 -3,3 -6,6 -7,7 0"
relu_dim=800
initial_lr=0.0017
final_lr=0.00017
momentum=0.0
initial_jobs=3
final_jobs=3
use_gpu=true
gpus="0 1 2"
num_epochs=5
frames_per_eg=20

decode_sets="forum non-native"
decode_nj=6
decode_iter="final"
decode_suffix=""
suffix=

data=data_fbank
train_set=train

ali_dir=exp/tri2b_all_ali
graph_dir=exp/tri2b/graph_lang_biglm_tg

cmvn_opts="--norm-means=false --norm-vars=false"
online_cmvn=false

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

# local/nnet3/run_ivector_common.sh --stage $stage \
# 	--speed-perturb $speed_perturb || exit 1;

if [ $stage -le 8 ]; then
  if [ -z $common_egs_dir ];then
    egs_dir=/ssd/egs-`basename $dir`
    egs_dir=${egs_dir}$suffix
    mkdir -p $egs_dir
    if [ -f $egs_dir/log/shuffle.100.log ];then
      common_egs_dir=$egs_dir
    else
      rm -rf $dir/egs
      ln -s $egs_dir $dir/egs
    fi
  fi
fi

if [ $stage -le 9 ]; then
  echo "$0: creating neural net configs";

  # create the config files for nnet initialization
  python steps/nnet3/tdnn/make_configs.py  \
    --feat-dir $data/${train_set} \
    --ali-dir $ali_dir \
    --relu-dim $relu_dim \
    --splice-indexes "$splice_indexes"  \
    --use-presoftmax-prior-scale true \
   $dir/configs || exit 1;
fi

if [ $stage -le 10 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{3,4,5,6}/$USER/kaldi-data/egs/swbd-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi

  steps/nnet3/train_dnn.py --stage=$train_stage --exit-stage $exit_stage \
    --cmd="$decode_cmd" \
    --feat.cmvn-opts="$cmvn_opts" \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial $initial_jobs \
    --trainer.optimization.num-jobs-final $final_jobs \
    --trainer.optimization.initial-effective-lrate $initial_lr \
    --trainer.optimization.final-effective-lrate $final_lr \
    --trainer.optimization.momentum $momentum \
    --egs.dir "$common_egs_dir" \
    --egs.frames-per-eg $frames_per_eg \
    --cleanup.remove-egs $remove_egs \
    --cleanup.preserve-model-interval 100 \
    --use-gpu $use_gpu \
    --gpus "$gpus" --sudo-password "496666" \
    --feat-dir $data/${train_set} \
    --ali-dir $ali_dir \
    --lang $data/lang \
    --dir=$dir  || exit 1;

fi

if [ $stage -le 11 ]; then
  echo "496666" | sudo -S nvidia-smi -c 0
  for decode_set in $decode_sets ; do
    steps/nnet3/decode.sh --nj $decode_nj --cmd "$decode_cmd" --iter $decode_iter --online-cmvn $online_cmvn \
       $graph_dir $data/${decode_set} $dir/decode_${decode_iter}_${decode_set}$decode_suffix || exit 1;
  done
fi

exit 0;

