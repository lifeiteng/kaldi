#!/bin/bash

stage=1
train_stage=-10
use_gpu=true
dir=exp/nnet2_online/nnet_v0
njobs=4

. cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if $use_gpu; then
  if ! cuda-compiled; then
    cat <<EOF && exit 1 
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA 
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.  Otherwise, call this script with --use-gpu false
EOF
  fi
  parallel_opts="-l gpu=1" 
  num_threads=1
  minibatch_size=512
else
  # Use 4 nnet jobs just like run_4d_gpu.sh so the results should be
  # almost the same, but this may be a little bit slow.
  num_threads=16
  minibatch_size=128
  parallel_opts="-pe smp $num_threads" 
fi

echo ============================================================================
echo "                Data & Lexicon & Language Preparation                     "
echo ============================================================================
# #### 特征准备 TODO

# ## concatenate the .scp files together.
# for name in train test; do
#   for n in $(seq 4); do
#     cat mfcc40/raw_mfcc_$name.$n.scp || exit 1;
#   done > data/$name/feats.scp
#   ## 尽管online decoding不使用cmvn，这里为了一致仍然修改cmvn.scp
#   cp mfcc40/cmvn_$name.scp data/$name/cmvn.scp
# done
data=data_dnn

echo ============================================================================
echo "                     Nnet2 Training and Online Decode                     "
echo ============================================================================
graphdir=exp/tri3/graph_bg
aligndir=exp/tri3_ali
dir=exp/nnet2_online/nnet_v0

# align_cmd=              # The cmd that is passed to steps/nnet2/align.sh
# align_use_gpu=          # Passed to use_gpu in steps/nnet2/align.sh [yes/no]
# realign_epochs=         # List of epochs, the beginning of which realignment is done
# num_jobs_align=30       # Number of jobs for realignment

stage=4
if [ $stage -le 4 ]; then
  local/online/train_sigmoid_simple2_std.sh --stage $train_stage \
    --feat-type raw \
    --splice-width 5 \
    --hidden-layer-dim 2048 \
    --add-layers-period 10 \
    --num-hidden-layers 7 \
    --combine-num-threads 4 \
    --mix-up -100 \
    --cleanup false \
    --cmvn-opts "--norm-means=false --norm-vars=false" \
    --num-jobs-nnet 4 \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --num-epochs 25 \
    --initial-learning-rate 0.01 --final-learning-rate 0.004 \
    --cmd "$train_cmd" \
    --align-cmd "$train_cmd" --align-use-gpu "yes" --realign-epochs "5 10 15 20" --num-jobs-align 4 \
    $data/train $data/lang $aligndir $dir || exit 1;
fi

### Feiteng 在线解码准备(7) + 解码(8) 
if [ $stage -le 7 ]; then
  # If this setup used PLP features, we'd have to give the option --feature-type plp
  # to the script below.
  steps/online/nnet2/prepare_online_decoding.sh data/lang \
    "$dir" ${dir}_online || exit 1;
fi

if [ $stage -le 8 ]; then
  # do the actual online decoding with iVectors.
  steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $njobs \
    --chunk-length 0.05 $graphdir data/test ${dir}_online/decode_nodeprune
fi

exit 0;

echo ============================================================================
echo "                 Nnet2 Node-Pruning and Online Decode                     "
echo ============================================================================

# steps/nnet2/align.sh --nj $njobs --cmd "$train_cmd" --use-gpu "yes" \
#   data/train data/lang $dir ${dir)_ali || exit 1
####TODO
if [ ! -z "${realign_this_iter[$x]}" ]; then
  epoch=${realign_this_iter[$x]}

  echo "Getting average posterior for purposes of adjusting the priors."
  # Note: this just uses CPUs, using a smallish subset of data.
  # always use the first egs archive, which makes the script simpler;
  # we're using different random subsets of it.
  rm $dir/post.$x.*.vec 2>/dev/null
  $cmd JOB=1:$num_jobs_compute_prior $dir/log/get_post.$x.JOB.log \
    nnet-copy-egs --srand=JOB --frame=random ark:$prev_egs_dir/egs.1.ark ark:- \| \
    nnet-subset-egs --srand=JOB --n=$prior_subset_size ark:- ark:- \| \
    nnet-compute-from-egs "nnet-to-raw-nnet $dir/$x.mdl -|" ark:- ark:- \| \
    matrix-sum-rows ark:- ark:- \| vector-sum ark:- $dir/post.$x.JOB.vec || exit 1;

  sleep 3;  # make sure there is time for $dir/post.$x.*.vec to appear.

  $cmd $dir/log/vector_sum.$x.log \
    vector-sum $dir/post.$x.*.vec $dir/post.$x.vec || exit 1;
  rm $dir/post.$x.*.vec;

  echo "Re-adjusting priors based on computed posteriors"
  $cmd $dir/log/adjust_priors.$x.log \
    nnet-adjust-priors $dir/$x.mdl $dir/post.$x.vec $dir/$x.mdl || exit 1;

  sleep 2

  steps/nnet2/align.sh --nj $num_jobs_align --cmd "$align_cmd" --use-gpu $align_use_gpu \
    --transform-dir "$transform_dir" --online-ivector-dir "$online_ivector_dir" \
    --iter $x $data $lang $dir $dir/ali_$epoch || exit 1

  steps/nnet2/relabel_egs2.sh --cmd "$cmd" --iter $x $dir/ali_$epoch \
    $prev_egs_dir $cur_egs_dir || exit 1

  if $cleanupegs && $cleanup && [[ $prev_egs_dir =~ $dir/egs* ]]; then
    steps/nnet2/remove_egs.sh $prev_egs_dir
  fi
