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
exit_stage=1000000

speed_perturb=false

reporting_email=""

# LSTM options
splice_indexes="-2,-1,0,1,2 0 0"
lstm_delay=" [-1,1] [-2,2] [-3,3] "
label_delay=0
num_lstm_layers=3
cell_dim=512
hidden_dim=1024
recurrent_projection_dim=256
non_recurrent_projection_dim=256
chunk_width=20
chunk_left_context=40
chunk_right_context=20

# training options
num_epochs=5
initial_effective_lrate=0.0003
final_effective_lrate=0.00003

num_jobs_initial=3
num_jobs_final=3
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
decode_iter=final

shrink=0.99
max_param_change=2
warm_iters=0
cmvn_opts="--norm-means=true --norm-vars=true"

data=data_fbank_hires

ali_dir=exp/tri3_all_ali
ali_dir=exp/tri2b_all_ali
common_egs_dir=exp/nnet3/gru-bidirectional-ld0-mpc2/egs
graph_dir=exp/tri2b/graph_lang_biglm_tg

decode_sets="non-native forum"
decode_suffix=""

realign_times=""

python_train=true

suffix=

glb_cmvn=false

cv_period=20
get_egs_stage=0
gpus="0 1 2"
use_gpu=true

train_set=train
use_gru_layer=true

# End configuration section.

echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

# if ! cuda-compiled; then
#   cat <<EOF && exit 1
# This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
# If you want to use GPUs (and have them), go to src/, and configure and make on a machine
# where "nvcc" is installed.
# EOF
# fi


if [ "$speed_perturb" == "true" ]; then
  suffix=${suffix}_sp
fi

if $use_gru_layer;then
  dir=exp/nnet3/gru
else
  dir=exp/nnet3/lstm
fi

dir=$dir${affix:+-$affix}-ld${label_delay}-mpc${max_param_change}${suffix}
# dir=exp/nnet3/test
mkdir -p $dir

# make egs dir on /ssd
if [ $stage -le 5 ]; then
  if [ -z $common_egs_dir ];then
    egs_dir=/ssd/egs-fbank40-ld${label_delay}-clc${chunk_left_context}-crc${chunk_right_context}-chunk${chunk_width}
    [ ! -z ${extra_left_context} ] && egs_dir=${egs_dir}-elc${extra_left_context}
    [ ! -z ${extra_right_context} ] && egs_dir=${egs_dir}-erc${extra_right_context}
    egs_dir=${egs_dir}$suffix
    mkdir -p $egs_dir
    if [ -f $egs_dir/log/shuffle.100.log ];then
      common_egs_dir=$egs_dir
      # # TEST TO
      # rm -rf $dir/egs
      # cp -r $egs_dir $dir/egs || exit 1;
      # common_egs_dir=$dir/egs
    else
      rm -rf $dir/egs
      ln -s $egs_dir $dir/egs
    fi
  fi
fi

ivector_dir=""
if $use_ivectors && [ $stage -le 6 ]; then
  local/nnet3/run_ivector_common.sh --stage $stage \
    --speed-perturb $speed_perturb || exit 1;
  ivector_dir=exp/nnet3/ivectors_${train_set}
fi

chmod -R +x local

if $python_train;then
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
        --ali-dir $ali_dir \
        --recurrent-projection-dim 1024 \
        --non-recurrent-projection-dim 512 \
        --hidden-dim $hidden_dim \
        --norm-based-clipping true \
        --label-delay $label_delay \
        --gru-delay "$gru_delay" \
       $dir/configs || exit 1;
    else
      [ ! -z "$lstm_delay" ] && config_extra_opts+=(--lstm-delay "$lstm_delay")
      steps/nnet3/lstm/make_configs.py  "${config_extra_opts[@]}" \
        --feat-dir $data/${train_set} \
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
  fi

  if [ $stage -le 10 ]; then
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
      utils/create_split_dir.pl \
       /export/b0{3,4,5,6}/$USER/kaldi-data/egs/swbd-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
    fi

    steps/nnet3/train_rnn.py --stage=$train_stage --exit-stage=$exit_stage \
      --cmd="$decode_cmd" \
      --feat.online-ivector-dir=$ivector_dir \
      --feat.cmvn-opts="$cmvn_opts" \
      --trainer.num-epochs=$num_epochs \
      --trainer.samples-per-iter=$samples_per_iter \
      --trainer.optimization.num-jobs-initial=$num_jobs_initial \
      --trainer.optimization.num-jobs-final=$num_jobs_final \
      --trainer.optimization.initial-effective-lrate=$initial_effective_lrate \
      --trainer.optimization.final-effective-lrate=$final_effective_lrate \
      --trainer.optimization.shrink-value=0.99 \
      --trainer.rnn.num-chunk-per-minibatch=$num_chunk_per_minibatch \
      --trainer.optimization.momentum=$momentum \
      --trainer.max-param-change=${max_param_change} \
      --egs.chunk-width=$chunk_width \
      --egs.chunk-left-context=$chunk_left_context \
      --egs.chunk-right-context=$chunk_right_context \
      --egs.dir="$common_egs_dir" \
      --cleanup.remove-egs=$remove_egs \
      --cleanup.preserve-model-interval=100 \
      --use-gpu=$use_gpu \
      --warm-iters=$warm_iters \
      --gpus-wait=true \
      --gpus="$gpus" \
      --cv-period=$cv_period \
      --sudo-password="496666" \
      --feat-dir=$data/train \
      --ali-dir=$ali_dir \
      --lang=$data/lang \
      --reporting.email="$reporting_email" \
      --dir=$dir  || exit 1;
  fi
else
  if [ $stage -le 10 ]; then
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
      utils/create_split_dir.pl \
       /export/b0{3,5,6,7}/$USER/kaldi-data/egs/ami-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
    fi
    if [ "$use_ivectors" == "true" ]; then
      ivector_opts=" --online-ivector-dir exp/$mic/nnet3/ivectors_train_sp_hires "
    else
      ivector_opts=
    fi

    steps/nnet3/lstm/train.sh $ivector_opts \
      --glb-cmvn-lda $glb_cmvn --cv-period $cv_period \
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
      --egs-dir "$common_egs_dir" --remove-egs $remove_egs --get-egs-stage $get_egs_stage \
      --realign-times "$realign_times" \
      --num-gpus 3 --sudo-password "496666" \
      --exit-stage $exit_stage \
      $data/train $data/lang $ali_dir $dir  || exit 1;
  fi
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
  # echo "496666" | sudo -S nvidia-smi -c 0
  echo "496666" | sudo -S nvidia-smi -c 0
  model_opts=
  for decode_set in $decode_sets; do
      decode_dir=${dir}/decode_${decode_set}
      [ ! -z $decode_iter ] && model_opts=" --iter $decode_iter " && decode_dir=${decode_dir}_${decode_iter}${decode_suffix};
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
         $graph_dir $data/${decode_set} $decode_dir || exit 1;
  done
  wait
fi

bash RESULTS

echo "$0 DONE!"
exit 0;
