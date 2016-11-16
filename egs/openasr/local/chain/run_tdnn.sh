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
adapt_stage=0
cleanup=true

get_egs_stage=-10
egs_context_opts=""

common_stage=

decode_stage=0

affix=
common_egs_dir=

# label_delay=0
num_epochs=3
pruner_times=
pruner_perlayer=3
pruner_lambda=1

# training options
leftmost_questions_truncate=-1

TreeLeaves=4000
frame_subsampling_factor=3
tree_suffix=""
tree_dir=exp/chain/tri3_tree
tree_context_opts=""

frames_per_eg=150
xent_regularize=0.1
relu_dim=800
bottleneck_dim=
initial_effective_lrate=0.001
final_effective_lrate=0.0001

cmvn_opts="--norm-means=true --norm-vars=true"

train_set=train
exit_stage=

dir=
graph_dir=

decode_sets="forum non-native native"
suffix=

decode_suffix=""
decode_nj=12
decode_iter="final"
gpus="0 1 2"
splice_indexes="-1,0,1 -1,0,1,2 -3,0,3 -3,0,3 -3,0,3 -6,-3,0 0"
decode_opts=

online_cmvn=true
skip_decode=true
skip_train=false

egs_opts=

nnet_jobs=3
nnet_jobs_initial=0
nnet_jobs_final=0

extra_egs_dirs=

final_normalize_target=0.5
self_repair_scale=0.00001
mini_batch=128

data=data_fbank_hires
src_model=exp/tri3

ali_dir=exp/tri3_all_ali

lang=data_fbank_hires/lang_chain
ivector_dir=""

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

if [ -z $dir ];then
  dir=exp/chain/tdnn$suffix
fi

if [[ -z $tree_dir || ! -z $tree_suffix ]] ;then
  tree_dir=exp/chain/tri3_tree_${TreeLeaves}$tree_suffix
  echo "TreeDir is $tree_dir"
fi



if [ $stage -le 0 ]; then
  # utils/copy_data_dir.sh data/openasr-01/train data/openasr-01-train
  # utils/copy_data_dir.sh data/tedlium/train data/tedlium-train
  # utils/copy_data_dir.sh data/voxpop/train data/voxpop-train
  local/chain/run_chain_common.sh --stage $common_stage --min-seg-len 1.55 \
                                  --frames-per-eg $frames_per_eg \
                                  $max_wer_opt \
                                  --dir $dir \
                                  --treedir $treedir \
                                  --lang $lang || exit 1;
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

# if [ $stage -le 2 ]; then
#   # Build a tree using our new topology.
#   steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
#       --leftmost-questions-truncate $leftmost_questions_truncate \
#       --cmd "$train_cmd" $numTreeLeaves data_mfcc/train_all $lang $ali_dir $tree_dir
# fi

if [ $stage -le 8 ]; then
  # Build a tree using our new topology.
  steps/nnet3/chain/build_tree.sh --frame-subsampling-factor $frame_subsampling_factor  \
      --leftmost-questions-truncate -1 --context-opts "$tree_context_opts" \
      --cmd "$train_cmd" $TreeLeaves data_mfcc/train_all $lang exp/tri3_all_ali $tree_dir || exit 1;
fi

. $dir/vars || exit 1;

if [ $stage -le 9 ]; then
  echo "$0: creating neural net configs";
  bottleneck_dim_opts=""
  [ ! -z $bottleneck_dim ] && bottleneck_dim_opts="--bottleneck-dim $bottleneck_dim"
  steps/nnet3/tdnn/make_configs.py \
    --self-repair-scale-nonlinearity $self_repair_scale \
    --feat-dir $train_data_dir \
    --tree-dir $tree_dir \
    --relu-dim $relu_dim $bottleneck_dim_opts \
    --splice-indexes "$splice_indexes" \
    --use-presoftmax-prior-scale false \
    --xent-regularize $xent_regularize \
    --xent-separate-forward-affine true \
    --include-log-softmax false \
    --final-layer-normalize-target $final_normalize_target \
   $dir/configs || exit 1;
fi

