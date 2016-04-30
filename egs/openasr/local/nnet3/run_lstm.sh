#!/bin/bash

# Copyright 2015  Johns Hopkins University (Author: Daniel Povey).
#           2015  Vijayaditya Peddinti
#           2015  Xingyu Na
#           2015  Pegah Ghahrmani
# Apache 2.0.


# this is a basic lstm script, it can also be used to train blstm models.
# the blstm can be run using local/nnet3/run_blstm.sh which invokes this script
# with the necessary parameters
# Note: lstm script runs for more epochs than the tdnn script

# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call lstm/train.sh with --gpu false

stage=0
train_stage=-10

num_jobs=6

affix=
common_egs_dir=
add_lda=false


# LSTM options
splice_indexes="-2,-1,0,1,2 0 0"
lstm_delay=" -1 -2 -3 "
label_delay=5
num_lstm_layers=3
cell_dim=1024
hidden_dim=1024
recurrent_projection_dim=256
non_recurrent_projection_dim=256
chunk_width=20
chunk_left_context=40
chunk_right_context=0
shrink=0.99
max_param_change=2.0

# training options
num_epochs=5
initial_effective_lrate=0.0003
final_effective_lrate=0.00003
num_jobs_initial=2
num_jobs_final=12
momentum=0.5
num_chunk_per_minibatch=100
samples_per_iter=20000
remove_egs=true
realign_times=

# feature options
use_ivectors=false

#decode options
extra_left_context=
extra_right_context=
frames_per_chunk=
decode_iter=

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

if [ $# != 3 ]; then
   echo "usage: local/nnet3/run_lstm.sh <graph-dir> <data-dir> <align-dir>"
   echo "e.g.:  "
   echo "main options (for others, see top of script file)"
   exit 1;
fi

graph_dir=$1
data=$2
ali_dir=$3


if $use_ivectors;then
  local/nnet3/run_ivector_common.sh --stage $stage \
                                    --mic $mic \
                                    --use-ihm-ali $use_ihm_ali \
                                    --use-sat-alignments $use_sat_alignments || exit 1;
fi

# set the variable names
use_delay=false
if [ $label_delay -gt 0 ]; then use_delay=true; fi

dir=exp/nnet3/lstm${affix:+_$affix}${use_delay:+_ld$label_delay}_layers${num_lstm_layers}_lr${initial_effective_lrate}_rpd${recurrent_projection_dim}_mpc${max_param_change}

if [ $stage -le 10 ]; then
  if [ "$use_ivectors" == "true" ]; then
    ivector_opts=" --online-ivector-dir exp/nnet3/ivectors_train_sp_hires "
    cmvn_opts="--norm-means=false --norm-vars=false"
  else
    ivector_opts=
    cmvn_opts="--norm-means=true --norm-vars=true"
  fi

  local/nnet3/train.sh $ivector_opts \
    --num-gpus 3 \
    --cleanup false \
    --stage $train_stage \
    --label-delay $label_delay \
    --num-epochs $num_epochs --num-jobs-initial $num_jobs_initial --num-jobs-final $num_jobs_final \
    --num-chunk-per-minibatch $num_chunk_per_minibatch \
    --samples-per-iter $samples_per_iter \
    --splice-indexes "$splice_indexes" \
    --feat-type raw \
    --cmvn-opts "$cmvn_opts" \
    --initial-effective-lrate $initial_effective_lrate --final-effective-lrate $final_effective_lrate \
    --momentum $momentum \
    --max-param-change $max_param_change \
    --lstm-delay "$lstm_delay" \
    --shrink $shrink \
    --cmd "$decode_cmd" \
    --num-lstm-layers $num_lstm_layers \
    --cell-dim $cell_dim \
    --hidden-dim $hidden_dim \
    --recurrent-projection-dim $recurrent_projection_dim \
    --non-recurrent-projection-dim $non_recurrent_projection_dim \
    --chunk-width $chunk_width \
    --chunk-left-context $chunk_left_context \
    --chunk-right-context $chunk_right_context \
    --egs-dir "$common_egs_dir" \
    --remove-egs $remove_egs \
    --realign-times "$realign_times" \
    $data/train $data/lang $ali_dir $dir  || exit 1;
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
  # for decode_set in forum test; do
  for decode_set in non-native native; do
      decode_dir=${dir}/decode_${decode_set}
      if [ "$use_ivectors" == "true" ]; then
        ivector_opts=" --online-ivector-dir exp/nnet3/ivectors_${decode_set} "
      else
        ivector_opts=
      fi
      steps/nnet3/lstm/decode.sh --nj ${num_jobs} --cmd "$decode_cmd" \
          $ivector_opts $model_opts \
          --extra-left-context $extra_left_context  \
	        --extra-right-context $extra_right_context  \
          --frames-per-chunk "$frames_per_chunk" \
         $graph_dir $data/${decode_set} $decode_dir || exit 1;
  done
fi

exit 0;
