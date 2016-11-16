#!/bin/bash

# set -o pipefail
# set -e
# # this is run_discriminative.sh

# This script does discriminative training on top of chain nnet3 system.
# note: this relies on having a cluster that has plenty of CPUs as well as GPUs,
# since the lattice generation runs in about real-time, so takes of the order of
# 1000 hours of CPU time.
# 

stage=10
train_stage=-10 # can be used to start training in the middle.
get_egs_stage=-10
use_gpu=true  # for training
cleanup=false  # run with --cleanup true --stage 6 to clean up (remove large things like denlats,
               # alignments and degs).
nj=40

suffix=""
dir_suffix=""
graph_dir=exp/chain/tdnn/graph_tg
rescore=false

srcdir=exp/chain/tdnn_sp

online_ivector_dir=
degs_dir=                     # If provided, will skip the degs directory creation
lats_dir=                     # If provided, will skip denlats creation

## Objective options
criterion=smbr
one_silence_class=true

## Egs options
frames_per_eg=150
frames_overlap_per_eg=30
truncate_deriv_weights=10

## Nnet training options
effective_learning_rate=0.00000125
max_param_change=1
num_jobs_nnet=4
num_epochs=4
regularization_opts="--xent-regularize=0.1 --l2-regularize=0.00005"          # Applicable for providing --xent-regularize and --l2-regularize options 
minibatch_size=64 
last_layer_factor=0.1         

extra_left_context=15
extra_right_context=15

## Decode options
decode_start_epoch=1 # can be used to avoid decoding all epochs, e.g. if we decided to run more.
decode_iters=""
decode_nj=12
decode_sets="telis2-asr-test-data non-native-readaloud native-readaloud forum"  #"forum  native-readaloud "
decode_suffix="_peruser"


echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

dir=${srcdir}_${criterion}${suffix}${dir_suffix}

. $srcdir/vars
# sets the directory names where features, ivectors and lattices are stored
#train_data_dir
#train_ivector_dir
#lat_dir

if $use_gpu; then
  if ! cuda-compiled; then
    cat <<EOF && exit 1 
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA 
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.  Otherwise, call this script with --use-gpu false
EOF
  fi
  num_threads=1
else
  # Use 4 nnet jobs just like run_4d_gpu.sh so the results should be
  # almost the same, but this may be a little bit slow.
  num_threads=1
fi

if [ ! -f ${srcdir}/final.mdl ]; then
  echo "$0: expected ${srcdir}/final.mdl to exist; first run run_tdnn.sh or run_lstm.sh"
  exit 1;
fi


lang=data/lang

frame_subsampling_opt=
frame_subsampling_factor=1
if [ -f $srcdir/frame_subsampling_factor ]; then
  frame_subsampling_factor=$(cat $srcdir/frame_subsampling_factor)
  frame_subsampling_opt="--frame-subsampling-factor $(cat $srcdir/frame_subsampling_factor)"
fi

affix=    # Will be set if doing input frame shift
if [ $frame_subsampling_factor -ne 1 ]; then
  train_data_dir=data/train_sp_min1.55_hires_subset
  if [ $stage -le -1 ]; then
    # wc -l data/*55_hires/text
    #  3944473 data/openasr-01-train_sp_min1.55_hires/text
    #   159222 data/tedlium-train_sp_min1.55_hires/text
    #  5652547 data/train_sp_min1.55_hires/text
    #  1548852 data/voxpop-train_sp_min1.55_hires/text
    utils/subset_data_dir.sh data/openasr-01-train_sp_min1.55_hires 1000000 tmp/data/openasr-01-train_sp_min1.55_hires_1000k || exit 1;
    utils/subset_data_dir.sh data/voxpop-train_sp_min1.55_hires 500000 tmp/data/voxpop-train_sp_min1.55_hires_500k || exit 1;
    utils/combine_data.sh --skip-fix true ${train_data_dir} \
      tmp/data/openasr-01-train_sp_min1.55_hires_1000k \
      tmp/data/voxpop-train_sp_min1.55_hires_500k \
      data/tedlium-train_sp_min1.55_hires
  fi

  if [ $stage -le 0 ]; then
    data_dirs=
    for x in `seq -$[frame_subsampling_factor/2] $[frame_subsampling_factor/2]`; do 
      steps/shift_feats.sh --cmd "$train_cmd --max-jobs-run 40" --nj $nj \
        $x $train_data_dir exp/shift_hires mfcc_hires
      # utils/fix_data_dir.sh ${train_data_dir}_fs$x
      data_dirs="$data_dirs ${train_data_dir}_fs$x"
    done
    utils/combine_data.sh --skip-fix true ${train_data_dir}_fs $data_dirs
    for x in `seq -$[frame_subsampling_factor/2] $[frame_subsampling_factor/2]`; do 
      rm -r ${train_data_dir}_fs$x
    done
  fi

  train_data_dir=${train_data_dir}_fs
  affix=_fs$suffix
fi


if [ $stage -le 5 ]; then
  # hardcode no-GPU for alignment, although you could use GPU [you wouldn't
  # get excellent GPU utilization though.]
  if $use_gpu;then
    echo "496666" | sudo -S nvidia-smi -c 0
  fi
  steps/nnet3/align.sh  --cmd "$decode_cmd" --use-gpu $use_gpu \
    --online-ivector-dir "$online_ivector_dir" \
    --scale-opts "--transition-scale=1.0 --acoustic-scale=1.0 --self-loop-scale=1.0" \
    --nj $nj $train_data_dir $lang $srcdir ${srcdir}_ali${affix}
