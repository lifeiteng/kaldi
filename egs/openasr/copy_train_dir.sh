#!/bin/bash

iter=3000
start_iter=100
deep=false
fix_layer=""

. ./path.sh
. ./utils/parse_options.sh

set -e

if [ $# != 2 ]; then
  echo "Usage: "
  echo "  $0 [options] <src-dir> <dest-dir>"
  echo "e.g.:"
  echo " $0 exp/chain/tdnn_sp exp/chainnoise/tdnn_sp_clean"
  echo "Options"
  exit 1;
fi

src_dir=$1
dir=$2

mkdir -p $dir

cp $src_dir/{frame_subsampling_factor,cmvn_opts,tree} $dir
cp $src_dir/$iter.mdl $dir/$start_iter.mdl
rm -rf $dir/configs
cp -r $src_dir/configs $dir

if [ ! -z $fix_layer ];then
    nnet3-am-switch-fixedaffine $fix_layer $src_dir/$iter.mdl $dir/$start_iter.mdl >& $dir/fixlayer.log || exit 1;
fi

if $deep;then
    for x in 0.trans_mdl den.fst normalization.fst lda_stats;do
        cp $src_dir/$x $dir || exit 1;
    done
fi

echo $src_dir >$dir/.src

echo "$0: Done!"
