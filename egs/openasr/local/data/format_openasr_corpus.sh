
set -e

# echo "Format openasr-data-01-raw -> openasr-data-01"

# srcdir=/data/openasr-data-01-raw
# todir=/data/openasr-data-01


audio_postfix="*.m4a"
echo "Format openasr-data-02-raw -> openasr-data-02"

srcdir=/data/openasr-data-02-raw/audios
todir=/data/openasr-data-02
mkdir -p $todir

# rm -rf $todir/{data/train,data/test,doc,tmp}
# mkdir -p $todir/{data/train,data/test,doc,tmp} || exit 1;


# find $srcdir -iname "*.m4a" >$todir/tmp/raws.find || exit 1;
# find $srcdir -iname "*.flac" >>$todir/tmp/raws.find

# cat $srcdir/*/transcriptions >$todir/tmp/trans.txt

wc -l $todir/tmp/*

# chmod +x local/*

cat $todir/tmp/raws.find | head -n 1000 >$todir/tmp/raws.find.1000
head -n 1000 $todir/tmp/trans.txt >$todir/tmp/trans.txt.1000
python local/data/format_openasr_corpus.py $todir/tmp/raws.find.1000 $todir/tmp/trans.txt.1000 $todir/data/train $todir/doc || exit 1;

python local/data/format_openasr_corpus.py $todir/tmp/raws.find $todir/tmp/trans.txt $todir/data/train $todir/doc || exit 1;

head -n 1000 $todir/doc/ffmpeg.cmd >$todir/doc/ffmpeg.test
# head $todir/doc/transcriptions.all

parallel -j12 -a $todir/doc/ffmpeg.test || exit 1;

echo "Parallel to wav(long time)..."
parallel -j12 -a $todir/doc/ffmpeg.cmd || exit 1;

echo "===== Split Train/Test ====="

echo "$0 DONE!"
exit 0
