
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

# for noise in white pink;do
for noise in bus home mixed;do
    # for snr in 5 10 15 20 25;do
    for snr in -15 -5 0;do
        echo "Noise type: $noise, SNR: $snr"
        # utils/copy_data_dir.sh $srcdir $dir/noise$noise-snr$snr
        rm -rf $dir/snr$snr-noise-$noise
        local/noise/addnoise.py --random-seed 0 --snr-db $snr --noise $noise --noise-data-dir $llsnoise \
            --input-data-dir $srcdir --output-data-dir $dir/snr$snr-noise-$noise || exit 1;
    done
done


# for x in train test;do
#     utils/combine_data.sh datanoise/noisesets/combined/$x \
#         datanoise/noisesets/chime4/$x datanoise/noisesets/demand/$x \
#         datanoise/noisesets/lls1/$x datanoise/noisesets/whitepink/$x
# done

