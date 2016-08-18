#!/bin/bash

iter=3000
start_iter=100

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
cp -r $src_dir/configs $dir
# for x in 0.trans_mdl;do
#     cp $src_dir/$x $dir || exit 1;
# done

echo $src_dir >$dir/.src

echo "$0: Done!"