fi


aligndir=${dir)_ali 

train_stage=-10
dir_np=${dir}_nodeprune
if [ $stage -le 5 ]; then
  ### Node pruning method -- Reference paper: RESHAPING DEEP NEURAL NETWORK FOR FAST DECODING BY NODE-PRUNING
  local/nnet2/nnet_node_pruning_std.sh --stage $train_stage \
    --egs-dir $dir/egs_20 \
    --mix-up -100 \
    --cleanup true \
    --num-jobs-nnet 4 \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --num-epochs 5 \
    --initial-learning-rate 0.004 --final-learning-rate 0.0004 \
    --cmd "$decode_cmd" \
    --percent 0.3 --onorm true --retrain true data/train data/lang $aligndir $dir $dir_np
fi

### Feiteng 在线解码准备(7) + 解码(8) 
if [ $stage -le 7 ]; then
  # If this setup used PLP features, we'd have to give the option --feature-type plp
  # to the script below.
  steps/online/nnet2/prepare_online_decoding.sh data/lang \
    "$dir" ${dir_np}_online || exit 1;
fi

if [ $stage -le 8 ]; then
  # do the actual online decoding with iVectors.
  steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $njobs \
    --chunk-length 0.05 $graphdir data/test ${dir_np}_online/decode_nodeprune
fi

echo ============================================================================
echo "           Nnet2 Node-Pruning (twice) and Online Decode                   "
echo ============================================================================

TODO
##aligndir=
train_stage=-10
dir_np=${dir_np}2
if [ $stage -le 5 ]; then
  ### Node pruning method -- Reference paper: RESHAPING DEEP NEURAL NETWORK FOR FAST DECODING BY NODE-PRUNING
  local/nnet2/nnet_node_pruning_std.sh --stage $train_stage \
    --egs-dir $dir/egs_20 \
    --mix-up -100 \
    --cleanup true \
    --num-jobs-nnet 4 \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --num-epochs 5 \
    --initial-learning-rate 0.0008 --final-learning-rate 0.0001 \
    --cmd "$decode_cmd" \
    --percent 0.3 --onorm true --retrain true data/train data/lang $aligndir $dir $dir_np
fi

dir=${dir_np}

### Feiteng 在线解码准备(7) + 解码(8) 
if [ $stage -le 7 ]; then
  # If this setup used PLP features, we'd have to give the option --feature-type plp
  # to the script below.
  steps/online/nnet2/prepare_online_decoding.sh data/lang \
    "$dir" ${dir}_online || exit 1;
fi

if [ $stage -le 8 ]; then
  # do the actual online decoding with iVectors.
  steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $njobs \
    --chunk-length 0.05 $graphdir data/test ${dir}_online/decode_nodeprune2
fi


echo ============================================================================
echo "                       Nnet2 SVD and Online Decode                        "
echo ============================================================================

TODO
##aligndir=
train_stage=-10
dir_svd=${dir}_svd
if [ $stage -le 5 ]; then
  ### Node pruning method -- Reference paper: RESHAPING DEEP NEURAL NETWORK FOR FAST DECODING BY NODE-PRUNING
  local/nnet2/nnet_node_pruning_std.sh --stage $train_stage \
    --egs-dir $dir/egs \
    --mix-up -100 \
    --cleanup true \
    --num-jobs-nnet 4 \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --num-epochs 5 \
    --initial-learning-rate 0.004 --final-learning-rate 0.0004 \
    --cmd "$decode_cmd" \
    --percent 0.3 --onorm true --retrain true data/train data/lang $aligndir $dir $dir_svd
