#!/bin/bash

# Feiteng
# 根据alignment的情况，清除“质量不佳”（音频质量差 or 音频与文本无法对齐）的特征、音频条目

# Begin configuration.
stage=-4 #  This allows restarting after partway, when something when wrong.
cmd=run.pl
mv_wav=false
cp_not_decode_wav=false
cp_retry_wav=false
cp_no_feat_wav=false
align_flag="*"
###rm_wav=false
align_fmllr=false
fix_data=false

# End configuration.

echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "Usage: tools/clear.sh <data-dir> <alignment-dir> <exp-dir>"
   echo "e.g.: tools/clear.sh data/train exp/tri2_ali exp/clear_from_tri2"
   echo "main options (for others, see top of script file)"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo "  --stage <stage>                                  # stage to do partial re-run from."
   exit 1;
fi

data=$1
alidir=$2
dir=$3

mkdir -p $dir

for f in $data/wav.scp $data/text $data/feats.scp; do
  [ ! -f $f ] && echo "clear.sh: no such file $f" && exit 1;
done

alignlog=$alidir/log/align.${align_flag}.log
if $align_fmllr;then
	alignlog=$alidir/log/align_pass2.${align_flag}.log
fi

cat $alignlog | grep "Did not successfully decode" | sed 's/,//g' | cut -d" " -f 8 | \
	awk 'FNR==NR{D[$1]=1} FNR<NR{if(($1 in D)) print $0; }' - $data/wav.scp > $dir/not_decode.wav

cat $alignlog | grep "Retrying utterance " | sed 's/,//g' | cut -d" " -f 5 | \
	awk 'FNR==NR{D[$1]=1} FNR<NR{if(($1 in D)) print $0; }' - $data/wav.scp > $dir/retry.wav

cat $alignlog | grep "No features " | sed 's/,//g' | cut -d" " -f 7 | \
	awk 'FNR==NR{D[$1]=1} FNR<NR{if(($1 in D)) print $0; }' - $data/wav.scp > $dir/no_feat.wav

# WARNING (gmm-align-compiled:main():gmm-align-compiled.cc:104) No features for utterance 4433s2m0nwrt_2171_tst
# WARNING (gmm-align-compiled:main():gmm-align-compiled.cc:104) No features for utterance 4433s2m0nwrt_2173_tst
# WARNING (gmm-align-compiled:main():gmm-align-compiled.cc:104) No features for utterance 4433s2m0nwrt_2197_tst	

awk 'FNR==NR{W[$1]=$2;} FNR<NR{if($1 in W) print W[$1],$0;}' $dir/not_decode.wav $data/text >$dir/badtext
awk 'FNR==NR{W[$1]=$2;} FNR<NR{if($1 in W) print W[$1],$0;}' $dir/retry.wav $data/text >$dir/retrytext
awk 'FNR==NR{W[$1]=$2;} FNR<NR{if($1 in W) print W[$1],$0;}' $dir/no_feat.wav $data/text >$dir/nofeattext

cp $dir/badtext clearwavs
cp $dir/retrytext clearwavs
cp $dir/nofeattext clearwavs

if $cp_not_decode_wav; then
	cut -d" " -f2 $dir/not_decode.wav | perl -ane 'm/((.+)\/(\w+)\/(\w+)\.wav)\s+$/ || next; print " mkdir -p clearwavs/badwavs/$3 \n cp $1  clearwavs/badwavs/$4.wav\n"' >$dir/badtorun.sh
	bash $dir/badtorun.sh
fi

if $cp_retry_wav; then
	cut -d" " -f2 $dir/retry.wav | perl -ane 'm/((.+)\/(\w+)\/(\w+)\.wav)\s+$/ || next; print " mkdir -p clearwavs/retrywavs/$3 \n cp $1  clearwavs/retrywavs/$4.wav\n"' >$dir/retrytorun.sh
	bash $dir/retrytorun.sh
fi

if $cp_no_feat_wav; then
	cut -d" " -f2 $dir/no_feat.wav | perl -ane 'm/((.+)\/(\w+)\/(\w+)\.wav)\s+$/ || next; print " mkdir -p clearwavs/retrywavs/$3 \n cp $1  clearwavs/retrywavs/$4.wav\n"' >$dir/nofeattorun.sh
	bash $dir/nofeattorun.sh
fi

if $mv_wav; then
	# awk 'FNR==NR{D[$1]=1} FNR<NR{if(($1 in D)) print $0; }' $dir/not_decode.wav $data/wav.scp >$dir/not_decode_wav.scp
	# awk 'FNR==NR{D[$1]=1} FNR<NR{if(($1 in D)) print $0; }' $dir/retry.wav $data/wav.scp >$dir/retry_wav.scp
	cut -d" " -f2 $dir/not_decode.wav | perl -ane 'm/((.+)\/(\w+)\/(\w+)\.wav)\s+$/ || next; print " mkdir -p clearwavs/badwavs/$3 \n mv $1  clearwavs/badwavs/$3/$4.wav\n"' >$dir/badtorun.sh
	bash $dir/badtorun.sh

	cut -d" " -f2 $dir/retry.wav | perl -ane 'm/((.+)\/(\w+)\/(\w+)\.wav)\s+$/ || next; print " mkdir -p clearwavs/retrywavs/$3 \n mv $1  clearwavs/retrywavs/$3/$4.wav\n"' >$dir/retrytorun.sh
	bash $dir/retrytorun.sh

	cp $dir/badtext clearwavs
    cp $dir/retrytext clearwavs
fi	

not_decode_lines=`cat $dir/not_decode.wav | wc -l`
retry_lines=`cat $dir/retry.wav | wc -l`
no_feat_lines=`cat $dir/no_feat.wav | wc -l`

if $fix_data; then
	if [ $not_decode_lines != 0 ] || [ $retry_lines != 0 ] || [ $no_feat_lines != 0 ];then
		if [ $not_decode_lines != 0 ]; then
			mv $data/feats.scp $data/feats.scp.clear.back
			awk 'FNR==NR{D[$1]=1} FNR<NR{if(!($1 in D)) print $0; }' $dir/not_decode.wav $data/feats.scp.clear.back >$dir/feats.scp.decode
			cp $dir/feats.scp.decode $data/feats.scp
			utils/fix_data_dir.sh $data
	    fi

	    if [ $retry_lines != 0 ] ;then
	    	cp $data/feats.scp $dir/feats.scp.decode 
			awk 'FNR==NR{D[$1]=1} FNR<NR{if(!($1 in D)) print $0; }' $dir/retry.wav $dir/feats.scp.decode >$data/feats.scp
			utils/fix_data_dir.sh $data
	    fi

	    if [ $no_feat_lines != 0 ] ;then
	    	cp $data/feats.scp $dir/feats.scp.decode 
			awk 'FNR==NR{D[$1]=1} FNR<NR{if(!($1 in D)) print $0; }' $dir/no_feat.wav $dir/feats.scp.decode >$data/feats.scp
			utils/fix_data_dir.sh $data
	    fi

	fi
fi

echo "clear $data dir is done"
