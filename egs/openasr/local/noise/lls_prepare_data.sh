
set -e

. ./path.sh

export LC_ALL=C

mm=40  #  当噪声数据文件数大于此数字时 才会挑选部分条目作为测试噪音
test_num=10 

srcdir=/data/noise-data/LLS1/wave
dir=datanoise/lls1

mkdir -p $dir/train

find $srcdir -iname "*.wav" >tmp/noise.wav

# /data/noise-data/LLS1/wave/street/600005_2361_android_street.wav
# wav.scp
#   600005_2361_android_street /data/noise-data/LLS1/wave/street/600005_2361_android_street.wav
# utt2spk
#   600005_2361_android_street street

cat tmp/noise.wav | perl -ane 'm/^(.*\/wave\/(\w+)\/(\w+).wav)/ || die; print "$2_$3 $1\n"' | sort -k1 -n >$dir/train/wav.scp
cat tmp/noise.wav | perl -ane 'm/^(.*\/wave\/(\w+)\/(\w+).wav)/ || die; print "$2_$3 $2\n"' | sort -k1 -n >$dir/train/text
cp $dir/train/text $dir/train/utt2spk

utils/utt2spk_to_spk2utt.pl $dir/train/utt2spk > $dir/train/spk2utt
wav-to-duration scp:$dir/train/wav.scp ark,t:$dir/train/utt2dur || exit 1;

utils/fix_data_dir.sh $dir/train


# split Train/Test
utils/subset_data_dir.sh --per-spk $dir/train $test_num $dir/test

awk -v m=$mm '{if(NF > m) print $1 }' $dir/train/spk2utt >tmp/test.keep
awk 'FNR==NR{T[$1]=1;} FNR<NR{if($1 in T) print $0;}' tmp/test.keep $dir/train/spk2utt >$dir/test/spk2utt
utils/spk2utt_to_utt2spk.pl $dir/test/spk2utt >$dir/test/utt2spk
utils/fix_data_dir.sh $dir/test

cp $dir/train/utt2spk tmp
awk 'FNR==NR{T[$1]=1;} FNR<NR{if (!($1 in T)) print $0;}' $dir/test/utt2spk tmp/utt2spk >$dir/train/utt2spk

utils/fix_data_dir.sh $dir/train

