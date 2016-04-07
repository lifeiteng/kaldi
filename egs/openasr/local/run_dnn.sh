#!/bin/bash

stage=10
exit_stage=11
train_stage=-10
use_gpu=true
njobs=6

data=data_fbank
num_epochs=5
realign_epochs=100

align_dir=tri3_ali
splice=5           # Temporal splicing
splice_step=1 
hiddim=512
prefix="dnn"

egs_dir="\"\""

weight_sil=false
silence_weight=1

graphdir=exp/tri3/graph_ug/
feature_type="fbank"
passwd="496666"

. cmd.sh
. ./path.sh
. ./utils/parse_options.sh
set -e

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

dir=$exp/$prefix_h5t${hiddim}_ReLU

if ${weight_sil};then
  dir=${dir}_WSIL
fi

mkdir -p $dir/log

${align_dir}=$exp/${${align_dir}}

echo "weight-sil=${weight_sil}" >$dir/weight_sil

echo ============================================================================
echo "                  Dropout No Pre-Training                                 "
echo ============================================================================
soft_dim=$(hmm-info --print-args=false $${align_dir}/final.mdl | grep pdfs | awk '{ print $NF }')

if [ $stage -le 3 ]; then
  echo "----------------- Bias Scales -----------------"
  # read the features
  feats="ark:copy-feats scp:$data/train/feats.scp ark:- |"

  echo -n "Getting feature dim : "
  feat_dim=$(feat-to-dim --print-args=false "$feats" -)
  echo $feat_dim

  # Generate the splice transform
  echo "Using splice +/- $splice , step $splice_step"
  feature_transform=$dir/tr_splice$splice-$splice_step.nnet
  utils/nnet/gen_splice.py --fea-dim=$feat_dim --splice=$splice --splice-step=$splice_step > $feature_transform

  # Renormalize the MLP input to zero mean and unit variance
  feature_transform_old=$feature_transform
  feature_transform=${feature_transform%.nnet}_cmvn-g.nnet
  echo "Renormalizing MLP input features into $feature_transform"

  #create a 10k utt subset for global cmvn estimates
  echo $passwd | sudo -S nvidia-smi -c 0
  sort -R $data/train/feats.scp | head -n 10000 | sort > $data/train/feats.scp.10k
  nnet-forward --use-gpu=yes $feature_transform_old "$(echo $feats | sed 's|feats\.scp|feats\.scp\.10k|')" \
    ark:- 2>$dir/log/cmvn_glob_fwd.log |\
  compute-cmvn-stats ark:- - | cmvn-to-nnet - - |\
  nnet-concat --binary=false $feature_transform_old - $feature_transform

  # MAKE LINK TO THE FINAL feature_transform, so the other scripts will find it ######
  [ -f $dir/final.feature_transform ] && unlink $dir/final.feature_transform
  (cd $dir; ln -s $(basename $feature_transform) final.feature_transform )
  
  ## bias_mat
  cat $dir/final.feature_transform | sed -n '5p' | cut -d" " -f1,2 --complement >$dir/bias.mat
  ## scales_mat
  cat $dir/final.feature_transform | sed -n '7p' | cut -d" " -f1,2 --complement >$dir/scales.mat

  # feat_dim=$(cat $dir/feat_dim) || exit 1;
  # ivector_dim=$(cat $dir/ivector_dim) || exit 1;
  echo $feat_dim >$dir/feat_dim
  echo 0 >$dir/ivector_dim

fi

if [ $stage -le 4 ]; then
  feat_dim=`cat $dir/feat_dim`
  input_dim=$[${feat_dim}*(2*$splice+1)]
  echo "$0: initializing neural net";
echo "SpliceComponent input-dim=$feat_dim left-context=$splice right-context=$splice const-component-dim=0
FixedBiasComponent  bias=$dir/bias.mat
FixedScaleComponent scales=$dir/scales.mat
AffineComponentPreconditionedOnline input-dim=${input_dim} output-dim=$hiddim alpha=4.0 num-samples-history=2000 update-period=4 rank-in=20 rank-out=80 max-change-per-sample=0.075 learning-rate=0.001 param-stddev=0.01 bias-stddev=0.0
RectifiedLinearComponent dim=$hiddim
AffineComponentPreconditionedOnline input-dim=$hiddim output-dim=$hiddim alpha=4.0 num-samples-history=2000 update-period=4 rank-in=20 rank-out=80 max-change-per-sample=0.075 learning-rate=0.001 param-stddev=0.01 bias-stddev=0.0
RectifiedLinearComponent dim=$hiddim
AffineComponentPreconditionedOnline input-dim=$hiddim output-dim=$hiddim alpha=4.0 num-samples-history=2000 update-period=4 rank-in=20 rank-out=80 max-change-per-sample=0.075 learning-rate=0.001 param-stddev=0.01 bias-stddev=0.0
RectifiedLinearComponent dim=$hiddim
AffineComponentPreconditionedOnline input-dim=$hiddim output-dim=$hiddim alpha=4.0 num-samples-history=2000 update-period=4 rank-in=20 rank-out=80 max-change-per-sample=0.075 learning-rate=0.001 param-stddev=0.01 bias-stddev=0.0
RectifiedLinearComponent dim=$hiddim
AffineComponentPreconditionedOnline input-dim=$hiddim output-dim=$hiddim alpha=4.0 num-samples-history=2000 update-period=4 rank-in=20 rank-out=80 max-change-per-sample=0.075 learning-rate=0.001 param-stddev=0.01 bias-stddev=0.0
RectifiedLinearComponent dim=$hiddim
AffineComponentPreconditionedOnline input-dim=$hiddim output-dim=$soft_dim alpha=4.0 num-samples-history=2000 update-period=4 rank-in=20 rank-out=80 max-change-per-sample=0.075 learning-rate=0.001 param-stddev=0.01 bias-stddev=0.01
SoftmaxComponent dim=$soft_dim
" > $dir/nnet.config || exit 1;

  nnet-am-init $${align_dir}/tree $data/lang/topo "nnet-init $dir/nnet.config -|" $dir/nnet2.mdl || exit 1;

  nnet-am-info $dir/nnet2.mdl
