#!/bin/bash

# based on run_tdnn_2o.sh

set -e

# configs for 'chain'
stage=100
train_stage=-10
get_egs_stage=-10
exit_stage=-1

speed_perturb=false

affix=bidirectional

# LSTM options
splice_indexes="-2,-1,0,1,2 0 0"
lstm_delay=" -3 -3 -3 "
label_delay=5
num_lstm_layers=3
cell_dim=800
hidden_dim=1024
recurrent_projection_dim=256
non_recurrent_projection_dim=256

# GRU
use_gru_layer=true

# training options
leftmost_questions_truncate=-1
chunk_width=150

chunk_left_context=40
chunk_right_context=20

xent_regularize=0.025
cmvn_opts="--norm-means=true --norm-vars=true"
max_param_change=5

gpus="0 1 2"
use_gpu=true
cv_period=20
num_epochs=5

# decode options
extra_left_context=
extra_right_context=
frames_per_chunk=

remove_egs=false
common_egs_dir= # exp/chain/tdnn/egs

use_ivectors=false

numTreeLeaves=5000

suffix=

skip_decode=false
decode_sets="forum non-native"
decode_suffix=""
decode_iter=final
decode_nj=6

graph_dir=
dir=

# End configuration section.
echo "$0 $@"  # Print the command line for logging

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

# The iVector-extraction and feature-dumping parts are the same as the standard
# nnet3 setup, and you can skip them by setting "--stage 8" if you have already
# run those things.

if [ "$speed_perturb" == "true" ]; then
  suffix=${suffix}_sp
fi

if [ -z $dir ];then
  if $use_gru_layer;then
    dir=exp/chain/gru
  else
    dir=exp/chain/lstm
  fi

  dir=$dir${affix:+-$affix}-ld${label_delay}-clc${chunk_left_context}-crc${chunk_right_context}-mpc${max_param_change}
  dir=${dir}-rpd${recurrent_projection_dim}-nrpd${non_recurrent_projection_dim}${suffix}
fi

mkdir -p $dir/egs
data=data_fbank_hires

train_set=train

src_model=exp/tri3
lats_dir=exp/tri3_all_lats

ali_dir=exp/tri3_all_ali
tree_dir=exp/chain/tri3_tree
lang=$data/lang_chain

# if we are using the speed-perturbed data we need to generate
# alignments for it.
ivector_dir=""
# if $use_ivectors && [ $stage -le 5 ]; then
#   local/nnet3/run_ivector_common.sh --stage $stage \
#     --speed-perturb $speed_perturb \
#     --generate-alignments $speed_perturb || exit 1;
# fi

if [ $stage -le 0 ]; then
    # Get the alignments as lattices (gives the CTC training more freedom).
    # use the same num-jobs as the alignments
    nj=$(cat $ali_dir/num_jobs) || exit 1;
    steps/align_fmllr_lats.sh --nj $nj data_mfcc/train \
      data_mfcc/lang exp/tri3 $lats_dir || exit 1;
    rm exp/tri3_all_lats/fsts.*.gz # save space
fi

if [ $stage -le 1 ]; then
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  rm -rf $lang
  cp -r data/lang $lang
  silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
  nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
  # Use our special topology... note that later on may have to tune this
  # topology.
  steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
fi

if [ $stage -le 2 ]; then
  # Build a tree using our new topology.
  steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
      --leftmost-questions-truncate $leftmost_questions_truncate \
      --cmd "$train_cmd" $numTreeLeaves data_mfcc/train_all $lang $ali_dir $tree_dir
fi

