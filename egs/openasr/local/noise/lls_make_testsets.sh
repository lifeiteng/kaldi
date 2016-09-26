
. ./path.sh

# 准备测试数据集
srcdir=asr-testsets/eng/non-native-readaloud

llsnoise=/home/feiteng/openasr/datanoise/noisesets/lls1/test

dir=datanoise/testsets

if [ ! -d $dir/clean ];then
    utils/copy_data_dir.sh $srcdir $dir/clean
fi

chmod +x local/noise/addnoise.py

# # bus SNR 5 10 15 20 25
# # home SNR 5 10 15 20 25
# # mixed(all test noise types) SNR 5 10 15 20 25

# # for noise in white pink;do
# for noise in bus home mixed;do
#     # for snr in 5 10 15 20 25;do
#     for snr in -15 -5 0;do
#         echo "Noise type: $noise, SNR: $snr"
#         # utils/copy_data_dir.sh $srcdir $dir/noise$noise-snr$snr
#         rm -rf $dir/snr$snr-noise-$noise
#         local/noise/addnoise.py --random-seed 0 --snr-db $snr --noise $noise --noise-data-dir $llsnoise \
#             --input-data-dir $srcdir --output-data-dir $dir/snr$snr-noise-$noise || exit 1;
#     done
# done


# for x in train test;do
#     utils/combine_data.sh datanoise/noisesets/combined/$x \
#         datanoise/noisesets/chime4/$x datanoise/noisesets/demand/$x \
#         datanoise/noisesets/lls1/$x datanoise/noisesets/whitepink/$x
# done


# # 生成标准测试集合
# srcdir=asr-testsets/eng
# for x in Aug-25-2015-ntv-readaloud Jan-09-2015-nnv-readaloud Mar-17-2015-forum telis2-asr-test-data;do
#     for snr in 0 10 20 30;do
#         echo "Noise type: $noise, SNR: $snr"
#         utils/copy_data_dir.sh $srcdir/$x $srcdir/${x}-snr$snr
#         rm -rf $srcdir/${x}-snr$snr
#         local/noise/addnoise.py --random-seed 0 --snr-db-range \"$[$snr-5],$[$snr+5]\" --noise "mixed" --noise-data-dir asr-noisesets/combined/test \
#             --input-data-dir $srcdir/$x --output-data-dir $srcdir/${x}-snr$snr || exit 1;
#     done
# done

srcdir=asr-testsets/eng
for x in Aug-25-2015-ntv-readaloud Jan-09-2015-nnv-readaloud Mar-17-2015-forum telis2-asr-test-data;do
    snr=0-30
    echo "Noise type: $noise, SNR: $snr"
    utils/copy_data_dir.sh $srcdir/$x $srcdir/${x}-snr$snr
    rm -rf $srcdir/${x}-snr$snr
    local/noise/addnoise.py --random-seed 0 --snr-db-range \"0,30\" --noise "mixed" --noise-data-dir asr-noisesets/combined/test \
        --input-data-dir $srcdir/$x --output-data-dir $srcdir/${x}-snr$snr || exit 1;
done
