#!/bin/bash


if [ $# != 2 ]; then
  echo "Usage: $0 <num-iters> <exp-dir> <exp-dir> <exp-dir>"
  echo " e.g.: $0 exp/chain/tdnn_a 1000"
  echo ""
  echo "Main options (for others, see top of script file)"

  exit 1;
fi


num_iters=$1
dir=$2

echo "$0: Removing most of the models for DIR: $dir"
for x in `seq 0 $num_iters`; do
	if [ $[$x%100] -ne 0 ] && [ $x -ne $num_iters ] && [ -f $dir/$x.mdl ]; then
	   # delete all but every 100th model; don't delete the ones which combine to form the final model.
	  rm $dir/$x.mdl
	fi
done


echo "$0: DONE!"
