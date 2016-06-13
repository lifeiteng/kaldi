#!/bin/bash

# Copyright 2016  Liulishuo (author: Feiteng)
# Apache 2.0

# begin configuration section
copy_configs=false
copy_egs=false

# end configuration section

. utils/parse_options.sh

if [ $# != 2 ]; then
  echo "Usage: "
  echo "  $0 [options] <srcdir> <destdir>"
  echo "e.g.:"
  echo " $0 exp/nnet3/tdnn exp/nnet3/tdnn-BN"
  echo "Options"
  echo "   --copy-configs false|true          # Copy configs"
  echo "   --copy-egs     false|true          # Copy egs"
  exit 1;
fi

srcdir=$1
destdir=$2
mkdir -p $destdir/configs

for f in 0.raw 0.mdl cmvn_opts init.raw lda.mat lda_stats num_jobs pdf_counts presoftmax_prior_scale.vec tree;do
  if [ ! -f $srcdir/$f ]; then
    echo "$0: no such file $srcdir/$f"
    exit 1;
  fi
  cp $srcdir/$f $destdir || exit 1;
done

if $copy_configs;then
  if [ ! -d $srcdir/configs ];then
    echo "$0: no such dir $srcdir/configs"
    exit 1;
  fi
  cp -r $srcdir/configs $destdir || exit 1;
fi

rm -f $destdir/configs/presoftmax_prior_scale.vec || exit 1;
mv $destdir/presoftmax_prior_scale.vec $destdir/configs || exit 1;

if $copy_egs;then
  if [ ! -d $srcdir/egs ];then
    echo "$0: no such dir $srcdir/egs"
    exit 1;
  fi
  cp -r $srcdir/egs $destdir || exit 1;
fi

exit 0
