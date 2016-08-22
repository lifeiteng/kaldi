#!/bin/bash
# Copyright 2016  Feiteng  Apache 2.0.

# This srcipt operates on lattices directories, such as exp/tri4a_lats
# the output is a new lattices dir which has lattices from all the input lattices dirs

# Begin configuration section.
cmd=run.pl
extra_files=
num_jobs=10
# End configuration section.
echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 [options] <data> <dest-lat-dir> <src-lat-dir1> <src-lat-dir2> ..."
  echo "e.g.: $0 --num-jobs 32 data/train exp/tri3_lat_combined exp/tri3_lat_1 exp_tri3_lat_2"
  echo "Options:"
  echo " --extra-files <file1 file2...>   # specify addtional files in 'src-lat-dir1' to copy"
  echo " --num-jobs <nj>                  # number of jobs used to split the data directory."
  echo " Note, files that don't appear in the first source dir will not be added even if they appear in later ones."
  echo " Other than lattices, only files from the first src lat dir are copied."
  exit 1;
fi

data=$1;
shift;
dest=$1;
shift;
first_src=$1;

if [ ! -f $data/spk2utt ];then
  echo "$0: no file $data/spk2utt (error usage?)"
  exit 1;
fi

mkdir -p $dest;
rm $dest/{lat.*.gz,num_jobs} 2>/dev/null

export LC_ALL=C

for dir in $*; do
  if [ ! -f $dir/lat.1.gz ]; then
    echo "$0: check if lattices (lat.*.gz) are present in $dir."
    exit 1;
  fi
done

for dir in $*; do
  for f in tree; do
    diff $first_src/$f $dir/$f 1>/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "$0: Cannot combine lattice directories with different $f files."
    fi
  done
done

for f in final.mdl tree cmvn_opts num_jobs splice_opts $extra_files; do
  if [ ! -f $first_src/$f ]; then
    echo "combine_lat_dir.sh: no such file $first_src/$f"
    exit 1;
  fi
  cp $first_src/$f $dest/
done

src_id=0
temp_dir=$dest/temp
[ -d $temp_dir ] && rm -r $temp_dir;
mkdir -p $temp_dir
echo "$0: dumping lattices in each source directory as single archive and index."
for dir in $*; do
  src_id=$((src_id + 1))
  cur_num_jobs=$(cat $dir/num_jobs) || exit 1;
  lats=$(for n in $(seq $cur_num_jobs); do echo -n "$dir/lat.$n.gz "; done)
  $cmd $dir/log/copy_lattices.log \
    lattice-copy "ark:gunzip -c $lats|" \
    ark,scp:$temp_dir/lat.$src_id.ark,$temp_dir/lat.$src_id.scp || exit 1 &
  sleep 10
done
wait
sleep 5
sort -m $temp_dir/lat.*.scp > $temp_dir/lat.scp || exit 1;

echo "$0: splitting data to get reference utt2spk for individual lat.JOB.gz files."
utils/split_data.sh $data $num_jobs || exit 1;

echo "$0: splitting the lattices to appropriate chunks according to the reference utt2spk files."
utils/filter_scps.pl JOB=1:$num_jobs \
  $data/split$num_jobs/JOB/utt2spk $temp_dir/lat.scp $temp_dir/lat.JOB.scp

for i in `seq 1 $num_jobs`; do
    lattice-copy scp:$temp_dir/lat.${i}.scp "ark:|gzip -c >$dest/lat.$i.gz" || exit 1 &
done
wait

echo $num_jobs > $dest/num_jobs  || exit 1

echo "$0: checking the lattice files generated have at least 90% of the utterances."
for i in `seq 1 $num_jobs`; do
  num_lines=`cat $temp_dir/lat.$i.scp | wc -l` || exit 1;
  num_lines_tot=`cat $data/split$num_jobs/$i/utt2spk | wc -l` || exit 1;
  python -c "import sys;
percent = 100.0 * float($num_lines) / $num_lines_tot
if percent < 90 :
  print ('$dest/lat.$i.gz {0}% utterances missing.'.format(percent))"  || exit 1;
done
rm -r $temp_dir 2>/dev/null

echo "Combined lattices and stored in $dest"
exit 0
