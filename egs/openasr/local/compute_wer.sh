#!/bin/bash

njobs=1
stage=-1
skip_frames=1
use_gpu="no"
iter="final"
decode_cmd=run.pl
njobs=6
decode_dir=decode
x=1310

dnn_decode=false

lang=data_fbank/lang
graphdir=exp/fbank40_h4t1024_ReLU/graph_bg
prefix=""
datas="Mar-17-2015-forum  read-aloud-native  read-aloud-non-native"

echo "$0 $@"  # Print the command line for logging
# . cmd.sh
. ./path.sh
. parse_options.sh || exit 1;

if [ $# != 1 ];then
	echo "useage: computer_wer.sh --option optvalue modeldir"
	exit 1;
fi


modeldir=$1


datapath=/llswork1/ASR_testset/eng

for dir in $modeldir ; do
	echo "${dnn_decode}"
	if ${dnn_decode};then
		echo " ------DNN Decoding..."

	    [ ! -f $dir/final.mdl ] && cp $dir/$iter.mdl $dir/final.mdl
		steps/online/nnet2/prepare_online_decoding.sh --feature-type "fbank" \
			$lang "$dir" ${dir}_online || exit 1;
		cp $dir/$iter.mdl ${dir}_online || exit 1;
		# if [ $iter != "final" ];then
		# 	nnet-adjust-priors $dir/$iter.mdl $dir/post.$x.vec ${dir}_online/$iter.mdl
		# fi 

		dir=${dir}_online
		rm -f $dir/WER

		for data in $datas;do
			todir=${dir}/$prefix${decode_dir}_${iter}_$data
			steps/online/nnet2/decode.sh --stage $stage --iter $iter --config conf/decode.config --cmd "$decode_cmd" --nj $njobs \
				$graphdir $datapath/$data $todir

		    echo "$todir WER======="
			grep "WER" $todir/wer_*
			grep "WER" $todir/wer_* >>$dir/WER
	    done
	else
		echo " ------GMM Decoding..."

    	for data in $datas;do
    		todir=${dir}/$prefix${decode_dir}_$data
		    steps/decode_fmllr.sh --stage $stage --config conf/decode.config --nj $njobs --cmd "$decode_cmd" \
		    	$graphdir $datapath/$data $todir
		    
		    echo "$todir WER======="
			grep "WER" $todir/wer_*
			grep "WER" $todir/wer_* >>$dir/WER

	    done
	fi

done

exit 0;
