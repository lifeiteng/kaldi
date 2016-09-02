
set -e

. ./path.sh

export LC_ALL=C

srcdir=/data/noise-data/CHiME4/CHiME3/

dir=datanoise/noisesets/chime4

# rm -rf $dir/all
# mkdir -p $dir/all

# find $srcdir -iname "*.wav" >tmp/noise.wav

# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150211_030_STR.CH3.wav
# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150204_030_CAF.CH1.wav
# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150203_010_CAF.CH4.wav
# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150212_040_STR.CH1.wav
# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150211_020_STR.CH6.wav
# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150203_010_STR.CH6.wav
# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150204_020_CAF.CH5.wav
# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150203_010_PED.CH4.wav
# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150204_030_BUS.CH6.wav
# # /data/noise-data/CHiME4/CHiME3/data/audio/16kHz/backgrounds/BGD_150204_030_CAF.CH4.wav

# cat tmp/noise.wav | perl -ane 'm/^(.*\/backgrounds\/((\w+)_\d+_(\w+)).(\w+).wav)/ || die; print "$4_$2_$5 $1\n"' | \
#     awk '{print tolower($1), $2;}' | sort -k1 -n >$dir/all/wav.scp
# cat tmp/noise.wav | perl -ane 'm/^(.*\/backgrounds\/((\w+)_\d+_(\w+)).(\w+).wav)/ || die; print "$4_$2_$5 $4\n"' | \
#     awk '{print tolower($0);}' | sort -k1 -n >$dir/all/text

# cp $dir/all/text $dir/all/utt2spk

# utils/utt2spk_to_spk2utt.pl $dir/all/utt2spk > $dir/all/spk2utt
# wav-to-duration scp:$dir/all/wav.scp ark,t:$dir/all/utt2dur || exit 1;

# utils/fix_data_dir.sh $dir/all

# split Train/Test
rm -rf $dir/train $dir/test
# utils/subset_data_dir_tr_cv.sh --cv-utt-percent 1 $dir/all $dir/train $dir/test

utils/subset_data_dir.sh --per-spk $dir/all 1 $dir/test
utils/copy_data_dir.sh $dir/all $dir/train

awk 'FNR==NR{T[$1]=1;} FNR<NR{if(!($1 in T)) print $0;}' $dir/test/text $dir/all/text >$dir/train/text

utils/fix_data_dir.sh $dir/train
utils/fix_data_dir.sh $dir/test
