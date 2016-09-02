
set -e

. ./path.sh

export LC_ALL=C

srcdir=/data/noise-data/DEMAND

dir=datanoise/noisesets/demand

rm -rf $dir/all
mkdir -p $dir/all

find $srcdir -iname "*.wav" >tmp/noise.wav

# /data/noise-data/DEMAND/DKITCHEN/ch06.wav
# /data/noise-data/DEMAND/DKITCHEN/ch15.wav
# /data/noise-data/DEMAND/DKITCHEN/ch16.wav
# /data/noise-data/DEMAND/DKITCHEN/ch07.wav

cat tmp/noise.wav | perl -ane 'm/^(.*\/DEMAND\/(\w+)\/(\w+).wav)/ || die; print "$2_$3 $1\n"' | \
    awk '{print tolower($1), $2;}' | sort -k1 -n >$dir/all/wav.scp
cat tmp/noise.wav | perl -ane 'm/^(.*\/DEMAND\/(\w+)\/(\w+).wav)/ || die; print "$2_$3 $2\n"' | \
    awk '{print tolower($0);}' | sort -k1 -n >$dir/all/text

cp $dir/all/text $dir/all/utt2spk

utils/utt2spk_to_spk2utt.pl $dir/all/utt2spk > $dir/all/spk2utt
wav-to-duration scp:$dir/all/wav.scp ark,t:$dir/all/utt2dur || exit 1;

utils/fix_data_dir.sh $dir/all

# split Train/Test
# utils/subset_data_dir_tr_cv.sh --cv-utt-percent 1 $dir/all $dir/train $dir/test

utils/subset_data_dir.sh --per-spk $dir/all 2 $dir/test
utils/copy_data_dir.sh $dir/all $dir/train

awk 'FNR==NR{T[$1]=1;} FNR<NR{if(!($1 in T)) print $0;}' $dir/test/text $dir/all/text >$dir/train/text

utils/fix_data_dir.sh $dir/train
utils/fix_data_dir.sh $dir/test