fi

dir=${dir_svd}

### Feiteng 在线解码准备(7) + 解码(8) 
if [ $stage -le 7 ]; then
  # If this setup used PLP features, we'd have to give the option --feature-type plp
  # to the script below.
  steps/online/nnet2/prepare_online_decoding.sh data/lang \
    "$dir" ${dir}_online || exit 1;
fi

if [ $stage -le 8 ]; then
  # do the actual online decoding with iVectors.
  steps/online/nnet2/decode.sh --config conf/decode.config --cmd "$decode_cmd" --nj $njobs \
    --chunk-length 0.05 $graphdir data/test ${dir}_online/decode_nodeprune
fi






echo "========    WER       =========="
bash RESULTS dev

for x in exp/nnet2_online/{nnet_v1,nnet_v1_online,nnet_v1_nodeprune,nnet_v1_nodeprune_online}/decode*; do 
	[ -d $x ] && echo $x | grep "${1:-.*}" >/dev/null && grep WER $x/wer_* 2>/dev/null | utils/best_wer.sh; 
done

echo "========Real Time Rate=========="
### real-time factor
for x in exp/{mono,tri,sgmm,dnn,combine}*/decode*; do 
	[ -d $x ] && echo $x | grep "${1:-.*}" >/dev/null && grep "real-time" $x/log/decode.*.log 2>/dev/null
done

for x in exp/nnet2_online/{nnet_v1,nnet_v1_online,nnet_v1_nodeprune,nnet_v1_nodeprune_online}/decode*; do 
	[ -d $x ] && echo $x | grep "${1:-.*}" >/dev/null && grep "real-time" $x/log/decode.*.log 2>/dev/null
done


exit 0;

## TODO update results (Feiteng)
## TODO
# the experiment (with GPU)
#for x in exp/nnet2_online/nnet_a/decode*; do grep WER $x/wer_* | utils/best_wer.sh; done
%WER 2.20 [ 276 / 12533, 37 ins, 61 del, 178 sub ] exp/nnet2_online/nnet_a/decode/wer_5
%WER 10.22 [ 1281 / 12533, 143 ins, 193 del, 945 sub ] exp/nnet2_online/nnet_a/decode_ug/wer_10

# This is the baseline with spliced non-CMVN cepstra and no iVector input. 
# The difference is pretty small on RM; I expect it to be more clear-cut on larger corpora.
%WER 2.30 [ 288 / 12533, 35 ins, 57 del, 196 sub ] exp/nnet2_online/nnet_gpu_baseline/decode/wer_5
%WER 10.98 [ 1376 / 12533, 121 ins, 227 del, 1028 sub ] exp/nnet2_online/nnet_gpu_baseline/decode_ug/wer_10
 # and this is the same (baseline) using truly-online decoding; it probably only differs because
 # of slight decoding-parameter differences.
 %WER 2.31 [ 290 / 12533, 34 ins, 57 del, 199 sub ] exp/nnet2_online/nnet_gpu_baseline_online/decode/wer_5
 %WER 10.93 [ 1370 / 12533, 142 ins, 202 del, 1026 sub ] exp/nnet2_online/nnet_gpu_baseline_online/decode_ug/wer_9


# This is the online decoding.
# This truly-online per-utterance decoding gives essentially the same WER as the offline decoding, which is
# as we expect as the features and decoding parameters are the same.
# for x in exp/nnet2_online/nnet_gpu_online/decode*utt; do grep WER $x/wer_* | utils/best_wer.sh; done
%WER 2.28 [ 286 / 12533, 66 ins, 39 del, 181 sub ] exp/nnet2_online/nnet_a_online/decode_per_utt/wer_2
%WER 10.45 [ 1310 / 12533, 106 ins, 241 del, 963 sub ] exp/nnet2_online/nnet_a_online/decode_ug_per_utt/wer_12

# The following are online decoding, as above, but using previous utterances of
# the same speaker to refine the adaptation state.  It doesn't make much difference.
# for x in exp/nnet2_online/nnet_gpu_online/decode*; do grep WER $x/wer_* | utils/best_wer.sh; done | grep -v utt
%WER 2.27 [ 285 / 12533, 42 ins, 62 del, 181 sub ] exp/nnet2_online/nnet_a_online/decode/wer_5
%WER 10.26 [ 1286 / 12533, 140 ins, 188 del, 958 sub ] exp/nnet2_online/nnet_a_online/decode_ug/wer_10