# if [ -z $common_egs_dir ]; then
#   mkdir -p $dir/egs
#   if [ $stage -le 11 ];then
#     steps/nnet3/chain/train_get_egs.py --stage -10 \
#       --cmd "$decode_cmd" \
#       --chain.lm-opts="--num-extra-lm-states=2000" \
#       --feat.cmvn-opts "$cmvn_opts" \
#       --chain.frame-subsampling-factor $frame_subsampling_factor \
#       --chain.alignment-subsampling-factor $frame_subsampling_factor \
#       --egs.dir "" \
#       --egs.stage $get_egs_stage \
#       --egs.opts "--frames-overlap-per-eg 0 $egs_opts " \
#       --egs.chunk-width $frames_per_eg \
#       --egs.extra-egs-dirs "$extra_egs_dirs" \
#       --trainer.frames-per-iter 1500000 \
#       --feat-dir $train_data_dir \
#       --tree-dir $tree_dir \
#       --lat-dir $lat_dir \
#       --dir $dir  || exit 1;
#   fi
  
#   if [ ! -z $extra_egs_dirs  ];then
#     if [ ! -d $dir/egs_combine ];then
#       echo "Fail to combine Egs."
#       exit 1;
#     fi
#     common_egs_dir=$dir/egs_combine
#   else
#     if [ -f $dir/egs/.done ];then
#       common_egs_dir=$dir/egs
#     fi
#   fi
# fi

# if $skip_train;then
#   echo "Skip Training."
#   exit 0;
# fi

if [ $stage -le 12 ]; then
  if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
    utils/create_split_dir.pl \
     /export/b0{5,6,7,8}/$USER/kaldi-data/egs/ami-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
  fi
  mkdir -p $dir/egs
  touch $dir/egs/.nodelete # keep egs around when that run dies.
  mkdir -p $dir/log
  if [ $nnet_jobs_initial -eq 0 ];then
      nnet_jobs_initial=$nnet_jobs
  fi
  if [ $nnet_jobs_final -eq 0 ];then
      nnet_jobs_final=$nnet_jobs
  fi

  # --feat.online-ivector-dir "$ivector_dir" \
  exit_stage_opts=""
  [ ! -z $exit_stage ] && exit_stage_opts="--exit-stage $exit_stage"
  steps/nnet3/chain/train.py --stage $train_stage $exit_stage_opts \
    --adapt-stage $adapt_stage \
    --cmd "$decode_cmd" \
    --feat.cmvn-opts "$cmvn_opts" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.00005 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --chain.frame-subsampling-factor $frame_subsampling_factor \
    --chain.alignment-subsampling-factor $frame_subsampling_factor \
    --egs.dir "$common_egs_dir" \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0 $egs_opts " \
    --egs.chunk-width $frames_per_eg $egs_context_opts \
    --trainer.num-chunk-per-minibatch $mini_batch \
    --trainer.frames-per-iter 1500000 \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial $nnet_jobs_initial \
    --trainer.optimization.num-jobs-final $nnet_jobs_final \
    --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
    --trainer.optimization.final-effective-lrate $final_effective_lrate \
    --trainer.max-param-change 2.0 \
    --pruner.times "$pruner_times" \
    --pruner.per-layer $pruner_perlayer \
    --pruner.lambda $pruner_lambda \
    --cleanup.remove-egs false \
    --cleanup $cleanup \
    --feat-dir $train_data_dir \
    --tree-dir $tree_dir \
    --lat-dir $lat_dir \
    --use-gpu=true \
    --gpus-wait=true \
    --gpus="$gpus" \
    --sudo-password "496666" \
    --dir $dir  || exit 1;
fi

if $skip_decode;then
  exit 0;
fi

if [ -z $graph_dir ] && [ $stage -le 11 ]; then
  # Note: it might appear that this $lang directory is mismatched, and it is as
  # far as the 'topo' is concerned, but this script doesn't read the 'topo' from
  # the lang directory.
  if [ ! -f $dir/final.mdl ]; then
    cp $dir/$decode_iter.mdl $dir/final.mdl || exit 1;
  else
  fi
  utils/mkgraph.sh --self-loop-scale 1.0 --remove-oov data/lang_biglm_tg $dir $dir/graph_tg
  graph_dir=$dir/graph_tg
  fstrmsymbols --apply-to-output=true --remove-arcs=true "echo 3|" $graph_dir/HCLG.fst $graph_dir/HCLG.fst
fi

if [ $stage -le 12 ]; then
  echo "496666" | sudo -S nvidia-smi -c 0
  for decode_set in $decode_sets; do
    steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 $decode_opts  \
        --stage $decode_stage --iter $decode_iter \
        --nj $decode_nj --cmd "$decode_cmd" \
        --scoring-opts "--min-lmwt 5 " --online-cmvn $online_cmvn \
       $graph_dir data/${decode_set}_hires $dir/decode_${decode_iter}_${decode_set}${decode_suffix} || exit 1;

  done
fi

bash RESULTS | grep $dir

exit 0;