fi

if [ -z "$lats_dir" ]; then
  lats_dir=${srcdir}_denlats${affix}
  if [ $stage -le 6 ]; then
    # this doesn't really affect anything strongly, except the num-jobs for one of
    # the phases of get_egs_discriminative.sh below.
    num_threads_denlats=1
    subsplit=1 # number of jobs that run per job (but 2 run at a time, so total jobs is 80, giving
    # total slots = 80 * 6 = 480.
    steps/nnet3/make_denlats.sh --cmd "$decode_cmd" \
      --self-loop-scale 1.0 --acwt 1.0 --determinize true \
      --nj $nj --sub-split $subsplit --num-threads "$num_threads_denlats" --config conf/decode.config \
      $train_data_dir $lang $srcdir ${lats_dir} ;
  fi
fi

model_left_context=`nnet3-am-info $srcdir/final.mdl | grep "left-context:" | awk '{print $2}'` 
model_right_context=`nnet3-am-info $srcdir/final.mdl | grep "right-context:" | awk '{print $2}'` 

left_context=$[model_left_context + extra_left_context]
right_context=$[model_right_context + extra_right_context]

valid_left_context=$[valid_left_context + frames_per_eg]
valid_right_context=$[valid_right_context + frames_per_eg]

cmvn_opts=`cat $srcdir/cmvn_opts` 

if [ -z "$degs_dir" ]; then
  degs_dir=${srcdir}_degs${affix}

  if [ $stage -le 8 ]; then
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d ${srcdir}_degs/storage ]; then
      utils/create_split_dir.pl \
        /export/b{01,02,12,13}/$USER/kaldi-data/egs/swbd-$(date +'%m_%d_%H_%M')/s5/${srcdir}_degs/storage ${srcdir}_degs/storage
    fi
    # have a higher maximum num-jobs if
    if [ -d ${srcdir}_degs/storage ]; then max_jobs=10; else max_jobs=$nj; fi

    degs_opts="--determinize true --minimize true --remove-output-symbols true --remove-epsilons true --collapse-transition-ids true"

    steps/nnet3/get_egs_discriminative.sh \
      --cmd "$decode_cmd " --max-jobs-run 10 --max-shuffle-jobs-run $max_jobs \
      --stage $get_egs_stage --cmvn-opts "$cmvn_opts" \
      --adjust-priors false --acwt 1.0 \
      --online-ivector-dir "$online_ivector_dir" \
      --left-context $left_context --right-context $right_context \
      --valid-left-context $valid_left_context --valid-right-context $valid_right_context \
      --priors-left-context $valid_left_context --priors-right-context $valid_right_context $frame_subsampling_opt \
      --frames-per-eg $frames_per_eg --frames-overlap-per-eg $frames_overlap_per_eg ${degs_opts} \
      $train_data_dir $lang ${srcdir}_ali${affix} $lats_dir $srcdir/final.mdl $degs_dir ;
    exit 0;
  fi
fi

if [ $stage -le 10 ]; then
  echo "496666" | sudo -S nvidia-smi -c 1
  steps/nnet3/train_discriminative.sh --cmd "$decode_cmd" \
    --stage $train_stage --src-model $srcdir/final.mdl \
    --effective-lrate $effective_learning_rate --max-param-change $max_param_change \
    --criterion $criterion --drop-frames true --acoustic-scale 1.0 \
    --num-epochs $num_epochs --one-silence-class $one_silence_class --minibatch-size $minibatch_size \
    --num-jobs-nnet $num_jobs_nnet --num-threads $num_threads \
    --regularization-opts "$regularization_opts" --use-frame-shift false \
    --truncate-deriv-weights $truncate_deriv_weights --adjust-priors false \
      ${degs_dir} $dir ;
fi

if [[ $stage -le 11 &&  ! -z $decode_iters ]]; then
  echo "496666" | sudo -S nvidia-smi -c 0
  cmvn_scp=data/train_sp_min1.55_hires/cmvn.scp.sub10k
  for x in $decode_iters; do
      iter=$x
      if ! $rescore;then
        for decode_set in $decode_sets;do
          local/decode/online_decode.sh --decode-sets "$decode_set" --decode-nj $decode_nj --graph-dir $graph_dir \
            --data asr-testsets/eng --decode-iter $iter \
            --online-cmvn-opts " --online-cmvn true --cmvn-scp $cmvn_scp " \
            --feat-config "--feature-type mfcc --mfcc-config conf/mfcc_hires_decode.conf"  \
            --decode-suffix "$decode_suffix" --chain true --scoring-opts "--min-lmwt 5 " \
            $dir &
          sleep 50
        done
      else
        echo "$0: rescoring"
        for decode_set in $decode_sets;do
          src_decode_dir=${dir}_online/decode_${iter}_${decode_set}${decode_suffix}
          if [ ! -d $src_decode_dir ];then
            echo "$0: decode dir not exist." && exit 1
          fi
          local/decode/lmrescore.sh \
            --decode-iter $iter asr-testsets/eng/$decode_set $graph_dir $src_decode_dir ${src_decode_dir}_rescore &
          sleep 50
        done
      fi
  done
  wait
fi

if [ $stage -le 6 ] && $cleanup; then
  # if you run with "--cleanup true --stage 6" you can clean up.
  rm ${lats_dir}/lat.*.gz || true
  rm ${srcdir}_ali/ali.*.gz || true
  steps/nnet2/remove_egs.sh ${srcdir}_degs || true
fi


exit 0;

