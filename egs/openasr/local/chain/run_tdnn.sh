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

# label_delay=0
num_epochs=3

# training options
leftmost_questions_truncate=-1
numTreeLeaves=5000

frames_per_eg=150
xent_regularize=0.1
relu_dim=800
bottleneck_dim=2048

train_set=train
exit_stage=100000

dir=exp/chain/tdnn
graph_dir=

decode_sets="forum non-native"
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

dir=$dir${affix:+_$affix}
# if [ $label_delay -gt 0 ]; then dir=${dir}_ld$label_delay; fi
dir=${dir}$suffix
mkdir -p $dir/egs

data=data_fbank_hires

src_model=exp/tri3
lats_dir=exp/tri3_all_lats

ali_dir=exp/tri3_all_ali
tree_dir=exp/chain/tri3_tree
lang=$data/lang_chain
ivector_dir=""

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

  steps/nnet3/tdnn/make_configs.py \
    --self-repair-scale 0.00001 \
    --feat-dir $data/$train_set \
    --tree-dir $tree_dir \
    --relu-dim $relu_dim \
    --bottleneck-dim $bottleneck_dim \
    --splice-indexes "$splice_indexes" \
    --use-presoftmax-prior-scale false \
    --xent-regularize $xent_regularize \
    --xent-separate-forward-affine true \
    --include-log-softmax false \
    --final-layer-normalize-target 1.0 \
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
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial 2 \
    --trainer.optimization.num-jobs-final 2 \
    --trainer.optimization.initial-effective-lrate 0.001 \
    --trainer.optimization.final-effective-lrate 0.0001 \
    --trainer.max-param-change 2.0 \
    --cleanup.remove-egs false \
    --feat-dir $data/$train_set \
    --tree-dir $tree_dir \
    --lat-dir $lats_dir \
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
  utils/mkgraph.sh --self-loop-scale 1.0 $data/lang_biglm_tg $dir $dir/graph_tg
  graph_dir=$dir/graph_tg
fi

if [ $stage -le 19 ]; then
  echo "496666" | sudo -S nvidia-smi -c 0
  for decode_set in $decode_sets; do
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 $decode_opts  \
        --stage $decode_stage --iter $decode_iter \
        --nj $decode_nj --cmd "$decode_cmd" \
        --scoring-opts "--min-lmwt 5 " \
       $graph_dir $data/${decode_set} $dir/decode_${decode_iter}_${decode_set}${decode_suffix} || exit 1;
  done
fi

bash RESULTS | grep $dir

exit 0;
