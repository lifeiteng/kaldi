#!/bin/bash

# Copyright 2016  Feiteng
# Apache 2.0

# It copies to another directory, possibly adding a specified prefix or a suffix
# to the utterance names.
#


# begin configuration section
utt_prefix=
utt_suffix=
validate_opts=   # should rarely be needed.
# End configuration section.
echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. utils/parse_options.sh

if [ $# != 2 ]; then
  echo "Usage: "
  echo "  $0 [options] <srcdir> <destdir>"
  echo "e.g.:"
  echo " $0 --utt-suffix=_1 data/train data/train_1"
  echo "Options"
  echo "   --utt-prefix=<prefix>     # Prefix for utterance ids, default empty"
  echo "   --utt-suffix=<suffix>     # Suffix for utterance ids, default empty"
  exit 1;
fi

export LC_ALL=C

srcdir=$1
destdir=$2

if [ ! -f $dir/lat.1.gz ]; then
  echo "$0: check if lattices (lat.*.gz) are present in $dir."
  exit 1;
fi

mkdir -p $destdir

for f in final.mdl tree cmvn_opts num_jobs splice_opts $extra_files; do
  if [ ! -f $srcdir/$f ]; then
    echo "$0: no such file $srcdir/$f"
    exit 1;
  fi
  cp $srcdir/$f $dest/
done

num_jobs=$(cat $srcdir/num_jobs) || exit 1;
if [[ -z $utt_prefix && -z $utt_suffix ]];then
  echo "$0: Just copy lattices."
  for i in `seq 1 $num_jobs`; do
      cp $srcdir/lat.$i.gz $dest/lat.$i.gz || exit 1 &
  done
  wait
else
  echo "$0: --utt-prefix=$utt_prefix --utt-suffix=$utt_suffix"
  for i in `seq 1 $num_jobs`; do
      lattice-copy --utt-prefix=$utt_prefix --utt-suffix=$utt_suffix \
        "ark:gunzip -c $srcdir/lat.$i.gz |" "ark:|gzip -c >$dest/lat.$i.gz" || exit 1 &
  done
  wait
fi

echo "$0: Copy lattices to $dest DONE!"
exit 0
