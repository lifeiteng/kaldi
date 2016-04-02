


echo "Format openasr-data-01-raw -> openasr-data-01"
srcdir=/data/openasr-data-01-raw
todir=/data/openasr-data-01
# rm -rf $todir/doc
# rm -rf $todir/data/train
# rm -rf $todir/data/test

mkdir -p $todir/{data/train,data/test,doc,tmp}
# rm -rf $todir/{data/train,data/test,doc,tmp}

# find $srcdir -iname "*raw" >$todir/tmp/raws.find
# cat $srcdir/*/transcriptions >$todir/tmp/trans.txt

wc -l $todir/tmp/*

# chmod +x local/*

# $todir/tmp/raws.find | sort -R | head -n 100 >$todir/tmp/raws.find.1000
# head -n 100 $todir/tmp/trans.txt >$todir/tmp/trans.txt.1000
python local/format_openasr_corpus.py $todir/tmp/raws.find $todir/tmp/trans.txt $todir/data/train $todir/doc || exit 1;

# head $todir/doc/ffmpeg.cmd
# sort -R $todir/doc/ffmpeg.cmd | head -n 100 >$todir/doc/ffmpeg.test
# head $todir/doc/transcriptions.all

# parallel -j12 -a $todir/doc/ffmpeg.test
# exit 1;

echo "Parallel to wav(long time)..."
parallel -j12 -a $todir/doc/ffmpeg.cmd || exit 1;

echo "===== TODO Split Train/Test ====="

# echo "$0 DONE!"
exit 0
