


COURPUS_ROOT=/data/voxpop

corpus=${COURPUS_ROOT}
dir=$COURPUS_ROOT

mkdir -p tmp

dict=$dir/doc/cmudict_merge_cmu07_20140625.dic.ps.kaldi

dos2unix $dict

# sed -i 's/<s>/ /g' $corpus/doc/all_trans.txt
# sed -i 's/<\/s>/ /g' $corpus/doc/all_trans.txt
# sed -i 's/<sil>/ /g' $corpus/doc/all_trans.txt


# for file in cmu07_20140625_stressed.sdic.kaldi all_trans.txt; do
# 	sed -i 's=([0-9]\+)= =g' $corpus/doc/$file
# 	sed -i 's= \+= =g' $corpus/doc/$file
# done

# sed -i 's/WI FI/WIFI/g' $corpus/doc/all_trans.txt


cat $dict | sort | uniq >$dict.uniq

dict=$dict.uniq
## 词典
cp $dict $dir/doc/words_trans.txt
cp $dict $dir/doc/decode_lexicon.txt


## 移除trans标点符号



