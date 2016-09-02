
set -e

. ./path.sh

export LC_$x=C

srcdir=/data/noise-data/whitepink
rm -rf $srcdir/{white,pink}
mkdir -p $srcdir/{white,pink}


dir=datanoise/noisesets/whitepink
rm -rf $dir/{train,test}
mkdir -p $dir/{train,test}

for x in train test;do
    for n in white pink;do
        echo "Noise: $n"
        for i in $(seq 50);do
            echo -n "$i,"
            wavname=`date +%s%N | md5sum | awk '{print $1;}'`
            wavname="${n}_$wavname"
            wavfile=$srcdir/$n/$wavname.wav
            sox -n -r 16000 -c 1 -b 16 $wavfile synth 10 ${n}noise
            echo "$wavname $wavfile" >> $dir/$x/wav.scp
            echo "$wavname $n" >> $dir/$x/utt2spk
            echo "$wavname $n" >> $dir/$x/text
            echo "$wavname 10" >> $dir/$x/utt2dur
        done
        sort $dir/$x/utt2spk -o $dir/$x/utt2spk
        utils/utt2spk_to_spk2utt.pl $dir/$x/utt2spk  > $dir/$x/spk2utt
    done

    utils/fix_data_dir.sh $dir/$x
done


# # split Train/Test
# utils/subset_data_dir_tr_cv.sh  --cv-utt-percent 50 $dir/$x $dir/train $dir/test

# utils/fix_data_dir.sh $dir/train
# utils/fix_data_dir.sh $dir/test