if [ $stage -le 9 ]; then
  echo "$0: creating neural net configs";
  config_extra_opts=()

  if $use_gru_layer;then
    echo "$0: Use GRU Layer!"
    gru_delay=$lstm_delay
    [ ! -z "$gru_delay" ] && config_extra_opts+=(--gru-delay "$gru_delay")
    steps/nnet3/gru/make_configs.py  "${config_extra_opts[@]}" \
      --splice-indexes "$splice_indexes " \
      --num-gru-layers $num_lstm_layers \
      --feat-dir $data/${train_set} \
      --tree-dir $tree_dir \
      --recurrent-projection-dim $recurrent_projection_dim \
      --non-recurrent-projection-dim $non_recurrent_projection_dim \
      --hidden-dim $hidden_dim \
      --norm-based-clipping true \
      --label-delay $label_delay \
      --self-repair-scale 0.00001 \
      --xent-regularize $xent_regularize \
      --include-log-softmax false \
     $dir/configs || exit 1;
  else
    [ ! -z "$lstm_delay" ] && config_extra_opts+=(--lstm-delay "$lstm_delay")
    steps/nnet3/lstm/make_configs.py  "${config_extra_opts[@]}" \
      --feat-dir $data/${train_set} \
      --tree-dir $tree_dir \
      --num-lstm-layers $num_lstm_layers \
      --splice-indexes "$splice_indexes " \
      --cell-dim $cell_dim \
      --hidden-dim $hidden_dim \
      --recurrent-projection-dim $recurrent_projection_dim \
      --non-recurrent-projection-dim $non_recurrent_projection_dim \
      --label-delay $label_delay \
      --self-repair-scale 0.00001 \
      --xent-regularize $xent_regularize \
      --include-log-softmax false \
     $dir/configs || exit 1;
  fi
fi

if [ $stage -le 10 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{5,6,7,8}/$USER/kaldi-data/egs/swbd-$(date +'%m_%d_%H_%M')/s5c/$dir/egs/storage $dir/egs/storage
  fi

 touch $dir/egs/.nodelete # keep egs around when that run dies.

 steps/nnet3/chain/train.py --stage $train_stage --exit-stage $exit_stage \
    --stage=$train_stage \
    --cmd="$decode_cmd" \
    --feat.online-ivector-dir "$ivector_dir" \
    --feat.cmvn-opts="$cmvn_opts" \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00001 \
    --chain.xent-regularize $xent_regularize \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --chain.left-deriv-truncate 0 \
    --trainer.num-chunk-per-minibatch 64 \
    --trainer.max-param-change $max_param_change \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.shrink-value 0.99 \
    --trainer.optimization.num-jobs-initial 3 \
    --trainer.optimization.num-jobs-final 3 \
    --trainer.optimization.initial-effective-lrate 0.001 \
    --trainer.optimization.final-effective-lrate 0.0001 \
    --trainer.optimization.momentum 0.0 \
    --egs.stage $get_egs_stage \
    --egs.opts="--frames-overlap-per-eg 0" \
    --egs.chunk-width $chunk_width \
    --egs.chunk-left-context $chunk_left_context \
    --egs.chunk-right-context $chunk_right_context \
    --egs.dir="$common_egs_dir" \
    --cleanup.remove-egs $remove_egs \
    --feat-dir $data/${train_set} \
    --tree-dir $tree_dir \
    --lat-dir $lats_dir \
    --use-gpu=$use_gpu \
    --warm-iters=0 \
    --gpus-wait=true \
    --gpus="$gpus" \
    --cv-period=$cv_period \
    --sudo-password="496666" \
    --dir $dir  || exit 1;
fi

if $skip_decode;then
  exit 0;
fi

if [ -z $graph_dir ] && [ $stage -le 18 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  utils/mkgraph.sh --self-loop-scale 1.0 $data/lang_biglm_tg $dir $dir/graph_tg
  graph_dir=$dir/graph_tg
fi

if [ $stage -le 11 ]; then
  if [ -z $extra_left_context ]; then
    extra_left_context=$chunk_left_context
  fi
  if [ -z $extra_right_context ]; then
    extra_right_context=$chunk_right_context
  fi
  if [ -z $frames_per_chunk ]; then
    frames_per_chunk=$chunk_width
  fi
  model_opts=
  [ ! -z $decode_iter ] && model_opts=" --iter $decode_iter ";  
  for decode_set in forum non-native native; do
      decode_dir=${dir}/decode_${decode_set}
      if [ "$use_ivectors" == "true" ]; then
        ivector_opts=" --online-ivector-dir exp/nnet3/ivectors_${decode_set} "
      else
        ivector_opts=
      fi
      steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 --nj $decode_nj \
          $ivector_opts $model_opts \
          --extra-left-context $extra_left_context  \
          --extra-right-context $extra_right_context  \
          --frames-per-chunk "$frames_per_chunk" \
          --scoring-opts "--min-lmwt 5 " \
          $graph_dir $data/${decode_set} $dir/decode_${decode_iter}_${decode_set}${decode_suffix} || exit 1;
  done
fi


exit 0;
