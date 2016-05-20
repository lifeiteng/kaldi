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
common_stage=0

train_stage=-10
get_egs_stage=-10
decode_stage=1

affix=
common_egs_dir=

# label_delay=0
num_epochs=3

# training options
frames_per_eg=150
xent_regularize=0.1
relu_dim=800
bottleneck_dim=1024
cmvn_opts="--norm-means=false --norm-vars=false"
max_wer=

exit_stage=100000

dir=exp/chain/tdnn
graph_dir=

decode_sets="spontaneous-forum_hires readaloud-non-native_hires readaloud-native_hires"
suffix=

decode_suffix=""
decode_nj=6
decode_iter="final"
gpus="0 1 2"
splice_indexes="-1,0,1 -1,0,1,2 -3,0,3 -3,0,3 -3,0,3 -6,-3,0 0"
decode_opts=

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

suffix=_sp$suffix

dir=${dir}${affix:+_$affix}
dir=${dir}$suffix

treedir=exp/chain/tri3_f_tree$suffix

lang=data/lang_chain_f
max_wer_opt=${max_wer:+" --max-wer $max_wer "}

chmod -R +x local

if [ $stage -le 0 ]; then
  # utils/copy_data_dir.sh data/openasr-01/train data/openasr-01-train
  # utils/copy_data_dir.sh data/tedlium/train data/tedlium-train
  # utils/copy_data_dir.sh data/voxpop/train data/voxpop-train
  local/chain/run_chain_common.sh --stage $common_stage \
                                  --frames-per-eg $frames_per_eg \
                                  $max_wer_opt \
                                  --dir $dir \
                                  --treedir $treedir \
                                  --lang $lang || exit 1;
fi

. $dir/vars
# sets the directory names where features, ivectors and lattices are stored
#train_data_dir
#train_ivector_dir
#lat_dir

if [ $stage -le 9 ]; then
  echo "$0: creating neural net configs";

  steps/nnet3/tdnn/make_configs.py \
    --self-repair-scale 0.00001 \
    --feat-dir $train_data_dir \
    --tree-dir $treedir \
    --relu-dim $relu_dim \
    --bottleneck-dim $bottleneck_dim \
    --splice-indexes "$splice_indexes" \
    --use-presoftmax-prior-scale false \
    --xent-regularize $xent_regularize \
    --xent-separate-forward-affine true \
    --include-log-softmax false \
    --final-layer-normalize-target 0.5 \
   $dir/configs || exit 1;
fi

if [ $stage -le 10 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{5,6,7,8}/$USER/kaldi-data/egs/ami-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi
  touch $dir/egs/.nodelete # keep egs around when that run dies.

  # --feat.online-ivector-dir "$ivector_dir" \
  steps/nnet3/chain/train.py --stage $train_stage --exit-stage ${exit_stage} \
    --cmd "$decode_cmd" \
    --feat.cmvn-opts "$cmvn_opts" \
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
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial 3 \
    --trainer.optimization.num-jobs-final 3 \
    --trainer.optimization.initial-effective-lrate 0.001 \
    --trainer.optimization.final-effective-lrate 0.0001 \
    --trainer.max-param-change 2.0 \
    --cleanup.remove-egs false \
    --feat-dir $train_data_dir \
    --tree-dir $treedir \
    --lat-dir $lat_dir \
    --use-gpu=true \
    --gpus-wait=true \
    --gpus="$gpus" \
    --sudo-password "496666" \
    --dir $dir  || exit 1;
fi

if [ -z $graph_dir ] && [ $stage -le 18 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  utils/mkgraph.sh --self-loop-scale 1.0 --remove-oov data/lang_biglm_tg $dir $dir/graph_tg
  graph_dir=$dir/graph_tg
  # fstrmsymbols --apply-to-output=true --remove-arcs=true "echo 3|" $graph_dir/HCLG.fst $graph_dir/HCLG.fst
fi

if [ $stage -le 19 ]; then
  echo "496666" | sudo -S nvidia-smi -c 0
  for decode_set in $decode_sets; do
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 $decode_opts  \
        --stage $decode_stage --iter $decode_iter \
        --nj $decode_nj --cmd "$decode_cmd" \
        --scoring-opts "--min-lmwt 5 " \
       $graph_dir data/${decode_set}_hires $dir/decode_${decode_iter}_${decode_set}${decode_suffix} || exit 1;
  done
fi

bash RESULTS | grep $dir

exit 0;