fi

dropout_layers="4:6:8:10:12:14:16"
dropout_layers="2:4:6:10:12"
dropout_proportions="0.1:0.2:0.3:0.2:0.2"

if [ $stage -le 11 ]; then
  echo $passwd | sudo -S nvidia-smi -c 1 

  local/nnet2/nnet_fine_tuning_std.sh --stage $train_stage \
    --egs-dir ${egs_dir} \
    --weight-sil ${weight_sil} --silence-weight ${silence_weight} \
    --multigpu true --gpunum 2 \
    --add-dropout false --add-dropout-epoch 3 --dropout-layers $dropout_layers \
    --dropout-proportions $dropout_proportions \
    --remove-dropout true --remove-dropout-epoch 5 \
    --nnet-file  $dir/nnet2.mdl \
    --feat-type raw \
    --splice-width $splice \
    --combine-num-threads 4 \
    --mix-up -100 \
    --cleanup true \
    --cmvn-opts "--norm-means=false --norm-vars=false" \
    --num-jobs-nnet 4 \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --num-epochs ${num_epochs} \
    --align-cmd "$train_cmd" --align-use-gpu "yes" --realign-epochs "${realign_epochs}" --num-jobs-align $njobs \
    --initial-learning-rate 0.001 --final-learning-rate 0.00001 \
    --cmd "$train_cmd" \
    $data/train $data/lang ${align_dir} $dir || exit 1;
    
  echo "Nnet2 fine tuning Done."
fi

if [ $stage -le 11 ]; then
  echo $passwd | sudo -S nvidia-smi -c 0
  steps/online/nnet2/prepare_online_decoding.sh --feature-type $feature_type \
    $data/lang $dir ${dir}_online || exit 1;

  steps/online/nnet2/decode.sh --use-gpu $use_gpu --config conf/decode.config --cmd "$decode_cmd" --nj $njobs \
    $graph_dir $data/test ${dir}_online/decode_test

fi

if [ 11 -gt ${exit_stage} ]; then
  exit 0;
fi

srcdir=$dir
egs_dir=${srcdir}/egs
dir=${srcdir}_NP

if [ $stage -le 20 ]; then
  echo "============Doing node pruning============"
  mkdir -p $dir/log
  log=$dir/log/node_pruning.log; 
  nnet-node-pruning --percent=0.3 --threshold=-1.0 --per-layer=true --onorm=true --inorm=false \
    $srcdir/final.mdl $dir/0.mdl 2> $log || exit 1;
fi

if [ $stage -le 21 ]; then
  echo "============Fine Tuning============"
  echo $passwd | sudo -S nvidia-smi -c 1 
  
  local/nnet2/nnet_fine_tuning_std.sh --stage $train_stage \
    --egs-dir $egs_dir \
    --nnet-file $dir/0.mdl \
    --multigpu true --gpunum 2 \
    --feat-type raw \
    --splice-width 5 \
    --combine-num-threads 4 \
    --mix-up -100 \
    --cleanup true \
    --cmvn-opts "--norm-means=false --norm-vars=false" \
    --num-jobs-nnet 4 \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --num-epochs 4 \
    --initial-learning-rate 0.0001 --final-learning-rate 0.00001 \
    --cmd "$train_cmd" \
    $data/train $data/lang ${align_dir} $dir || exit 1;
  
  echo "Nnet2 node pruning fine tuning Done."
fi

echo "Node Pruning Done."
dir_svd=${dir}_SVD256
mkdir -p ${dir_svd}/log

if [ $stage -le 30 ]; then
  echo "============Doing SVD============"
  log=$dir_svd/log/svd.log; 
  nnet-svd-all --percent=-1 --rank=256 --input=false \
    $dir/final.mdl $dir_svd/0.mdl 2> $log || exit 1;
fi

if [ $stage -le 31 ]; then
  echo "============Fine Tuning============"
  echo $passwd | sudo -S nvidia-smi -c 1 
  local/nnet2/nnet_fine_tuning_std.sh --stage $train_stage \
    --egs-dir $egs_dir \
    --nnet-file $dir_svd/0.mdl \
    --multigpu true --gpunum 2 \
    --feat-type raw \
    --splice-width 5 \
    --combine-num-threads 4 \
    --mix-up -100 \
    --cleanup true \
    --cmvn-opts "--norm-means=false --norm-vars=false" \
    --num-jobs-nnet 4 \
    --num-threads "$num_threads" \
    --minibatch-size "$minibatch_size" \
    --parallel-opts "$parallel_opts" \
    --num-epochs 4 \
    --initial-learning-rate 0.0001 --final-learning-rate 0.00001 \
    --cmd "$train_cmd" \
    $data/train $data/lang ${align_dir} ${dir_svd} || exit 1;
   
  echo "Nnet2 SVD fine tuning Done."
fi

if [ $stage -le 31 ]; then
  echo $passwd | sudo -S nvidia-smi -c 0
  steps/online/nnet2/prepare_online_decoding.sh --feature-type $feature_type \
    $data/lang $dir_svd ${dir_svd}_online || exit 1;

  steps/online/nnet2/decode.sh --use-gpu $use_gpu --config conf/decode.config --cmd "$decode_cmd" --nj $njobs \
    $graph_dir $data/test ${dir_svd}_online/decode_test

fi

exit 0;




