#!/bin/bash

# Copyright 2015  Johns Hopkins University (Author: Daniel Povey).
#           2015  Vijayaditya Peddinti
#           2015  Xingyu Na
#           2015  Pegah Ghahrmani
# Apache 2.0.


# this is a basic lstm script
# LSTM script runs for more epochs than the TDNN script
# and each epoch takes twice the time

# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call lstm/train.sh with --gpu false

stage=100
train_stage=-10

speed_perturb=true
common_egs_dir=
reporting_email="feiteng@liulishuo.com"

# LSTM options
splice_indexes="-2,-1,0,1,2 0 0"
lstm_delay=" [-1,1] [-2,2] [-3,3] "
label_delay=5
num_lstm_layers=3
cell_dim=1024
hidden_dim=1024
recurrent_projection_dim=256
non_recurrent_projection_dim=256
chunk_width=20
chunk_left_context=40
chunk_right_context=20

# training options
num_epochs=5
initial_effective_lrate=0.00003
final_effective_lrate=0.000001
num_jobs_initial=3
num_jobs_final=6
momentum=0.5
num_chunk_per_minibatch=100
samples_per_iter=20000
remove_egs=false

#decode options
extra_left_context=
extra_right_context=
frames_per_chunk=

affix=bidirectional
use_ivectors=false
decode_dir=final
suffix=
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


if [ "$speed_perturb" == "true" ]; then
  suffix=${suffix}_sp
fi
dir=exp/nnet3/lstm
dir=$dir${affix:+_$affix}
if [ $label_delay -gt 0 ]; then dir=${dir}_ld$label_delay; fi
dir=${dir}$suffix

train_set=train_$suffix

ivector_dir=""
if $use_ivectors && [ $stage -le 5 ]; then
  local/nnet3/run_ivector_common.sh --stage $stage \
    --speed-perturb $speed_perturb || exit 1;
  ivector_dir=exp/nnet3/ivectors_${train_set}
fi

chmod -R +x local

data=data_all_fbank
ali_dir=exp/tri3_ali
graph_dir=exp/tri3/graph_tg

if [ $stage -le 9 ]; then
  echo "$0: creating neural net configs";
  config_extra_opts=()
  [ ! -z "$lstm_delay" ] && config_extra_opts+=(--lstm-delay "$lstm_delay")
  steps/nnet3/lstm/make_configs.py  "${config_extra_opts[@]}" \
    --feat-dir $data/train \
    --ali-dir $ali_dir \
    --num-lstm-layers $num_lstm_layers \
    --splice-indexes "$splice_indexes " \
    --cell-dim $cell_dim \
    --hidden-dim $hidden_dim \
    --recurrent-projection-dim $recurrent_projection_dim \
    --non-recurrent-projection-dim $non_recurrent_projection_dim \
    --label-delay $label_delay \
    --self-repair-scale 0.00001 \
   $dir/configs || exit 1;

fi

if [ $stage -le 10 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{3,4,5,6}/$USER/kaldi-data/egs/swbd-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi

  steps/nnet3/train_rnn.py --stage=$train_stage \
    --cmd="$decode_cmd" \
    --feat.online-ivector-dir=$ivector_dir \
    --feat.cmvn-opts="--norm-means=true --norm-vars=true" \
    --trainer.num-epochs=$num_epochs \
    --trainer.samples-per-iter=$samples_per_iter \
    --trainer.optimization.num-jobs-initial=$num_jobs_initial \
    --trainer.optimization.num-jobs-final=$num_jobs_final \
    --trainer.optimization.initial-effective-lrate=$initial_effective_lrate \
    --trainer.optimization.final-effective-lrate=$final_effective_lrate \
    --trainer.optimization.shrink-value 0.99 \
    --trainer.rnn.num-chunk-per-minibatch=$num_chunk_per_minibatch \
    --trainer.optimization.momentum=$momentum \
    --trainer.max-param-change 20 \
    --egs.chunk-width=$chunk_width \
    --egs.chunk-left-context=$chunk_left_context \
    --egs.chunk-right-context=$chunk_right_context \
    --egs.dir="$common_egs_dir" \
    --cleanup.remove-egs=$remove_egs \
    --cleanup.preserve-model-interval=100 \
    --use-gpu=true \
    --gpus-wait=true \
    --gpus="0 1 2" \
    --sudo-passward "496666" \
    --feat-dir=$data/train \
    --ali-dir=$ali_dir \
    --lang=$data/lang \
    --reporting.email="$reporting_email" \
    --dir=$dir  || exit 1;
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
  for decode_set in non-native forum native; do
      decode_dir=${dir}/decode_${decode_set}
      if [ "$use_ivectors" == "true" ]; then
        ivector_opts=" --online-ivector-dir exp/nnet3/ivectors_${decode_set} "
      else
        ivector_opts=
      fi
      steps/nnet3/lstm/decode.sh --nj 6 --cmd "$decode_cmd" \
          $ivector_opts $model_opts \
          --extra-left-context $extra_left_context  \
          --extra-right-context $extra_right_context  \
          --frames-per-chunk "$frames_per_chunk" \
         $graph_dir $data/${decode_set} $decode_dir || exit 1 &
  done
  wait
fi

bash RESULTS

echo "$0 DONE!"
exit 0;
