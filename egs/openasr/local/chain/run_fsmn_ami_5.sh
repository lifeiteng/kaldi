#!/bin/bash

#adapted from swbd's local/chain/6z.sh script. We change the TDNN config
# These are the other modifications:
#   1. AMI data has a lot of short segments so we use combine_short_segments.py
#      to combine contiguous segments to have a minimum_duration of 1.55 secs.
#      This is done to ensure that chain/get_egs.sh does not discard the
#      shorter segments
#   2. AMI data has a lot of alignment errors so we add an option to discard
#      segments with a lot of alignment errors. These are identified using
#      find_bad_utt.sh


set -e

# configs for 'chain'
stage=100
train_stage=-10
get_egs_stage=-10
decode_stage=1

affix=
common_egs_dir=

label_delay=5

# training options
# chain options
frames_per_eg=150
xent_regularize=0.1
max_wer=
relu_dim=512
dir=exp/chain/fsmn_ami5_d

graph_dir=exp/chain/lstm_d_ld5_0507/graph_tg

decode_sets="forum non-native"
suffix=
train_set=train
decode_nj=6

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

dir=$dir${affix:+_$affix}
if [ $label_delay -gt 0 ]; then dir=${dir}_ld$label_delay; fi
dir=${dir}$suffix
mkdir -p $dir/egs

data=data_all_mfcc_hires
mkdir -p $data

src_model=ep0-exp/tri3
lats_dir=ep0-exp/tri3_lats_d

ali_dir=ep0-exp/tri3_ali
treedir=exp/chain/tri3_d_tree
lang=$data/lang_chain_2d
ivector_dir=""

if [ $stage -le 16 ]; then
  echo "$0: creating neural net configs";

  steps/nnet3/fsmn/make_configs.py \
    --self-repair-scale 0.00001 \
    --feat-dir $data/$train_set \
    --tree-dir $treedir \
    --relu-dim $relu_dim \
    --splice-indexes "-1,0,1 [-2,2] [-3,3] [-5,5] [-6,6] 0" \
    --use-presoftmax-prior-scale false \
    --xent-regularize $xent_regularize \
    --xent-separate-forward-affine true \
    --include-log-softmax false \
    --final-layer-normalize-target 1.0 \
   $dir/configs || exit 1;
fi

if [ $stage -le 17 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{5,6,7,8}/$USER/kaldi-data/egs/ami-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi
  touch $dir/egs/.nodelete # keep egs around when that run dies.
  
  echo "496666" | sudo -S nvidia-smi -c 1
  steps/nnet3/chain/train.py --stage $train_stage \
    --cmd "$decode_cmd" \
    --feat.online-ivector-dir "$ivector_dir" \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00005 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --egs.dir "$common_egs_dir" \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0" \
    --egs.chunk-width $frames_per_eg \
    --trainer.num-chunk-per-minibatch 128 \
    --trainer.frames-per-iter 1500000 \
    --trainer.num-epochs 4 \
    --trainer.optimization.num-jobs-initial 2 \
    --trainer.optimization.num-jobs-final 4 \
    --trainer.optimization.initial-effective-lrate 0.001 \
    --trainer.optimization.final-effective-lrate 0.0001 \
    --trainer.max-param-change 2.0 \
    --cleanup.remove-egs false \
    --feat-dir $data/$train_set \
    --tree-dir $treedir \
    --lat-dir $lats_dir \
    --use-gpu=true \
    --gpus-wait=true \
    --gpus="0 1" \
    --sudo-password "496666" \
    --dir $dir  || exit 1;
fi

if [ ! -z $graph_dir ] && [ $stage -le 18 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  utils/mkgraph.sh --self-loop-scale 1.0 data_all/lang_tg_dict $dir $dir/graph_tg
fi

if [ $stage -le 19 ]; then
  echo "496666" | sudo -S nvidia-smi -c 0
  for decode_set in "$decode_sets"; do
      steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
          --stage $decode_stage \
          --extra-left-context 20 \
          --nj $decode_nj --cmd "$decode_cmd" \
          --online-ivector-dir "$ivector_dir" \
          --scoring-opts "--min-lmwt 5 " \
         $graph_dir $data/${decode_set} $dir/decode_${decode_set} || exit 1;
  done
fi

bash RESULTS | grep chain

exit 0;
