#!/bin/bash

# Feiteng 
# 2014.12.23 2014.12.25 
# 2015.01.14
#
#
#
#
#
# Begin configuration
train=false
dev=false
test=false

data=data
wavdir=/data/JAJASTNS140915A/wav
corpusname=jp

# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;
 

export LC_ALL=C
export LC_ALL=C


tmpdir=$data/local/tmp
mkdir -p $tmpdir


if $train;then
	export LC_ALL=C
	echo "========================Train==========================="
	cat etc/${corpusname}_train.fileids | awk '{printf("/data/King-ASR-064/data/%s.wav\n", $1);}' > $tmpdir/train.flist
	dir=$data/train
	mkdir -p $dir 
	export LC_ALL=C
	python local/make_trans.py trn $tmpdir/train.flist etc/${corpusname}_train.transcription >(sort -k1 -n >$dir/text) >(sort -k1 -n >$dir/wav.scp)
	sleep 2
    sed -i 's/<s>//g' $dir/text
    sed -i 's/<\/s>//g' $dir/text
    sed -i 's/<sil>//g' $dir/text

	cat $dir/wav.scp | perl -ane 'm/^(\w+_(\w+)_engzo_\w+) / || die; print "$1 $2\n"' > $dir/utt2spk

	utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt
fi


if $test;then
	echo "========================Test==========================="
	cat etc/${corpusname}_test.fileids | awk '{printf("/data/King-ASR-064/data/%s.wav\n", $1);}'  > $tmpdir/test.flist
	dir=$data/test
	mkdir -p $dir
	python local/make_trans.py tst $tmpdir/test.flist etc/${corpusname}_test.transcription >(sort -k1 >$dir/text) \
		>(sort -k1 >$dir/wav.scp)
	sleep 2
	sed -i 's/<s>//g' $dir/text
    sed -i 's/<\/s>//g' $dir/text
    sed -i 's/<sil>//g' $dir/text

	cat $dir/wav.scp | perl -ane 'm/^(\w+_(\w+)_engzo_\w+) / || die; print "$1 $2\n"' > $dir/utt2spk
	utils/utt2spk_to_spk2utt.pl $dir/utt2spk | sort > $dir/spk2utt
fi

# if $train;then
# 	export LC_ALL=C
# 	echo "========================Train==========================="
# 	cat etc/${corpusname}_train.fileids | sort -k1 | awk '{printf("/data/JAJASTNS140915A/wav/%s.wav\n", $1);}' | sort > $tmpdir/train.flist
# 	dir=$data/train
# 	mkdir -p $dir 
# 	export LC_ALL=C
# 	local/make_trans.pl trn $tmpdir/train.flist etc/${corpusname}_train.transcription >(sort -k1 >$dir/text) \
# 		>(sort -k1 >$dir/wav.scp)
# 	sleep 2
#     sed -i 's/<s>//g' $dir/text
#     sed -i 's/<\/s>//g' $dir/text
#     sed -i 's/<sil>//g' $dir/text

# 	cat $dir/wav.scp | perl -ane 'm/^((\w+)_\w+_\w+) / || die; print "$1 $2\n"' | sort -s | uniq  > $dir/utt2spk

# 	utils/utt2spk_to_spk2utt.pl $dir/utt2spk | sort > $dir/spk2utt
# fi


# if $test;then
# 	echo "========================Test==========================="
# 	cat etc/${corpusname}_test.fileids | sort | awk '{printf("/data/JAJASTNS140915A/wav/%s.wav\n", $1);}'  | sort > $tmpdir/test.flist
# 	dir=data/test
# 	mkdir -p $dir
# 	local/make_trans.pl tst $tmpdir/test.flist etc/${corpusname}_test.transcription >(sort -k1 >$dir/text) \
# 		>(sort -k1 >$dir/wav.scp)
# 	sleep 2
# 	sed -i 's/<s>//g' $dir/text
#     sed -i 's/<\/s>//g' $dir/text
#     sed -i 's/<sil>//g' $dir/text

# 	cat $dir/wav.scp | perl -ane 'm/^((\w+)_\w+_\w+) / || die; print "$1 $2\n"' > $dir/utt2spk
# 	utils/utt2spk_to_spk2utt.pl $dir/utt2spk | sort > $dir/spk2utt
# fi



echo "##### std_prepare_data.sh succeeded."





