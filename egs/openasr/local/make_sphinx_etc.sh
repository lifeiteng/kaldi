







lang=de_de

data=data
etc=etc


# echo "make $etc/$lang.dic dict(ok)"
# read GOON
# if [ $GOON = 'ok' ];then
# 	echo "dict is ok!"
# else
# 	exit 1;
# fi

# echo "make $etc/$lang.phone $etc/$lang.filler"

# grep -v "#" $data/lang/phones.txt  >$etc/phones.txt.tmp
# grep -v "<eps>" $etc/phones.txt.tmp | cut -d" " -f1 >$etc/$lang.phone
# rm $etc/phones.txt.tmp

# echo "<s> SIL
# </s> SIL
# <sil> SIL" >$etc/$lang.filler


echo "make data"
# for x in train test;do
# 	echo "make $etc/${lang}_$x.fileids $etc/${lang}_$x.transcription"
# 	l1=`wc -l $data/$x/wav.scp`
# 	l2=`wc -l $data/$x/text`
# 	# if [ ! "$l1" = "$l2" ];then
# 	# 	echo "ERROR: wav number $l1 != transcription number $l2."
# 	# 	exit 1;
# 	# fi
    
#     cat $data/$x/wav.scp | perl -ane 'm/^(\w+)  ((.+)\/(\w+)\.wav)/ || die; print "$1 $4 $2\n"' > $etc/$x-wav.scp
    
#     echo "$etc/${lang}_$x.transcription"
# 	awk 'FNR==NR{k=$1; $1=""; T[k]=$0;} FNR<NR{if(!($1 in T)){ exit 1;} else {printf("<s> %s </s> (%s)\n", T[$1], $2);} }' $data/$x/text $etc/$x-wav.scp >$etc/${lang}_$x.transcription

# 	cut -d" " -f3 $etc/$x-wav.scp > $etc/${lang}_$x.fileids
#     sed -i 's/\.wav//g' $etc/${lang}_$x.fileids
# 	# cut -d" " -f2 $data/$x/wav.scp > $etc/$lang_$x.fileids
# 	# cut -d" " -f2 $data/$x/text > $etc/$lang_$x.transcription
# done

# echo "make ug LM"

# echo "Sphinx LM"
DIR=~/NewSphinxTrain/sphinxbase/src/sphinx_lmtools/

for df in ug bg tg;do
	LM=data/local/lm/lm_$df.arpa
	$DIR/sphinx_lm_sort <$LM >$LM.sort
	$DIR/sphinx_lm_convert -i $LM.sort -o $LM.lm.DMP
	cp $LM.lm.DMP $etc/${lang}_$df.lm.DMP
done

cp data/local/lm/lm_ug.arpa.lm.DMP $etc/$lang.lm.DMP




