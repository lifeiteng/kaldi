#!/bin/bash


# This script does discriminative training on top of the online,
# system trained in run_nnet2.sh.
# note: this relies on having a cluster that has plenty of CPUs as well as GPUs,
# since the lattice generation runs in about real-time, so takes of the order of
# 1000 hours of CPU time.
# 
# Note: rather than using any features we have dumped on disk, this script
# regenerates them from the wav data three times-- when we do lattice
# generation, numerator alignment and discriminative training.  This made the
# script easier to write and more generic, because we don't have to know where
# the features and the iVectors are, but of course it's a little inefficient.
# The time taken is dominated by the lattice generation anyway, so this isn't
# a huge deal.

. cmd.sh

### Feiteng 2015.01.21 修改自 librispeech

nj=6
data=data_all_fbank
srcdir=ep0-exp/tri3_ali_fbank40_h5t2048_ReLU_NP_SVD256

dir=${srcdir}_DCT
graphdir=ep0-exp/tri3/graph_tg

online_ivector_dir=""
remove_precondition=false

stage=100
train_stage=-10
use_gpu=true
criterion=smbr #mpfe #mmi #smbr 
drop_frames=false  # only relevant for MMI actually.
learning_rate=0.00000001
train_stage=-10 # can be used to start training in the middle.
decode_start_epoch=0 # can be used to avoid decoding all epochs, e.g. if we decided to run more.
num_epochs=3
cleanup=false  # run with --cleanup true --stage 6 to clean up (remove large things like denlats,
               # alignments and degs).

set -e
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
else
  # Use 4 nnet jobs just like run_4d_gpu.sh so the results should be
  # almost the same, but this may be a little bit slow.
  num_threads=16
  parallel_opts="-pe smp $num_threads" 
fi


# echo "Re-adjusting priors based on computed posteriors"
# # x=636
# # cp $srcdir/$x.mdl $srcdir/final.mdl
# # mkdir -p $srcdir/log
# # run.pl $srcdir/log/adjust_priors.final.log nnet-adjust-priors $srcdir/final.mdl $srcdir/post.$x.vec $srcdir/final.mdl || exit 1;


if [ ! -f ${srcdir}/final.mdl ]; then
  echo "$0: expected ${srcdir}/final.mdl to exist; "
  exit 1;
fi


if [ $stage -le 1 ]; then
  echo "496666" | sudo -S nvidia-smi -c 0
  nj=6
  use_gpu="yes"
  gpu_opts=

  steps/nnet2/align.sh --careful true --stage -2 --beam 12 --retry-beam 18 --cmd "$decode_cmd $gpu_opts" --use-gpu "$use_gpu" \
     --nj $nj $data/train $data/lang $srcdir ${srcdir}_ali || exit 1;
fi

## --online-ivector-dir $online_ivector_dir \
if [ $stage -le 2 ]; then	
  nj=6  # this doesn't really affect anything strongly, except the num-jobs for one of
         # the phases of get_egs_discriminative2.sh below.
  num_threads_denlats=1
  subsplit=1 # number of jobs that run per job
  steps/nnet2/make_denlats.sh --cmd "$decode_cmd -l mem_free=1G,ram_free=1G -pe smp $num_threads_denlats" \
     --nj $nj --sub-split $subsplit --num-threads "$num_threads_denlats" --beam 15.0 --lattice-beam 6.0 \
     $data/train $data/lang $srcdir ${srcdir}_denlats || exit 1;
fi

if [ $stage -le 3 ]; then
  # have a higher maximum num-jobs if
  if [ -d ${srcdir}_degs/storage ]; then max_jobs=10; else max_jobs=6; fi

  steps/nnet2/get_egs_discriminative2.sh \
    --cmd "$decode_cmd -tc $max_jobs" \
    --criterion $criterion --drop-frames $drop_frames \
    $data/train $data/lang ${srcdir}{_ali,_denlats,/final.mdl,_degs} || exit 1;

fi

if [ $stage -le 4 ]; then
  echo "TODO discriminative."
  echo "496666" | sudo -S nvidia-smi -c 1 
  local/nnet2/train_discriminative2.sh --cmd "$decode_cmd $parallel_opts" \
    --multigpu true --gpunum 2 \
    --stage $train_stage \
    --learning-rate $learning_rate \
    --remove-precondition false \
    --criterion $criterion --drop-frames $drop_frames \
    --num-epochs $num_epochs \
    --num-jobs-nnet 4 --num-threads 1 \
    --src-model $srcdir/final.mdl \
    ${srcdir}_degs ${dir}_${criterion}_$learning_rate || exit 1;
fi

if [ $stage -le 10 ]; then
  echo "496666" | sudo -S nvidia-smi -c 0
  dir_svd=${dir}_${criterion}_$learning_rate
  echo $dir_svd
  bash test.sh --data $data --lang lang --datas "Mar-17-2015-forum" --iter epoch1 --prefix "NP_SVD256_" \
    --graphdir $graphdir --njobs 6 \
    --langs "lang_tg_dict"  --dnn-decode true ${dir_svd} || exit 1;
  bash test.sh --data $data --lang lang --datas "Mar-17-2015-forum" --iter epoch2 --prefix "NP_SVD256_" --graphdir $graphdir --njobs 6 \
    --langs "lang_tg_dict"  --dnn-decode true ${dir_svd} || exit 1;
  bash test.sh --data $data --lang lang --datas "Mar-17-2015-forum" --iter epoch3 --prefix "NP_SVD256_" --graphdir $graphdir  --njobs 6 \
    --langs "lang_tg_dict"  --dnn-decode true ${dir_svd} || exit 1;
fi

dir_svd=${dir}_${criterion}_$learning_rate
bash test.sh --data $data --lang lang --datas "read-aloud-non-native" --iter epoch1 --prefix "NP_SVD256_" \
    --graphdir $graphdir --njobs 6 \
    --langs "lang_tg_dict"  --dnn-decode true ${dir_svd} || exit 1;
bash test.sh --data $data --lang lang --datas "read-aloud-native" --iter epoch1 --prefix "NP_SVD256_" \
    --graphdir $graphdir --njobs 6 \
    --langs "lang_tg_dict"  --dnn-decode true ${dir_svd} || exit 1;
exit 0;
